-- PROBE (pure, no DDL, aborted transaction) for the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql. Seat: it_engineer.
-- Run AFTER the definition (and after the files whose tables it reads: a_parked_model_question_has_an_owner_and_a_deadline.sql
-- and the_it_engineer_runs_the_safe_fix_playbooks_itself.sql) in the same transaction. It ends in raise exception.
-- The digest runs STUBBED (app.qd_stub_founder_notify = on: a test never reaches the founder) at 19:30 Dubai today, after
-- the parked questions are settled and the playbooks have run once, and shows the email it would send.
do $p$
declare v_list jsonb; v jsonb; v_ok boolean;
begin
  perform public.fn_held_questions_settle(5000);
  perform public.fn_it_safe_fix_tick();
  v_list := public.fn_it_session_fix_list();
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  v := public.fn_customer_support_sends_the_it_digest(((now() at time zone 'Asia/Dubai')::date + time '19:30') at time zone 'Asia/Dubai');
  v_ok := jsonb_array_length(v_list) between 1 and 12 and coalesce((v->>'stubbed')::boolean, false)
          and (v->>'session_items')::int = jsonb_array_length(v_list)
          and (v->>'detail') like '%What a working session must fix%'
          and not exists (select 1 from jsonb_array_elements(v_list) x where x->>'line' ~ 'duty:');
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'list', v_list, 'digest_sent', v->'sent', 'decisions', v->'decisions', 'session_items', v->'session_items', 'event', v->'event',
    'detail', left(v->>'detail', 2500), 'reason', v->'reason');
end $p$;
