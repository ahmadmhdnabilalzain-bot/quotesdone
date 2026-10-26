-- OWNERSHIP LEDGER SYNC for goal_retirement_re_plans_through_the_kernel.sql.
--
-- trg_goal_cascade is now canonically defined by goal_retirement_re_plans_through_the_kernel.sql,
-- superseding launch_step1_a_new_target_cascades.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/goal_retirement_re_plans_through_the_kernel_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/goal_retirement_re_plans_through_the_kernel.sql',
       evidence = 'records source_file scripts/sql/launch_step1_a_new_target_cascades.sql, manifest order says scripts/sql/goal_retirement_re_plans_through_the_kernel.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'trg_goal_cascade'
   and coalesce(identity_args,'') = '';
