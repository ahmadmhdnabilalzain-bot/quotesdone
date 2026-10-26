-- OWNERSHIP LEDGER SYNC for the_marketplace_score_uses_all_eight_inputs.sql.
--
-- fn_company_indices is now canonically defined by the_marketplace_score_uses_all_eight_inputs.sql,
-- superseding phase_c_06_components_part02.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketplace_score_uses_all_eight_inputs_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_marketplace_score_uses_all_eight_inputs.sql',
       evidence = 'recorded HISTORICAL_APPLICATION, repository derives QUOTESDONE_APPLICATION — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_company_indices'
   and coalesce(identity_args,'') = '';
