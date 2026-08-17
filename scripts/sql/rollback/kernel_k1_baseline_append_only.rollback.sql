-- ROLLBACK for scripts/sql/kernel_k1_baseline_append_only.sql.
--
-- Drops exactly the two objects that file creates, in dependency order, and nothing else. It does
-- not read, write or re-record any org_phase_baseline row — undoing a guard must never also undo
-- the thing the guard was protecting.
--
-- After this runs, public.org_phase_baseline is UPDATE-able and DELETE-able again by anything with
-- write access to the table. That is the pre-K1 state, not a safe one.

drop trigger if exists a00_org_phase_baseline_append_only on public.org_phase_baseline;

drop function if exists public.fn_org_phase_baseline_append_only();
