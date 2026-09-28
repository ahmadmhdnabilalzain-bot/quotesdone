-- THE REVIEW AND THE ROOT-CAUSE HANDOFFS COME BACK TO THE SEAT THAT STARTED THEM.
--
-- Agent: ceo. 29 Sep 2026. Two production checks failed on origin/main 55beee5; both are the same defect class the
-- 23 Sep file the_author_closes_the_review_handoff_and_names_its_kind.sql fixed for marketing.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 29 Sep 2026)
--   1. seat_handoff_kind holds seven ('deliberation.review', author, reviewer) pairs. Only marketing -> ceo is
--      originator_closes. The other six (accountant, customer_support, it_engineer and sales_engineer -> ceo; ceo ->
--      accountant; sales_engineer -> marketing) were inserted without the flag (it_engineer -> ceo and
--      sales_engineer -> ceo by the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql, 24 Sep). Their only closer is
--      fn_seat_deliberation_close, which refuses anyone but the author seat and sets qd.handoff_closer to it; the
--      handler fn_seat_deliberation_acts_on_handoff never completes the handoff (it names neither
--      fn_seat_handoff_complete nor qd.handoff_closer). So the flag was simply wrong: the author closes every review.
--      it_engineer_loop_is_closed.test.mjs failed on (deliberation.review, it_engineer -> ceo, originator_closes false).
--   2. ('ceo.root_cause', ceo -> each of five seats) is originator-closed, and its closer fn_ceo_root_cause_applies
--      does close it as the ceo (qd.handoff_closer = 'ceo') - but never names the kind, so
--      every_report_and_handoff_comes_back.test.mjs cannot tell it is the closer and reported all five orphaned. The
--      completion evidence now records the kind it closes. The body is the canonical one from
--      the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql (md5 of the live prosrc matched the file
--      before this change) with that one key added; CREATE OR REPLACE keeps the ACL and the revoke is restated.
--
-- Prevented by: scripts/checks/it_engineer_loop_is_closed.test.mjs, scripts/checks/every_report_and_handoff_comes_back.test.mjs
-- and the verdict row at the end of this file.
--   node scripts/apply_sql.mjs scripts/sql/the_review_and_root_cause_handoffs_come_back_to_their_author.sql --apply --ddl --seat ceo

begin;

update public.seat_handoff_kind set originator_closes = true
 where type = 'deliberation.review' and not originator_closes;

create or replace function public.fn_ceo_root_cause_applies(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text; v_f jsonb; v_task bigint; v_hid bigint; v_review jsonb;
begin
  v_choice := public.fn_ambition_choice(p_id, p_result);
  select * into r from public.reasoning_held_question where id = p_id;
  v_task := (r.subject->>'task_id')::bigint; v_hid := nullif(r.subject->>'handoff_id', '')::bigint;
  v_f := public.fn_ambition_fields(p_result);
  update public.ceo_task
     set state = case when state = 'open' then 'working' else state end,
         evidence = left(coalesce(evidence || E'\n\n', '') || format(E'Root cause from %s (%s): %s\nCorrective action: %s\nRecovery by: %s',
                           r.seat, v_choice, coalesce(v_f->>'root_cause', '?'), coalesce(v_f->>'corrective_action', '?'), coalesce(v_f->>'recovery_by', '?')), 8000)
   where task_id = v_task;
  if v_hid is not null and exists (select 1 from public.agent_actions where id = v_hid and status = 'pending') then
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('kind', 'ceo.root_cause', 'verified_by', 'ceo', 'root_cause', v_choice, 'fields', v_f, 'held_id', p_id));
    perform set_config('qd.handoff_closer', '', true);
  end if;
  -- the other side reads it on a model of another family: the CEO for a seat's answer, the accountant for the CEO's own
  v_review := public.fn_seat_duty_cross_review(r.seat || '.root_cause', r.seat, case when r.seat = 'ceo' then 'accountant' else 'ceo' end,
    'Challenge this root cause and corrective action for a metric behind the company''s target path.',
    jsonb_build_object('miss', r.request->'context'->'case'), jsonb_build_object('call', v_choice, 'fields', v_f,
    'reasoning', left(coalesce(p_result->>'answer', ''), 3000)), p_result, 'ceo_task', v_task::text);
  insert into public.seat_case_memory (seat, case_kind, source_table, source_id, situation, decision, reasoning, outcome, finalised, lessons, opened_at)
  values (r.seat, 'target_miss', 'ceo_task', v_task::text,
          left(format('%s behind the base-case path: %s', r.subject->>'metric', r.request->'context'->'case'), 4000),
          v_choice, left(coalesce(p_result->>'answer', ''), 4000), null, false,
          case when coalesce(v_f->>'corrective_action', '') <> '' then array[v_f->>'corrective_action'] else '{}'::text[] end, r.created_at)
  on conflict (source_table, source_id) do update set decision = excluded.decision, reasoning = excluded.reasoning, lessons = excluded.lessons, updated_at = now();
  return jsonb_build_object('applied', true, 'task', v_task, 'root_cause', v_choice, 'review', v_review);
end $fn$;
revoke execute on function public.fn_ceo_root_cause_applies(bigint, jsonb) from public, anon, authenticated;

commit;

select case
  when exists (select 1 from public.seat_handoff_kind where type = 'deliberation.review' and not originator_closes)
    then 'PROBE FAILED: a deliberation.review pair is still closed by its receiver'
  when exists (select 1 from public.seat_handoff_kind k where k.originator_closes
                and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                 where n.nspname = 'public' and p.prosrc like '%''' || k.type || '''%'
                                   and (p.prosrc like '%qd.handoff_closer%' or p.prosrc like '%qd.backup_closer%')))
    then 'PROBE FAILED: an originator-closed kind has no routine that closes it by name'
  else 'PROBE OK' end as verdict;
