-- OWNERSHIP LEDGER SYNC for outcome_grading_resumes_and_respects_the_hold.sql.
--
-- fn_outcome_evaluate is now canonically defined by outcome_grading_resumes_and_respects_the_hold.sql,
-- superseding seventeen_lessons_from_four_readings_and_none_of_them_earned.sql. Emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/outcome_grading_resumes_and_respects_the_hold_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/outcome_grading_resumes_and_respects_the_hold.sql',
       evidence = 'records source_file scripts/sql/seventeen_lessons_from_four_readings_and_none_of_them_earned.sql, manifest order says scripts/sql/outcome_grading_resumes_and_respects_the_hold.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_outcome_evaluate'
   and coalesce(identity_args,'') = '';
