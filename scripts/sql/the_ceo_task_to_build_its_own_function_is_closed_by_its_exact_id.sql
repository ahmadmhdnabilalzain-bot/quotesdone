-- THE CEO TASK TO BUILD ITS OWN FUNCTION IS CLOSED BY ITS EXACT ID.
--
-- Assigned: ceo. 22 Sep 2026 (raised by the it_engineer audit, SEATS-12).
--
-- ══ MEASURED, htdblwldjkcgjvmqkbeh, 22 Sep 2026 ══════════════════════════════════════════════
--   select task_id, title, state, evidence, closed_at from public.ceo_task where closed_at is null;
--     12 | build the ceo edge function and verify it end to end | open | null | null  (command 17)
--     13 | build the ceo edge function and verify it end to end | open | null | null  (command 18)
--   Both were raised on 8 Sep 2026 from the founder's two WhatsApp commands. The thing they ask for
--   EXISTS: the ceo_agent edge function is deployed and live (v108), it is the seat's own runtime in
--   public.llm_seat_binding (fn = 'ceo_agent', seat = 'ceo'), and resilience_ping calls it on the
--   ceoPlan/judgement path. Nothing re-reads a ceo_task once the work lands, so the CEO's own task
--   list has read "two open tasks" for a fortnight while the deliverable ran in production.
--
-- Closed by EXACT id (the two ids above), never by a title match: an ilike sweep is how the estate
-- closed an unfixed finding on 15 Sep. Each row carries the evidence that closes it.
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_task_to_build_its_own_function_is_closed_by_its_exact_id.sql --apply

update public.ceo_task
   set state = 'done', closed_at = now(),
       evidence = 'ceo_agent is deployed and live (version 108, supabase/functions/ceo_agent/index.ts): '
                  || 'it is the ceo seat''s runtime in public.llm_seat_binding (fn=ceo_agent, seat=ceo), '
                  || 'resilience_ping calls it on the ceoPlan step (action ''judgement'', only when '
                  || 'app_secrets.ceo_model_slot = ''on''), and the seat''s deterministic programme — '
                  || 'fn_ceo_plan_tick, fn_ceo_decisions_evaluate, fn_ceo_decide_report — runs on the '
                  || 'heartbeat every 15 minutes. Verified end to end by the CEO plan of 22 Sep 2026 '
                  || '(ceo_plan id 5, stage "invitations"). Closed by the it_engineer seat audit, 22 Sep 2026.'
 where task_id in (12, 13) and closed_at is null;

do $$
declare v_open int;
begin
  select count(*) into v_open from public.ceo_task where task_id in (12, 13) and closed_at is null;
  if v_open > 0 then raise exception 'ceo_task 12/13 still open after the close (% row(s))', v_open; end if;
  raise notice 'ceo_task 12 and 13 closed with evidence';
end $$;
