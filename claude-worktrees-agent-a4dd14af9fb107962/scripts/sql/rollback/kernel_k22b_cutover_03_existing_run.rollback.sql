-- Rollback for K22/K22b, cutover increment 3 (signals about runs that already exist).
--
-- Removing the cutover means deleting the marked "-- Kernel cutover." block from
-- trg_quote_items_roll and qd_on_refund_resolved and re-applying. After that a quotation revision
-- and a refund resolution leave no mark on the run they belong to.
--
-- DO NOT PUT THE NULL-RUN RAISE BACK. K22b deleted this from fn_kernel_source_emit:
--
--   if v_run is null then raise exception '... named no workflow_run_id' ...
--
-- because a class-B source is a database trigger firing on every row change, and "this object has
-- no live run right now" is the ordinary case, not a developer error. With the raise in place,
-- inserting a quote item on a quotation with no open W14 run FAILED. Measured in rehearsal both
-- ways: with the raise the insert died; without it the insert succeeds and the signal is recorded
-- as a refused row carrying its reason, because fn_kernel_signal_submit writes the ledger row
-- before it validates. Restoring the raise breaks quote_items and transactions inserts.
--
-- DO NOT PUT supplier.quote_revision BACK TO COMPLETE_STEP either. A trigger on quote_items knows
-- a quote id and a recomputed score; it does not know the step's required output, and
-- fn_kernel_step_complete rightly refuses to close a step without one. As COMPLETE_STEP the signal
-- was refused every single time.
--
-- The two quote_items reclassifications (B -> C) are measurements of what those triggers write and
-- stay true regardless of this file.

select 'K22b rollback: delete the marked "-- Kernel cutover." block from trg_quote_items_roll and '
       'qd_on_refund_resolved and re-apply. Keep the wrapper correction, the ATTACH_ONLY '
       'disposition and the two reclassifications. See the comment block above.' as instruction;
