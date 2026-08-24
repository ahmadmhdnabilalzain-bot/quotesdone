-- O12. A NEW FIXTURE TABLE THE COMMITTED SCENARIO WAS NOT WATCHING.
--
-- O11 made public.fn_phase_d_fixture_scenario register a file revision for every
-- supplier_safe_package it builds, because an empty file set is no longer an approved one. That is
-- a row in a table `public.phase_d_committed_scenario_watch` did not name — so if a COMMITTED
-- scenario ever reached that stage it would leave one `fxrev:` row per package behind while every
-- watched relation returned to its watermark and `fn_phase_d_committed_scenario_close` reported
-- success. A cleanup that stops at the tables somebody remembered is a shape this estate has been
-- caught by before.
--
-- MEASURED BEFORE DECIDING WHAT TO DO, because the obvious fix was the wrong one. Driven on
-- production in an aborted transaction (scripts/tmp_diag/probe_committed_residue.mjs):
--
--   public.fn_phase_d_committed_scenario_open  -> phase_d_file_revision 7 -> 7, fxrev rows 0
--   public.fn_phase_d_committed_scenario_close -> 7, fxrev rows 0, ok = true
--
-- The committed scenario does not reach the supplier_safe_package stage today, so there is no
-- exposure to clean up. Adding a DELETE to close() would therefore have been a cleanup that has
-- never removed anything and that nobody could prove works — and worse, the only key linking a
-- revision to a scenario runs through public.phase_d_object_record, which close() does not delete
-- and which carries no fixture_run_id column. A delete keyed on a column that does not exist is
-- how a cleanup silently removes nothing.
--
-- SO IT IS WATCHED RATHER THAN SWEPT, and it fails CLOSED. With the relation on the watch list,
-- close() compares its count against the watermark it took at open() and REFUSES to record success
-- while it is above it. If a future committed scenario ever does create a fixture revision, the
-- close will say so instead of a later reader discovering the rows. That is the estate's own
-- mechanism, it is stronger than a delete nobody has driven, and it needs no new code.

INSERT INTO public.phase_d_committed_scenario_watch (relation, reached_by, is_queue)
VALUES ('public.phase_d_file_revision',
        'created by fn_phase_d_fixture_file_revision from the supplier_safe_package stage (O11), so '
     || 'the package names the file set BR-012 requires',
        false)
ON CONFLICT DO NOTHING;
