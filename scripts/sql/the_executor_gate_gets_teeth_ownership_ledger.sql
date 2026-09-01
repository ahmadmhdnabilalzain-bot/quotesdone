-- OWNERSHIP LEDGER SYNC for the_executor_gate_gets_teeth.sql.
--
-- fn_action_invoke_dispatch is now canonically defined by the_executor_gate_gets_teeth.sql, superseding
-- spend_contract_dispatch_needs_two.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/the_executor_gate_gets_teeth_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_executor_gate_gets_teeth.sql',
       evidence = 'records source_file scripts/sql/spend_contract_dispatch_needs_two.sql, manifest order says scripts/sql/the_executor_gate_gets_teeth.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_action_invoke_dispatch'
   and coalesce(identity_args,'') = 'p_limit integer';
