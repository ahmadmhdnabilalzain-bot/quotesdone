-- OWNERSHIP LEDGER SYNC for unclassified_work_escalates.sql.
--
-- fn_agent_action_work_sweep is now canonically defined by unclassified_work_escalates.sql, superseding
-- only_refunds_reach_the_founder.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/unclassified_work_escalates_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/unclassified_work_escalates.sql',
       evidence = 'records source_file scripts/sql/only_refunds_reach_the_founder.sql, manifest order says scripts/sql/unclassified_work_escalates.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_agent_action_work_sweep'
   and coalesce(identity_args,'') = 'p_limit integer';
