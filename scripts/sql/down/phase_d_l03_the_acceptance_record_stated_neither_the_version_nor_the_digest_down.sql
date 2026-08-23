-- ROLLBACK for phase_d_l03_the_acceptance_record_stated_neither_the_version_nor_the_digest.sql
--
-- Drops the register the resolver and the handler read. Both routine bodies are restored by
-- re-applying their predecessors — L01 for fn_phase_d_step_context, h01 for
-- fn_phase_d_handler_execute — which is how a CREATE OR REPLACE chain rolls back here.
drop table if exists public.phase_d_acceptance_document;
