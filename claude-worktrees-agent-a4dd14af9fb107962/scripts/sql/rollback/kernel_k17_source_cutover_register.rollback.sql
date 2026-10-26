-- Rollback for K17, the source cutover register.
--
-- This removes the only record of which class each autonomous source belongs to, which adapter it
-- is allowed to call, and why. After it, "is this source read-only or does it start work?" has no
-- answer in the database and every check in fn_kernel_source_cutover_state disappears with it.
--
-- It does NOT restore the three recorded_creates_work flags K17 corrected. That correction was a
-- measurement — edge:claim_lookup, edge:resend_webhook and edge:unsubscribe were read and write
-- only their own execution log, email_suppressions, leads.invite_status and error_events, never a
-- workflow run, step run, task, handoff or outbox row. Reverting a measurement because a table
-- that recorded it is being dropped would put a known-false value back on purpose. If the flags
-- must go back to true, do it in a file that says why and shows the source that contradicts this
-- one.
--
-- The signal type supplier.acknowledgement, seeded here, is left in place: it belongs to K16's
-- vocabulary and dropping it would remove the only door edge:supplier_ack has.

begin;

drop function if exists public.fn_kernel_source_cutover_state();
drop table if exists public.phase_c_source_cutover;

commit;
