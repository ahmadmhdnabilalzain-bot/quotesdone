-- A REVISION THE MODEL CANNOT WRITE IS ASKED ONCE ON ANOTHER FAMILY, THEN WRITTEN FROM THE CEO'S REASONS, AND A
-- PARKED REVISION COUNTS AS A ROUND.
-- Seat: ceo (the decision cycle of founder ruling 1059 is the CEO's; each revision stays its originating seat's own).
-- 10 Nov 2026, ruling 1574 (the company runs on its own with an approval sequence; the founder is not in the loop).
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   * 14 items' last CEO decision is 'rejected' (ceo_decision_round): 3 experiments, 2 marketing month plans and 9
--     seat deliberations, at most 4 rounds. None has reached approval since.
--   * 14 ceo.revise handoffs are pending, none resubmitted. Each one's revision question (reasoning_held_question)
--     FAILED: the synthesis step on the internal_judgement route (model_policy: openai/gpt-6-luna-pro) ended
--     "gateway_http_502: gateway_deadline" or "client_timeout_42193ms" (rows 37857, 37860), 3 tries each. 27 held
--     questions "held after 5 failed reasonings on <seat>.ceo_revision" sit with their seats.
--   * fn_ceo_revision_refile (a_revision_the_model_could_not_write_is_asked_again.sql) waits 7 days after a failure,
--     asks the SAME route again under a new key, and only after 3 re-filings owes the CEO the replace/withdraw choice:
--     up to 28 days on one round, on the route that already failed. The 4-round guard in fn_ceo_decide counts DECIDED
--     rejections only, so a revision that is never written never counts, and the item parks silently.
--
-- WHAT THIS CHANGES (CREATE OR REPLACE keeps each routine's ACL; no new routine, no table):
--   A. fn_ceo_revision_refile: a failed (or expired) revision question is
--        1. asked again ONCE, at once, with request.otherFamilyThan = the class's primary model, so think() sends the
--           synthesis as counterpart_model and the gateway routes it to another family (supabase/functions/_shared/
--           think/engine.ts, think_other_family.test.ts);
--        2. if that fails too, the originating seat resubmits a DETERMINISTIC revision through the same door the model
--           answer uses (fn_ceo_revision_applies, model 'deterministic'): the submission as it stood, with every one of
--           the CEO's reasons accepted as a binding condition, stated as such. Nothing is invented: the text is the
--           CEO's own reasons and the record of what failed. The CEO decides the resubmitted round as usual;
--        3. if even that cannot be applied, the revision is PARKED and the park is a round: fn_ceo_decision_next counts
--           it with the rejections, and at 4 the CEO is owed the replace/withdraw choice (fn_ceo_decision_owe) at once.
--           Under 4, the next tick starts a fresh cycle (another-family re-ask), so a park can never be silent.
--   B. fn_ceo_decision_next: 'rejections' = decided rejections + parked revisions of the same generation. fn_ceo_decide's
--      own guard (a fifth rejection is refused, the CEO is owed the choice) therefore trips on parked rounds too.
-- The founder is never asked (1059). Demo rows are never re-asked (fn_reason_hold files no fixture subject).
--
-- Prevented by: scripts/checks/a_revision_the_model_cannot_write_is_asked_on_another_family.test.mjs (static rules on
-- the canonical bodies, plus a rolled-back production replay that drives the 14 pending revisions through the cycle).
--   node scripts/apply_sql.mjs scripts/sql/a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons.sql --apply --ddl --seat ceo

-- ── B ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_decision_next(p_item_key text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when l.id is null
    then jsonb_build_object('open', true, 'generation', 1, 'round', 1, 'rejections', 0)
    else jsonb_build_object('open', l.decision not in ('approved', 'withdrawn'), 'last_id', l.id, 'last_decision', l.decision,
      'last_round', l.round, 'path', l.path, 'originator', l.originator_seat,
      'generation', case when l.decision = 'replaced' then l.generation + 1 else l.generation end,
      'round', case when l.decision = 'replaced' then 1 else l.round + 1 end,
      -- 10 Nov 2026: a revision that could not be written or applied (PARKED) is a round, counted with the rejections
      'parked', case when l.decision = 'replaced' then 0 else (select coalesce(sum((a.evidence->>'parks')::int), 0) from public.agent_actions a
                     where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.detail->>'item_key' = p_item_key
                       and coalesce((a.detail->>'generation')::int, 1) = l.generation and a.evidence ? 'parks') end,
      'rejections', case when l.decision = 'replaced' then 0
                         else (select count(*) from public.ceo_decision_round r
                                where r.item_key = p_item_key and r.generation = l.generation and r.decision = 'rejected')
                            + (select coalesce(sum((a.evidence->>'parks')::int), 0) from public.agent_actions a
                                where a.kind = 'handoff' and a.detail->>'type' = 'ceo.revise' and a.detail->>'item_key' = p_item_key
                                  and coalesce((a.detail->>'generation')::int, 1) = l.generation and a.evidence ? 'parks') end)
  end
  from (select 1) one
  left join lateral (select * from public.ceo_decision_round r where r.item_key = p_item_key order by r.generation desc, r.round desc limit 1) l on true
$fn$;

-- ── A ─────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_revision_refile()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; h public.reasoning_held_question; v jsonb; v_owe bigint; v_model text; v_new bigint;
  v_reasons text; v_answers text; v_result jsonb; v_next jsonb; v_failed text;
  n_other int := 0; n_det int := 0; n_parked int := 0; n_owed int := 0; n_waiting int := 0; v_errors jsonb := '[]'::jsonb;
begin
  -- the route that failed: the synthesis of a seat's revision runs on the internal_judgement class
  select coalesce(m.model_primary, 'openai/gpt-6-luna-pro') into v_model from public.model_policy m where m.task_class = 'internal_judgement';
  v_model := coalesce(v_model, 'openai/gpt-6-luna-pro');
  for a in select * from public.agent_actions
            where kind = 'handoff' and status = 'pending' and detail->>'type' = 'ceo.revise'
              and not coalesce(evidence, '{}'::jsonb) ? 'resubmitted_at'
              and not coalesce(evidence, '{}'::jsonb) ? 'decision_owed'
            order by id
  loop
    select * into h from public.reasoning_held_question where id = (a.evidence->>'held_id')::bigint;
    -- a live question is the seat still working on it
    if h.id is not null and h.status not in ('failed', 'expired') then n_waiting := n_waiting + 1; continue; end if;
    begin
      if not coalesce(a.evidence, '{}'::jsonb) ? 'other_family_at' then
        -- 1. ONCE, AT ONCE, ON ANOTHER FAMILY
        update public.agent_actions set evidence = coalesce(evidence, '{}'::jsonb)
               || jsonb_build_object('refiles', coalesce((evidence->>'refiles')::int, 0) + 1) where id = a.id;
        select * into a from public.agent_actions where id = a.id;
        v := public.fn_seat_revises_for_the_ceo(a.id);
        v_new := nullif(v->>'held_id', '')::bigint;
        if v_new is not null then
          update public.reasoning_held_question set request = coalesce(request, '{}'::jsonb) || jsonb_build_object('otherFamilyThan', v_model)
           where id = v_new;
        end if;
        update public.agent_actions
           set evidence = evidence || jsonb_build_object('held_id', v_new, 'waiting', v->>'waiting', 'refiled_at', now(),
                            'other_family_at', now(), 'other_family_than', v_model,
                            'refiled_after', jsonb_build_object('held_id', h.id, 'status', coalesce(h.status, 'missing')))
         where id = a.id;
        n_other := n_other + 1;
      elsif not coalesce(a.evidence, '{}'::jsonb) ? 'deterministic_at' then
        -- 2. THE SEAT WRITES IT FROM THE CEO'S REASONS: the submission stands, every reason accepted as a condition
        if h.id is null then raise exception 'no held question to answer for handoff %', a.id; end if;
        v_reasons := coalesce(nullif(btrim(a.detail->>'reasons'), ''), '(the CEO''s reasons are not on the handoff)');
        select string_agg('Accepted as a binding condition of this version: ' || btrim(x), E'\n' order by n)
          into v_answers
          from regexp_split_to_table(v_reasons, E'\\n+|(?<=[.;])\\s+') with ordinality t(x, n) where btrim(x) <> '';
        v_failed := 'held questions ' || coalesce(a.evidence->'refiled_after'->>'held_id', '?') || ' (' || coalesce(a.evidence->>'other_family_than', v_model)
                    || ') and ' || h.id || ' (another family)';
        v_result := jsonb_build_object('model', 'deterministic', 'status', 'answered',
          'answer', 'Deterministic revision by ' || a.agent || ': the model could not write this revision (' || v_failed || ' failed).',
          'decision', jsonb_build_object('choice', 'revised', 'fields', jsonb_build_object(
            'revision', 'Deterministic revision (' || to_char(now(), 'YYYY-MM-DD') || '): the model could not write a revision on two model families ('
                        || v_failed || '). The submission is resubmitted as it stood, with each of the CEO''s round '
                        || coalesce(a.detail->>'round', '?') || ' reasons below accepted as a binding condition of this version. '
                        || 'Nothing else in it is changed, and nothing is added that the CEO did not ask for.' || E'\n\n' || v_reasons,
            'answers', coalesce(v_answers, 'Accepted as a binding condition of this version: ' || v_reasons))));
        v := public.fn_ceo_revision_applies(h.id, v_result);
        update public.agent_actions set evidence = evidence || jsonb_build_object('deterministic_at', now(), 'deterministic_from_held', h.id)
         where id = a.id;
        n_det := n_det + 1;
      else
        -- both were tried and the written revision still did not reach the CEO: that is a park, never a silent wait
        raise exception 'the revision written from the CEO''s reasons did not reach the CEO (handoff %, held question %)', a.id, h.id;
      end if;
    exception when others then
      -- 3. PARKED: the park is a round; at 4 the CEO is owed the replace/withdraw choice now
      -- the next tick starts a fresh cycle (another-family re-ask), and every park is one more round
      update public.agent_actions
         set evidence = (coalesce(evidence, '{}'::jsonb) - 'other_family_at' - 'deterministic_at')
                        || jsonb_build_object('parked_at', now(), 'parks', coalesce((evidence->>'parks')::int, 0) + 1, 'parked_reason', left(sqlerrm, 400))
       where id = a.id;
      n_parked := n_parked + 1;
      v_errors := v_errors || jsonb_build_object('handoff_id', a.id, 'error', left(sqlerrm, 300));
      v_next := public.fn_ceo_decision_next(a.detail->>'item_key');
      if coalesce((v_next->>'rejections')::int, 0) >= 4 then
        v_owe := public.fn_ceo_decision_owe(a.detail->>'path', a.detail->>'item_key', a.agent, coalesce((a.detail->>'generation')::int, 1),
          'rounds spent (' || (v_next->>'rejections') || ', ' || (v_next->>'parked') || ' of them parked: the revision could not be written on two model '
            || 'families nor applied as written from the reasons); the CEO replaces or withdraws it',
          a.detail->>'reasons', a.detail->'version');
        update public.agent_actions set evidence = evidence || jsonb_build_object('decision_owed', v_owe, 'decision_owed_at', now()) where id = a.id;
        n_owed := n_owed + 1;
      end if;
    end;
  end loop;
  return jsonb_build_object('asked_on_another_family', n_other, 'written_from_the_reasons', n_det, 'parked', n_parked,
                            'decision_owed', n_owed, 'still_with_the_seat', n_waiting, 'model_avoided', v_model, 'park_detail', v_errors);
end $fn$;

-- already closed to clients on production (10 Nov 2026); restated so the file says so itself
revoke execute on function public.fn_ceo_decision_next(text) from public, anon, authenticated;
revoke execute on function public.fn_ceo_revision_refile() from public, anon, authenticated;

update public.seat_duty
   set what = 'A seat''s revision the model could not write is asked again once on another model family, then written by the seat from the CEO''s reasons; a revision that still cannot reach the CEO is parked and counted as a round, and at 4 rounds the CEO replaces or withdraws it. Never the founder (1059).',
       owner_file = 'scripts/sql/a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons.sql'
 where duty = 'ceo.revision_refile';

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_ceo_revision_refile()'::regprocedure, 'public.fn_ceo_decision_next(text)'::regprocedure)
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the refile duty is not on its clock' where not exists (select 1 from public.seat_duty where duty = 'ceo.revision_refile' and enabled)
    union all select 'fn_ceo_decision_next does not count parked rounds'
     where position('parks' in (select prosrc from pg_proc where oid = 'public.fn_ceo_decision_next(text)'::regprocedure)) = 0
  ) z) y;
