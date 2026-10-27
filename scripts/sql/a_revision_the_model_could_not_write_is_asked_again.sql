-- A REVISION THE MODEL COULD NOT WRITE IS ASKED AGAIN, AND A MONTH PLAN'S REVISION CHANGES THE PLAN (ceo, 27 Oct 2026).
--
-- Assigned: ceo (the decision cycle of founder ruling 1059 - a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_
-- the_seat_revises.sql - is the CEO's; each revision is still its originating seat's own reasoning).
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 27 Oct 2026 UTC):
--   * marketing.month_plan (fn_marketing_month_plan_duty) failed 7 days running: "the plan for 2026-11 is not with the
--     founder on 2026-10-27: {sent:false, filed:{why:'marketing owes the CEO a revision'}, with_ceo:true}".
--   * The CEO rejected November's plan twice (ceo_decision_round 4298 and 4299, 12 Oct). Round 2's reasons: "the 12 ideas
--     submitted are word for word the round-1 plan, so none of the changes actually reached the plan".
--   * Marketing's round-2 revision (reasoning_held_question 21509, ceo.revise handoff 163352) FAILED on 13 Oct after its
--     3 tries ("model_failed: no reply", synthesise step client_error). fn_reason_hold keeps a failed row closed and its
--     dedupe key unique, and nothing ever asked again: handoff 163352 has been pending for 15 days, the plan sits
--     'ceo_reviewing', and fn_marketing_month_plan_to_ceo answers "marketing owes the CEO a revision" for ever.
--   * Not marketing alone: EVERY pending ceo.revise handoff is stuck the same way - 151684 (sales_engineer,
--     ceo_experiment:2), 163352 (marketing, marketing_month_plan:2026-11-01), 170729 (marketing, ceo_experiment:3),
--     171906 (customer_support, ceo_experiment:1), each on a held question that failed between 13 and 17 Oct.
-- So the duty was right to fail - the plan really is not with the founder - and the cause is two defects:
--   1. A rejection DID end the cycle (against ruling 1059) whenever the seat's revision question failed.
--   2. On the marketing_month_plan path a revision could not change the plan: fn_ceo_revision_applies appended the
--      seat's text to plan.revisions and left plan.ideas - the list the CEO reviews and the founder is mailed - untouched,
--      which is exactly why the CEO rejected round 2.
--
-- WHAT THIS CHANGES
--   A. fn_ceo_revision_refile() (new, duty ceo.revision_refile, daily): a pending ceo.revise whose held question failed
--      or expired, last tried more than 7 days ago (fn_reason_hold's own window: 3 tries per question per 7 days, so
--      this spends no more than the rule already allows), is asked again under a new dedupe key (':t<n>'). After 3
--      re-filings the CEO is owed the replace/withdraw choice (fn_ceo_decision_owe, the #1128 loop guard's path), never
--      the founder. A fixture subject is never filed (fn_reason_hold), so a demo handoff is skipped, not looped.
--   B. fn_seat_revises_for_the_ceo: the dedupe key carries the re-filing count; a marketing_month_plan revision is also
--      asked for the complete revised idea list (field 'ideas'). Otherwise the canonical body (prosrc md5
--      5caf8616146b5a8c21c09437df032677 equalled production).
--   C. fn_ceo_revision_applies: on the marketing_month_plan path a readable revised list replaces plan.ideas (and the
--      content brief); an unreadable one is refused (UNREADABLE_IDEAS, the row is reasoned again, like
--      UNANSWERED_REVISION); a blank one keeps the list. Otherwise the canonical body (the_ceo_reviews_the_months_video_
--      plan_before_the_founder_sees_it.sql, prosrc md5 21716fe9e8789feefefb54b4dd71a164 equalled production).
-- The founder is not in this loop (ruling 1059): he still receives the month plan once, after the CEO approves it.
-- CREATE OR REPLACE keeps the ACL of B and C; A is new, so it is revoked from public, anon and authenticated.
--
-- Prevented by: scripts/checks/a_revision_the_model_could_not_write_is_asked_again.test.mjs (static + rolled-back
-- production replay: a failed revision is re-filed, a revised idea list reaches the plan, a bad one is refused).
--   node scripts/apply_sql.mjs scripts/sql/a_revision_the_model_could_not_write_is_asked_again.sql --apply --ddl --seat ceo

-- ── B ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_revises_for_the_ceo(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_held bigint; v_fields jsonb;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_held := public.fn_seat_duty_reason(a.agent, a.agent || '.ceo_revision',
    'The CEO sent your submission back (round ' || coalesce(a.detail->>'round', '?') || ', ' || coalesce(a.detail->>'rounds_left', '?')
      || ' more before the CEO must replace or withdraw it). Read each of the CEO''s reasons. Produce a revised version that answers '
      || 'every one of them, or where you are right keep it and answer each reason with evidence. The CEO reviews what you resubmit.',
    '[{"id":"revised","meaning":"the submission is revised so that it answers every reason the CEO gave"},{"id":"defended","meaning":"the submission stands, and each reason is answered with evidence"}]'::jsonb,
    jsonb_build_object('path', a.detail->>'path', 'item_key', a.detail->>'item_key', 'round', a.detail->'round',
                       'ceo_reasons', a.detail->>'reasons', 'submission', a.detail->'version'),
    jsonb_build_object('handoff_id', p_id, 'path', a.detail->>'path', 'item_key', a.detail->>'item_key'),
    'ceo_revision:' || (a.detail->>'item_key') || ':g' || coalesce(a.detail->>'generation', '1') || ':r' || coalesce(a.detail->>'round', '1')
      -- a re-filed question (fn_ceo_revision_refile, after the last one failed) is a new question, not the closed one
      || coalesce(':t' || (a.evidence->>'refiles'), ''));
  v_fields := jsonb_build_array(
    jsonb_build_object('key', 'revision', 'question', 'the revised submission, complete, as the CEO should now review it'),
    jsonb_build_object('key', 'answers', 'question', 'for each of the CEO''s reasons: what changed, or the evidence that answers it'));
  if a.detail->>'path' = 'ceo_experiment' then
    v_fields := v_fields || jsonb_build_array(
      jsonb_build_object('key', 'hypothesis', 'question', 'the revised hypothesis (blank keeps it)'),
      jsonb_build_object('key', 'approach', 'question', 'the revised approach (blank keeps it)'),
      jsonb_build_object('key', 'target', 'question', 'the revised target, a number (blank keeps it)'),
      jsonb_build_object('key', 'days', 'question', 'the revised run length in days, 7 to 365 (blank keeps it)'));
  end if;
  if a.detail->>'path' = 'marketing_month_plan' then
    -- the CEO reviews the idea list itself, so a revision that changes the plan must carry the changed list
    v_fields := v_fields || jsonb_build_array(jsonb_build_object('key', 'ideas', 'question',
      'the complete revised idea list as a JSON array, one object per video with n (1, 2, ...), date (YYYY-MM-DD, a UAE '
      || 'working day in the plan''s month), idea_key, title, hook, film_plan, cta, audience (supplier, customer or both) '
      || 'and why; every change the CEO asked for must be in it. Blank keeps the current list.'));
  end if;
  perform public.fn_ambition_ask_fields(v_held, v_fields);
  return jsonb_build_object('waiting', a.agent || ' revises and resubmits ' || coalesce(a.detail->>'item_key', '?') || ' (held question ' || v_held || ')',
                            'held_id', v_held);
end $fn$;
revoke execute on function public.fn_seat_revises_for_the_ceo(bigint) from public, anon, authenticated;

-- ── C ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_revision_applies(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; a public.agent_actions; v_choice text; v_f jsonb; v_problem text; v jsonb;
  d public.seat_deliberation; e public.ceo_experiment; v_model text; v_target numeric; v_days int; v_revised jsonb;
  v_ideas jsonb; v_month date;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_f := public.fn_ambition_fields(p_result);
  -- a round the CEO has already left takes no revision (checked first, so a stale answer is never re-reasoned)
  select * into a from public.agent_actions where id = (r.subject->>'handoff_id')::bigint and kind = 'handoff';
  if a.id is null or a.status <> 'pending' then
    return jsonb_build_object('applied', true, 'already', 'the CEO has moved on from this round');
  end if;
  -- A revision answers the CEO's reasons; an empty one is not a resubmission and is reasoned again.
  v_problem := public.fn_ceo_reasons_problem(coalesce(v_f->>'answers', '') || ' ' || coalesce(p_result->>'answer', ''));
  if v_problem is not null then
    raise exception using errcode = 'check_violation', message = 'UNANSWERED_REVISION: a revision answers the CEO''s reasons: ' || v_problem;
  end if;
  v_model := coalesce((select m.model_id from public.model_registry m where m.model_id = p_result->>'model'), 'deterministic');

  if a.detail->>'path' = 'seat_deliberation' then
    select * into d from public.seat_deliberation where id = (a.detail->'version'->>'deliberation_id')::bigint;
    -- a deliberation that has no round left (opened before the five-round rule, or at its cap) cannot take the
    -- revision: the CEO is owed the choice instead of the seat's answer failing on every retry
    if d.round >= d.max_rounds then
      v := jsonb_build_object('decision_owed', public.fn_ceo_decision_owe('seat_deliberation', a.detail->>'item_key', a.agent,
             coalesce((a.detail->>'generation')::int, 1), 'revised with no round left in its deliberation (' || d.round || ' of ' || d.max_rounds || ')',
             a.detail->>'reasons', a.detail->'version'));
      update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id,
               'answers', left(coalesce(v_f->>'answers', ''), 3000), 'no_round_left', v) where id = a.id;
      return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'resubmission', v);
    end if;
    v_revised := d.proposal || jsonb_build_object('revision', coalesce(v_f->>'revision', p_result->>'answer'), 'answers_to_the_ceo', v_f->>'answers',
                                                  'revision_choice', v_choice, 'revises_round', a.detail->'round');
    if length(v_revised::text) > 28000 then   -- seat_deliberation.proposal holds 30,000 characters
      v_revised := jsonb_build_object('previous_proposal_cut', left(d.proposal::text, 6000),
        'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 12000), 'answers_to_the_ceo', left(v_f->>'answers', 4000),
        'revision_choice', v_choice, 'revises_round', a.detail->'round');
    end if;
    v := public.fn_seat_deliberation_revise(d.id, v_revised, v_model);
  elsif a.detail->>'path' = 'ceo_experiment' then
    select * into e from public.ceo_experiment where id = (a.detail->'version'->>'experiment_id')::bigint;
    v_target := case when coalesce(v_f->>'target', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_f->>'target')::numeric else e.target end;
    v_days := case when coalesce(v_f->>'days', '') ~ '^\d{1,3}$' and (v_f->>'days')::int between 7 and 365 then (v_f->>'days')::int else e.days end;
    v := jsonb_build_object('experiment_id', public.fn_ceo_experiment_propose(e.proposed_by, e.key,
           coalesce(nullif(btrim(v_f->>'hypothesis'), ''), e.hypothesis), e.metric_key, e.metric_definition, e.baseline, e.baseline_note,
           v_target, e.direction, coalesce(nullif(btrim(v_f->>'approach'), ''), e.approach), e.starts_on, v_days));
  elsif a.detail->>'path' = 'marketing_month_plan' then
    -- THE REVISED LIST REPLACES THE IDEAS (27 Oct 2026): the CEO rejected round 2 of November because the 12 ideas
    -- were word for word round 1 - a revision could only add a note, never change the plan. A list that cannot be read
    -- is refused like an unanswered revision (the row is reasoned again); a blank one keeps the current list.
    v_month := (a.detail->'version'->>'month')::date;
    if coalesce(btrim(v_f->>'ideas'), '') <> '' then
      begin
        v_ideas := (v_f->>'ideas')::jsonb;
      exception when others then
        v_ideas := null;
      end;
      if v_ideas is null or jsonb_typeof(v_ideas) <> 'array' or jsonb_array_length(v_ideas) = 0
         or exists (select 1 from jsonb_array_elements(v_ideas) x
                     where jsonb_typeof(x) <> 'object' or coalesce(x->>'n', '') !~ '^[0-9]{1,2}$'
                        or coalesce(btrim(x->>'title'), '') = ''
                        or coalesce(x->>'date', '') !~ ('^' || to_char(v_month, 'YYYY-MM') || '-(0[1-9]|[12][0-9]|3[01])$')) then
        raise exception using errcode = 'check_violation', message = 'UNREADABLE_IDEAS: the revised idea list must be a JSON array of '
          || 'objects, each with a number n, a title and a date in ' || to_char(v_month, 'YYYY-MM');
      end if;
      perform (x->>'date')::date from jsonb_array_elements(v_ideas) x;   -- 2026-11-31 is refused here (22008), and retried
    end if;
    -- the revision rides on the plan (the founder sees it with the ideas) and goes to the CEO as the next round
    update public.marketing_month_plan
       set content_brief = case when v_ideas is null then content_brief
                                else coalesce(content_brief, '{}'::jsonb) || jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_ideas)), 'ideas', v_ideas) end,
           plan = jsonb_set(case when v_ideas is null then plan else jsonb_set(plan, '{ideas}', v_ideas) end,
                    '{revisions}', coalesce(plan->'revisions', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                    'round', a.detail->'round', 'ceo_reasons', left(a.detail->>'reasons', 3000),
                    'revision', left(coalesce(v_f->>'revision', p_result->>'answer'), 6000), 'answers', left(v_f->>'answers', 3000),
                    'choice', v_choice, 'model', v_model, 'ideas_revised', v_ideas is not null))),
           updated_at = now()
     where month = v_month and status = 'ceo_reviewing';
    if not found then   -- the plan left the CEO (withdrawn, replaced by a new draft, sent): nothing to resubmit
      return jsonb_build_object('applied', true, 'already', 'the plan is no longer with the CEO');
    end if;
    v := public.fn_marketing_month_plan_to_ceo((a.detail->'version'->>'month')::date, true);
  else
    raise exception 'no revision route for a % item (%)', coalesce(a.detail->>'path', '?'), a.detail->>'item_key';
  end if;
  update public.agent_actions
     set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('resubmitted_at', now(), 'held_id', p_id, 'choice', v_choice,
                      'answers', left(coalesce(v_f->>'answers', ''), 3000), 'model', v_model, 'resubmission', v),
         detail = detail || jsonb_build_object('awaiting', 'the CEO decides the resubmitted round')
   where id = a.id;
  return jsonb_build_object('applied', true, 'item_key', a.detail->>'item_key', 'choice', v_choice, 'resubmission', v);
