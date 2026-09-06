-- OWNERSHIP LEDGER FOLLOWS THE MANIFEST — fn_os_automation_list is owned by
-- scripts/sql/the_automation_page_answers_in_under_a_second.sql (6 Sep 2026).
--
-- fn_os_automation_list was defined only in a migrations_history file
-- (20260724173529_phase2_automation_backend.sql), so the ledger recorded it HISTORICAL_APPLICATION
-- and the canonical engine read the new full definition as "canonical body not deployed". The
-- manifest names the new file; this reconciles the ledger to the manifest. Bookkeeping only.
--
--   node scripts/apply_sql.mjs scripts/sql/the_automation_list_ownership_ledger.sql --apply --ddl

begin;

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_automation_page_answers_in_under_a_second.sql',
       evidence = 'recorded HISTORICAL_APPLICATION (migrations_history 20260724173529), repository derives QUOTESDONE_APPLICATION from the manifest — reconciled 6 Sep 2026 when the routine was rewritten to answer in under a second.',
       recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_os_automation_list'
   and coalesce(identity_args,'') = '';

do $proof$
declare v int;
begin
  select count(*) into v from public.kernel_routine_ownership
   where schema_name = 'public' and routine_name = 'fn_os_automation_list'
     and source_file = 'scripts/sql/the_automation_page_answers_in_under_a_second.sql';
  if v <> 1 then raise exception 'ledger row for fn_os_automation_list not re-pointed (% rows)', v; end if;
  raise notice 'proof: fn_os_automation_list owned by the manifest file';
end $proof$;

commit;
