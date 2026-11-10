-- PROBE (pure, no DDL, aborted transaction) for
-- a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons.sql. Seat: ceo.
-- Run AFTER the definition in the same transaction; it always ends in raise exception, so nothing it does survives.
-- It drives today's pending revisions through the whole cycle without calling a model:
--   tick 1: every revision whose question failed is asked again once, its new question carrying otherFamilyThan;
--   then the new questions are marked failed here (standing in for a second failure);
--   tick 2: each is resubmitted as written from the CEO's reasons (fn_ceo_revision_applies, model 'deterministic'),
--           or parked (and counted as a round);
--   finally a parked revision on a scratch item key shows fn_ceo_decision_next counting it.
do $p$
declare
  v_before int; r1 jsonb; r2 jsonb; v_tagged int; v_new int; v_resub int; v_parked int; v_owed int; v_ok boolean;
  v_rej_before int; v_rej_after int; v_h bigint; v_item text;
begin
  select count(*) into v_before from public.agent_actions a
   where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.revise'
     and not coalesce(a.evidence, '{}'::jsonb) ? 'resubmitted_at' and not coalesce(a.evidence, '{}'::jsonb) ? 'decision_owed'
     and exists (select 1 from public.reasoning_held_question h where h.id = (a.evidence->>'held_id')::bigint and h.status in ('failed', 'expired'));

  r1 := public.fn_ceo_revision_refile();
  select count(*), count(*) filter (where h.request ? 'otherFamilyThan') into v_new, v_tagged
    from public.agent_actions a join public.reasoning_held_question h on h.id = (a.evidence->>'held_id')::bigint
   where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.evidence ? 'other_family_at' and (a.evidence->>'other_family_at')::timestamptz = now();

  update public.reasoning_held_question h set status = 'failed', last_attempt_at = now()
    from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.evidence ? 'other_family_at' and h.id = (a.evidence->>'held_id')::bigint;
  r2 := public.fn_ceo_revision_refile();

  select count(*) filter (where a.evidence ? 'resubmitted_at' and a.evidence ? 'deterministic_at'),
         count(*) filter (where a.evidence ? 'parks'), count(*) filter (where a.evidence ? 'decision_owed')
    into v_resub, v_parked, v_owed
    from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.status = 'pending';

  -- a park is a round: on one real pending revision (rolled back), one park raises fn_ceo_decision_next's count by one
  select a.id, a.detail->>'item_key' into v_h, v_item from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.status = 'pending' order by a.id limit 1;
  if v_h is not null then
    v_rej_before := (public.fn_ceo_decision_next(v_item)->>'rejections')::int;
    update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('parks', coalesce((evidence->>'parks')::int, 0) + 1)
     where id = v_h;
    v_rej_after := (public.fn_ceo_decision_next(v_item)->>'rejections')::int;
  end if;

  v_ok := (r1->>'asked_on_another_family')::int = v_before and v_tagged = v_new
          and (v_resub + v_parked) >= (r1->>'asked_on_another_family')::int
          and (v_h is null or v_rej_after = v_rej_before + 1);
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'failed_revisions_before', v_before, 'tick1', r1, 'new_questions', v_new, 'tagged_other_family', v_tagged,
    'tick2', r2 - 'park_detail', 'park_detail', r2->'park_detail', 'resubmitted_from_reasons', v_resub, 'parked', v_parked, 'owed', v_owed,
    'park_counts_as_round', jsonb_build_object('item', v_item, 'before', v_rej_before, 'after', v_rej_after));
end $p$;