end $fn$;
revoke execute on function public.fn_ceo_revision_applies(bigint, jsonb) from public, anon, authenticated;

-- ── A ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_revision_refile()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; h public.reasoning_held_question; v jsonb; v_n int; v_owe bigint;
  n_refiled int := 0; n_owed int := 0; n_waiting int := 0;
begin
  for a in select * from public.agent_actions
            where kind = 'handoff' and status = 'pending' and detail->>'type' = 'ceo.revise'
              and not coalesce(evidence, '{}'::jsonb) ? 'resubmitted_at'
            order by id
  loop
    select * into h from public.reasoning_held_question where id = (a.evidence->>'held_id')::bigint;
    -- a live question is the seat still working; a failed one inside its 7-day window has spent its 3 tries for now
    if h.id is null or h.status not in ('failed', 'expired') then n_waiting := n_waiting + 1; continue; end if;
    if coalesce(h.last_attempt_at, h.created_at) > now() - interval '7 days' then n_waiting := n_waiting + 1; continue; end if;
    v_n := coalesce((a.evidence->>'refiles')::int, 0);
    if v_n >= 3 then
      -- four questions of three tries each could not produce a revision: the CEO replaces or withdraws (never the founder)
      if not coalesce(a.evidence, '{}'::jsonb) ? 'decision_owed' then
        v_owe := public.fn_ceo_decision_owe(a.detail->>'path', a.detail->>'item_key', a.agent, coalesce((a.detail->>'generation')::int, 1),
          'the seat''s revision could not be reasoned: 4 questions, 3 tries each (last held question ' || h.id || ', ' || h.status || ')',
          a.detail->>'reasons', a.detail->'version');
        update public.agent_actions set evidence = evidence || jsonb_build_object('decision_owed', v_owe, 'decision_owed_at', now()) where id = a.id;
        n_owed := n_owed + 1;
      end if;
      continue;
    end if;
    update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('refiles', v_n + 1) where id = a.id;
    v := public.fn_seat_revises_for_the_ceo(a.id);
    update public.agent_actions
       set evidence = evidence || jsonb_build_object('held_id', v->'held_id', 'waiting', v->>'waiting', 'refiled_at', now(),
                                                     'refiled_after', jsonb_build_object('held_id', h.id, 'status', h.status))
     where id = a.id;
    n_refiled := n_refiled + 1;
  end loop;
  return jsonb_build_object('refiled', n_refiled, 'decision_owed', n_owed, 'still_with_the_seat', n_waiting);
end $fn$;
revoke execute on function public.fn_ceo_revision_refile() from public, anon, authenticated;
grant execute on function public.fn_ceo_revision_refile() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.revision_refile', 'ceo', interval '1 day', 'fn_ceo_revision_refile',
   'Ruling 1059: a rejection never ends the cycle. A ceo.revise whose revision question failed or expired more than 7 days ago is asked again; after 3 re-filings the CEO is owed replace or withdraw.',
   'scripts/sql/a_revision_the_model_could_not_write_is_asked_again.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
