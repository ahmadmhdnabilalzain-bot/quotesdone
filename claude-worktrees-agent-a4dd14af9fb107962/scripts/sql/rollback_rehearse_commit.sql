-- COMMIT PATH, exercised safely: run the real commit branch inside a DO block that raises at the
-- end, so the whole thing rolls back. This is the only way to reach the code after the rehearsal
-- RAISE - the return, the audit insert, and the post-rollback state - without leaving B.6 removed.
do $t$
declare
  r jsonb;
  again jsonb;
  v_audit int;
  v_survivor int;
  v_removable int;
begin
  r := public.fn_p2c1_rollback_stage_b6('commit', 'ops:p2c1-recovery-session');

  -- the commit branch returns rather than raising, so the audit row is now visible
  select count(*) into v_audit from public.inquiry_state_audit
   where event = 'p2c1_stage_b6_rollback_commit';

  -- state after a completed rollback
  select count(*) into v_removable from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname in ('inquiry_scope_disposition','scope_marker',
     'scope_disposition_kind','scope_component','p2c1_disposition_case','p2c1_holdout_case',
     'p2c1_holdout_seal','v_scope_disposition_effective','v_trade_scope_status');

  select count(*) into v_survivor from public.p2c1_holdout_result_of_record;

  -- re-running after a completed rollback must be a no-op, not a second teardown
  again := public.fn_p2c1_rollback_stage_b6('commit', 'ops:p2c1-recovery-session');

  raise exception E'COMMIT PATH REHEARSAL (rolled back)\naudit rows written: %\nremovable B.6 relations left: %\naudit-evidence rows surviving: %\nre-run response: %\nreport verdict: %\nreport tests: %',
    v_audit, v_removable, v_survivor, again::text, r->>'verdict', (r->'tests')::text;
end
$t$;
