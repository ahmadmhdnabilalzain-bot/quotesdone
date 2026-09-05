-- THE RETIRE ROUTINE HAS A CALLER (6 Sep 2026).
--
-- fn_internal_credential_retire(p_id, p_reason) was recorded inactive / DEFERRED_RUNTIME_IMPLEMENTATION:
-- "deployed and unreachable". credentials_expire_and_rotate_themselves.sql gave it a caller
-- (fn_internal_credential_rotate_due retires each predecessor after the successor is stored), and
-- the exposure board read that as deferred_or_inactive_but_reachable = 1. The record catches up
-- with the estate: the routine is deployed and reached from a traced kernel cron.
--
--   node scripts/apply_sql.mjs scripts/sql/the_retire_routine_has_a_caller.sql --apply --ddl
begin;

update public.phase_c_component
   set activation_state = 'deployed',
       classification = 'WIRE_TO_CANONICAL',
       repair_or_keep_action = 'keep; reached from fn_internal_credential_rotate_due under cron:credential_rotate_daily since 6 Sep 2026 (predecessor retired after each rotation)',
       evidence = coalesce(evidence, '') || ' | 6 Sep 2026: caller fn_internal_credential_rotate_due, traced under cron:credential_rotate_daily'
 where component_id = 'dbfn:fn_internal_credential_retire(p_id bigint, p_reason text)'
   and activation_state = 'inactive';

do $proof$
declare v_bad int;
begin
  select count(*) into v_bad from public.phase_c_component
   where component_id = 'dbfn:fn_internal_credential_retire(p_id bigint, p_reason text)' and activation_state <> 'deployed';
  if v_bad > 0 then raise exception 'fn_internal_credential_retire is still not recorded as deployed'; end if;
  raise notice 'proof: fn_internal_credential_retire recorded deployed with its caller';
end $proof$;

commit;
