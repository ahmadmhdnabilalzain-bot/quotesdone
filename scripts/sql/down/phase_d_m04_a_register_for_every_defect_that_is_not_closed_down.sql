-- ROLLBACK for phase_d_m04_a_register_for_every_defect_that_is_not_closed.sql
drop function if exists public.fn_phase_d_disposition_state();
drop table if exists public.phase_d_injected_defect_disposition;
