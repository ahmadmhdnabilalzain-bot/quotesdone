-- Rollback for K16, the existing-workflow signal service.
--
-- This removes the ONLY canonical door for a signal about a run that already exists. After it,
-- every clarification response, quote revision, document arrival, review verdict, follow-up,
-- deadline, SLA breach, retry and provider callback has two options again: pretend to be a new
-- request through fn_kernel_trigger_submit and create a duplicate workflow, or bypass the kernel.
-- Run it only to restore the pre-2026-08-17 shape, never as a fix.
--
-- The ledger is DROPPED, which destroys the record of every signal delivered and every signal
-- refused. If any rows exist, copy them out first — a refusal that vanishes is indistinguishable
-- from a signal that never arrived, and that is the confusion the table was built to prevent:
--
--   create table public.kernel_signal_inbox_archive_20260817 as
--     select * from public.kernel_signal_inbox;
--
-- Nothing K16 created is depended on by K2, K3, K4, K7, K10 or K13: the service calls them, they
-- do not call it. Dropping it cannot leave a dangling reference in the kernel.

begin;

drop function if exists public.fn_kernel_signal_state();
drop function if exists public.fn_kernel_signal_submit(jsonb);
drop table if exists public.kernel_signal_inbox;
drop table if exists public.kernel_signal_type;

commit;
