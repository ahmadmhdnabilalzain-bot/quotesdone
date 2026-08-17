-- Rollback for K23, the historical exception register's four missing facts.
--
-- Dropping these columns loses, for every one of the 38 preserved exceptions: when the object was
-- actually created, which kernel cutover it is judged against, whether anything is still running
-- because of it, and why an honest repair is impossible. The third is what separates a scar from a
-- wound; without the fourth, "we did not fix it" and "it cannot be fixed without inventing
-- evidence" read identically.
--
-- The rows themselves are NOT touched by this file and must never be. They are the preserved
-- historical record §9 exists to protect, and phase_c_historical_repair is append-only for that
-- reason. This rollback removes analysis, not evidence.
--
-- The append-only trigger is dropped and recreated here for the same reason K23 did it: an ALTER
-- ... DROP COLUMN is DDL and does not trip a row trigger, but leaving the drop and recreate
-- symmetric means a reader of either file sees the same handling.

begin;

drop trigger if exists a00_phase_c_historical_repair_append_only on public.phase_c_historical_repair;

drop function if exists public.fn_kernel_historical_register_state();

alter table public.phase_c_historical_repair
  drop column if exists original_at,
  drop column if exists kernel_cutover_at,
  drop column if exists active_effect_now,
  drop column if exists cannot_reconstruct;

create trigger a00_phase_c_historical_repair_append_only
  before update or delete on public.phase_c_historical_repair
  for each row execute function public.fn_phase_c_historical_repair_append_only();

commit;
