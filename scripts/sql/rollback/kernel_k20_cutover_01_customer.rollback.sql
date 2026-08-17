-- Rollback for K20, cutover increment 1 (customer sources).
--
-- This stops three live triggers handing work to the kernel. After it, a new customer inquiry
-- creates a notification and no W05 run, a refund request creates an owner email and no W17 run,
-- and a fourth abandoned request pauses the customer with no W18 run — the pre-2026-08-17 state,
-- where the company had a customer-facing side effect and no workflow behind it.
--
-- Restoring means re-applying the file that defined each trigger before the cutover. The cutover
-- added exactly one `perform public.fn_kernel_source_emit(...)` call to each and changed nothing
-- else, so removing that call is the whole rollback:
--
--   node scripts/phase_c/gen_cutover.mjs is NOT reversible in the other direction; instead, take
--   the deployed body and delete the K20 block, which is marked in the source:
--
--     -- K20 cutover. <why>
--     perform public.fn_kernel_source_emit(...);
--
-- Runs and inbox rows already created are NOT deleted. They are real workflow runs for real
-- customer inquiries; removing the trigger that started them does not make them not have happened,
-- and deleting them would be the falsification of history the brief forbids. If they must stop,
-- cancel them through fn_kernel_cancel so the cancellation propagates and is recorded.
--
-- The three additions to kernel_trigger_type.allowed_source_systems are left in place: they permit
-- a submission, they do not cause one, and removing them would make a later re-cutover look like
-- a refusal.

select 'K20 rollback: delete the marked "-- K20 cutover." block from trg_inquiry_received, '
       'trg_customer_abandon_ban and qd_notify_refund_request, and re-apply. See the comment '
       'block above; runs already created are deliberately kept.' as instruction;
