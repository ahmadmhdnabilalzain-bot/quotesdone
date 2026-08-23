-- ROLLBACK for phase_d_l01_a_register_that_could_not_tell_naming_from_describing.sql
--
-- Removes the two DESCRIBES keys and the column that classified them, and restores the single-
-- column primary key. The five reader bodies are restored by re-applying the file that defined
-- each of them before L01: k07 (fn_phase_d_step_context), h04 (fn_phase_d_fixture_effect_payload)
-- and f47 (fn_phase_d_fixture_input) — a CREATE OR REPLACE chain is rolled back by its predecessor,
-- never by a down script that would hold no statement of its own.
delete from public.phase_d_context_key_object where key_role = 'DESCRIBES';
drop index if exists public.phase_d_context_key_object_one_identity_uk;
alter table public.phase_d_context_key_object drop constraint if exists phase_d_context_key_object_key_role_ck;
alter table public.phase_d_context_key_object drop constraint if exists phase_d_context_key_object_pkey;
alter table public.phase_d_context_key_object add constraint phase_d_context_key_object_pkey primary key (context_key);
alter table public.phase_d_context_key_object drop column if exists key_role;
