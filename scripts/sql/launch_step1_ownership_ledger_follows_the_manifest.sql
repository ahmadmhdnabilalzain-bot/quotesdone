-- LAUNCH STEP 1 — THE OWNERSHIP LEDGER FOLLOWS THE MANIFEST FOR THE 5 SUPERSEDED ROUTINES.
--
-- The five launch_step1_*.sql routine files were appended to scripts/sql/MANIFEST.txt, which makes
-- each canonical (position in that file, not a git timestamp, decides). But public.kernel_routine_
-- ownership still recorded each routine against the file that USED to own it, so the Phase C kernel
-- gate's application_source_of_truth check reported "the repository and production disagree about
-- what the QuotesDone application IS" and exited 1 — the ledger asserted an owner the manifest no
-- longer agrees with. Same shape as
-- scripts/sql/spec3_the_ownership_ledger_still_named_the_superseded_file.sql.
--
-- This keeps the ledger in step with the manifest. It is NOT a re-classification: ownership_class
-- stays QUOTESDONE_APPLICATION and source_kind stays MANIFEST for every row. Only the file name moves,
-- and it moves to the file that actually holds the body running on production right now. Each WHERE
-- names the exact superseded file so the update is a no-op if it has already been applied.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_ownership_ledger_follows_the_manifest.sql --apply --ddl

begin;

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/launch_step1_ceo_escalates_to_founder.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_should_escalate'
   and source_file = 'scripts/sql/the_rule_against_repeating_a_failure_held_only_the_reports.sql';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/launch_step1_task_assign_fills_the_department.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_org_task_assign'
   and source_file = 'scripts/sql/org_reorg_04_runtime.sql';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/launch_step1_founder_reports_read_live_objectives.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_company_state'
   and source_file = 'scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/launch_step1_founder_reports_read_live_objectives.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_founder_brief'
   and source_file = 'scripts/sql/fn_founder_brief_names_the_approval_queue.sql';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/launch_step1_a_new_target_cascades.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'trg_goal_cascade'
   and source_file = 'scripts/sql/kernel_k31_goal_retirement.sql';

-- PRE-EXISTING on this branch, surfaced by the same gate: fix_policy_consistency_kb_scale.sql
-- (commit 2281663) redefined fn_policy_consistency_check and was appended to MANIFEST.txt, but the
-- ledger was never moved off the prior file. application_source_of_truth counts it as one more
-- repository/production disagreement, so it is closed here in the same ledger-follows-manifest repair
-- rather than left red under an unrelated step. Bookkeeping only — the routine body is unchanged and
-- is NOT part of the knowledge-corpus work this session leaves alone.
update public.kernel_routine_ownership
   set source_file = 'scripts/sql/fix_policy_consistency_kb_scale.sql', recorded_at = now()
 where schema_name = 'public' and routine_name = 'fn_policy_consistency_check'
   and source_file = 'scripts/sql/source_of_truth_the_repository_records_what_production_runs.sql';

commit;
