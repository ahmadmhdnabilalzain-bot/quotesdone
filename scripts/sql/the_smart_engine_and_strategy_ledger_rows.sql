-- OWNERSHIP LEDGER FOLLOWS THE MANIFEST — fn_agents_board and fn_ws_strategy (6 Sep 2026).
--
-- Both were defined only in migrations_history files, so the ledger recorded them
-- HISTORICAL_APPLICATION. The OS button audit redefined them in the manifest
-- (smart_engine_lists_staff_not_the_parked.sql, strategy_simulations_carry_their_question.sql) and
-- the source-of-truth gate reported the disagreement. This reconciles the ledger to the manifest;
-- bookkeeping only.
--
--   node scripts/apply_sql.mjs scripts/sql/the_smart_engine_and_strategy_ledger_rows.sql --apply --ddl

begin;

update public.kernel_routine_ownership k set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = m.file,
       evidence = 'recorded HISTORICAL_APPLICATION, repository derives QUOTESDONE_APPLICATION from the manifest — reconciled 6 Sep 2026 (OS button audit).',
       recorded_at = now()
  from (values ('fn_agents_board', 'scripts/sql/smart_engine_lists_staff_not_the_parked.sql'),
               ('fn_ws_strategy',  'scripts/sql/strategy_simulations_carry_their_question.sql')) m(routine, file)
 where k.schema_name = 'public' and k.routine_name = m.routine and coalesce(k.identity_args, '') = '';

do $proof$
declare v int;
begin
  select count(*) into v from public.kernel_routine_ownership
   where schema_name = 'public' and routine_name in ('fn_agents_board', 'fn_ws_strategy')
     and ownership_class = 'QUOTESDONE_APPLICATION';
  if v <> 2 then raise exception 'expected 2 ledger rows re-pointed, got %', v; end if;
  raise notice 'proof: fn_agents_board and fn_ws_strategy owned by manifest files';
end $proof$;

commit;
