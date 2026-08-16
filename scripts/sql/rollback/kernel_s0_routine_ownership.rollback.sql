-- ROLLBACK for kernel_s0_routine_ownership.sql
--
-- Drops the machinery: the guard trigger, the guard function, the derivation, and the ledger table.
-- It does NOT touch zzz_fn_notifications_demo_guard or fn_delete_proposer, and it does NOT remove
-- kernel_s0_routine_ownership.sql from scripts/sql/MANIFEST.txt.
--
-- WHY THOSE TWO ARE NOT REVERTED. kernel_s0 did not CHANGE either routine. It restated them with
-- bodies byte-identical to what production was already running — proved in the rehearsal by md5,
-- 823d0dce6bb8d2a75f496b023d7514f7 and 87e55ae74a5512d0b709ee7656136cdd before and after. What
-- changed is which file the manifest names as canonical for them, and that was a correction of a
-- WRONG ANSWER, not the introduction of a new one:
--
--   * demo_rehearsal_containment.sql was named canonical for zzz_fn_notifications_demo_guard by an
--     alphabetical tie-break inside one commit. It is the ORIGINAL. "Reverting" to it would restore
--     a last_error string containing @example.invalid, which fn_demo_marker_scan reads as a demo
--     marker, so the teardown proof could never reach zero again.
--   * five_delete_proposals_decided_and_two_of_them_were_miscounted.sql was named canonical for
--     fn_delete_proposer the same way. It predates the "a decision holds until the fact changes"
--     suppression that production runs today. "Reverting" to it would delete a shipped feature.
--
-- Rolling back to a definition production never ran is not a rollback, it is a regression with a
-- reassuring name. If the intent is genuinely to change either routine, that is a new numbered
-- file appended at the bottom of the manifest that says what it is changing and why.
--
-- WHAT ROLLING BACK COSTS. scripts/checks/application_source_of_truth.test.mjs keeps working — it
-- derives every class from the repository and the live catalogue itself, and it does not need the
-- table. What it loses is line 6, the cross-check that the recorded ownership agrees with the
-- repository, and the two justified INTENTIONALLY_UNTRACKED rows that keep holdout_v2.fn_eff and
-- holdout_v2.fn_run_pending out of line 2. Line 2 goes back to 2 of 961 and stays there, which is
-- the honest reading: without the justification on production, nothing has justified them.

begin;

drop trigger if exists a00_kernel_routine_ownership_guard on public.kernel_routine_ownership;
drop function if exists public.a00_kernel_routine_ownership_guard();
drop function if exists public.fn_kernel_routine_ownership(text, text, text);
drop table if exists public.kernel_routine_ownership;

-- Deliberately NOT reverted:
--   public.zzz_fn_notifications_demo_guard   -- restated identically; see the note above
--   public.fn_delete_proposer                -- restated identically; see the note above
--   scripts/sql/MANIFEST.txt                 -- the manifest is append-only by its own rule

commit;
