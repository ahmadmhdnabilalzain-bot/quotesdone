-- OWNERSHIP LEDGER SYNC for the_measurement_spine_carries_a_signal.sql.
--
-- fn_kpi_review is now canonically defined by the_measurement_spine_carries_a_signal.sql (the last
-- manifest file that defines it), superseding the_missed_kpi_opens_remediation.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/the_measurement_spine_carries_a_signal_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_measurement_spine_carries_a_signal.sql',
       evidence = 'records source_file scripts/sql/the_missed_kpi_opens_remediation.sql, manifest order says scripts/sql/the_measurement_spine_carries_a_signal.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_kpi_review'
   and coalesce(identity_args,'') = '';
