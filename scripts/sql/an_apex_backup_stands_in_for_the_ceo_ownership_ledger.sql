-- OWNERSHIP LEDGER SYNC for an_apex_backup_stands_in_for_the_ceo.sql.
--
-- fn_should_escalate is now canonically defined by an_apex_backup_stands_in_for_the_ceo.sql, superseding
-- launch_step1_ceo_escalates_to_founder.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/an_apex_backup_stands_in_for_the_ceo_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/an_apex_backup_stands_in_for_the_ceo.sql',
       evidence = 'records source_file scripts/sql/launch_step1_ceo_escalates_to_founder.sql, manifest order says scripts/sql/an_apex_backup_stands_in_for_the_ceo.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_should_escalate'
   and coalesce(identity_args,'') = 'ctx jsonb';
