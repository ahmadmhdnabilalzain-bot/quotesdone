-- OWNERSHIP LEDGER SYNC for the_board_sees_runway_cash_and_burn.sql.
--
-- fn_exec_meeting is now canonically defined by scripts/sql/the_board_sees_runway_cash_and_burn.sql
-- (the last manifest file that defines it), superseding launch_step1_ceo_priorities_reach_their_officer.sql.
-- kernel_routine_ownership.source_file must follow the manifest, or the application source-of-truth
-- gate reports the ledger disagreeing with the repository. Emitted mechanically by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/the_board_sees_runway_cash_and_burn_ownership_ledger.sql --apply

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/the_board_sees_runway_cash_and_burn.sql',
       evidence = 'records source_file scripts/sql/launch_step1_ceo_priorities_reach_their_officer.sql, manifest order says scripts/sql/the_board_sees_runway_cash_and_burn.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_exec_meeting'
   and coalesce(identity_args,'') = '';
