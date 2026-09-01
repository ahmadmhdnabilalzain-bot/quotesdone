-- OWNERSHIP LEDGER SYNC for the_amendment_reaches_the_step_binding.sql.
--
-- fn_phase_c_step_owner_valid is now canonically defined by the_amendment_reaches_the_step_binding.sql,
-- superseding phase_c_08_runtime_writers.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/the_amendment_reaches_the_step_binding_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_amendment_reaches_the_step_binding.sql',
       evidence = 'records source_file scripts/sql/phase_c_08_runtime_writers.sql, manifest order says scripts/sql/the_amendment_reaches_the_step_binding.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_phase_c_step_owner_valid'
   and coalesce(identity_args,'') = 'p_step_id text, p_owner text';
