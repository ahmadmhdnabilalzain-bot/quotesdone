-- ROLLBACK for supabase/migrations/20260815070000_phase_a_frozen_founder_approved.sql
--
-- Removes the freeze. It does NOT touch the organisation — the freeze added no department, role,
-- overlay, workflow or founder-reserved decision, so unfreezing removes only the record and the
-- guard. The approved shape stays exactly as the founder approved it.
--
-- The triggers go FIRST. Dropping the baseline row while the guard is still installed would leave
-- a guard that reads no baseline and silently permits everything, which is the worst of both.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_a_freeze_rollback.sql --apply --ddl

set lock_timeout = '5s';
set statement_timeout = '60s';

drop trigger if exists z90_phase_a_freeze on public.org_role;
drop trigger if exists z90_phase_a_freeze on public.org_departments;
drop function if exists public.fn_phase_a_freeze_guard();
drop function if exists public.fn_phase_a_baseline_drift();
delete from public.org_phase_baseline where phase = 'A';
drop table if exists public.org_phase_baseline;

do $$
declare v int;
begin
  -- the organisation must be untouched by unfreezing it
  select count(*) into v from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay';
  if v <> 90 then raise exception 'ROLLBACK: canonical roles = %, expected the approved 90 — unfreezing changed the organisation', v; end if;
  select count(*) into v from public.org_role where status='active' and runtime_mode='knowledge_overlay';
  if v <> 86 then raise exception 'ROLLBACK: category overlays = %, expected 86', v; end if;
  select count(*) into v from public.org_departments where active;
  if v <> 10 then raise exception 'ROLLBACK: active departments = %, expected 10', v; end if;
  select count(*) into v from public.fn_phase_a_organization_violations();
  if v <> 0 then raise exception 'ROLLBACK: % Phase A organization violation(s) after unfreezing', v; end if;
  if exists (select 1 from pg_trigger where tgname = 'z90_phase_a_freeze' and not tgisinternal)
    then raise exception 'ROLLBACK: a freeze trigger survived'; end if;
  raise notice 'PHASE A UNFROZEN: guard and baseline removed, organisation unchanged at 10/90/86.';
end $$;
