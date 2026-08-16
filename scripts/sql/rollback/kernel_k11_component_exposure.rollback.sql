-- ROLLBACK for kernel_k11_component_exposure.sql
--
-- Drops the machinery: the guard, the derivation, the exposure invariant. It does NOT restore the
-- labels the derivation corrected, and it does NOT narrow the classification CHECK back.
--
-- WHY. K11 did two different kinds of thing. It added machinery — a derivation, an invariant and a
-- trigger — and it recorded measurements: that trg_enforce_rls_new_tables is an enabled event
-- trigger, that cron.job 64 is active with 372 runs, that fifteen functions are executable by anon,
-- that pdpl_request answers an unauthenticated POST. Removing the machinery is reversible.
-- Un-recording the measurements is not a rollback, it is a lie: restoring
-- "DEFERRED_RUNTIME_IMPLEMENTATION / inactive" onto a trigger that fires on every DDL statement
-- would put back the exact false statement this increment existed to remove, and the trigger would
-- go on firing regardless.
--
-- So the CHECK stays widened (the corrected rows must remain expressible), the corrected rows stay
-- corrected, and phase_c_component_probe and phase_c_component_exposure_scope stay as the evidence
-- and the frozen denominator behind them. What goes is only the code.
--
-- If the intent is genuinely to undo the classifications as well, that is a separate, deliberate
-- migration that names each row and says why the measurement was wrong. The frozen `frozen_as`
-- column of phase_c_component_exposure_scope holds every original value, so it is a `select`, not
-- an archaeology exercise.

begin;

drop trigger if exists a00_phase_c_component_classification_guard on public.phase_c_component;
drop function if exists public.fn_phase_c_component_classification_guard();
drop function if exists public.fn_kernel_component_exposure_state();
drop function if exists public.fn_kernel_component_reachability(text);

-- Deliberately NOT dropped:
--   table public.phase_c_component_probe             -- the measured platform and repository facts
--   table public.phase_c_component_exposure_scope    -- the frozen denominator and every prior label
--   constraint phase_c_component_classification_ck   -- narrowing it would invalidate corrected rows
--   the reclassified rows themselves                 -- see the note above

commit;
