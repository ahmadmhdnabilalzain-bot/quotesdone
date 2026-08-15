-- Phase B — exact rollback.
--
-- Run this if any mandatory Phase A or Phase B invariant fails after deployment.  It removes
-- everything the Phase B forward migration created and nothing else.
--
--   node scripts/apply_sql.mjs scripts/sql/phase_b_workflow_closure_rollback.sql --apply --ddl
--
-- What it removes:
--   * the 16 phase_b_* tables and their triggers, constraints and indexes;
--   * the 6 fn_phase_b_* functions;
--   * the org_role_alias rows Phase B added, identified by their reason text so a pre-existing
--     alias with the same name is left alone.
--
-- What it deliberately does NOT touch:
--   * anything Phase A owns.  org_role, org_departments, org_workflow_ownership and
--     founder_reserved_decision are not written by the forward migration and are not written
--     here.  fn_phase_a_baseline_drift() must still return zero rows after this runs.
--   * any business record, cron job, provider route or edge function.  The forward migration
--     created none, so there are none to undo.
--
-- Dropping the tables discards the crosswalk measurement with them.  That is correct: the
-- measurement is reproducible from the repository with
--   node scripts/phase_b/inventory_estate.mjs && node scripts/phase_b/build_crosswalk.mjs
-- and a stale measurement left behind after a rollback would be worse than none.

set lock_timeout = '8s';
set statement_timeout = '600s';

begin;

-- ---- triggers first, so a drop cannot fire a guard mid-teardown ----
drop trigger if exists a10_phase_b_owner_guard          on public.phase_b_workflow_step;
drop trigger if exists a10_phase_b_workflow_owner_guard on public.phase_b_workflow;
drop trigger if exists a10_phase_b_handoff_guard        on public.phase_b_handoff;

-- ---- tables, in dependency order ----
drop table if exists public.phase_b_crosswalk;
drop table if exists public.phase_b_package_erratum;
drop table if exists public.phase_b_event;
drop table if exists public.phase_b_exception;
drop table if exists public.phase_b_handoff;
drop table if exists public.phase_b_workflow_step;
drop table if exists public.phase_b_workflow;
drop table if exists public.phase_b_founder_boundary;
drop table if exists public.phase_b_gate;
drop table if exists public.phase_b_business_rule;
drop table if exists public.phase_b_business_object;
drop table if exists public.phase_b_sla_policy;
drop table if exists public.phase_b_dynamic_actor;
drop table if exists public.phase_b_step_transition;
drop table if exists public.phase_b_workflow_transition;
drop table if exists public.phase_b_step_state;
drop table if exists public.phase_b_workflow_state;

-- ---- functions ----
drop function if exists public.fn_phase_b_invariants();
drop function if exists public.fn_phase_b_closure_blockers(text, text[], bigint, bigint);
drop function if exists public.fn_phase_b_step_transition_allowed(text, text);
drop function if exists public.fn_phase_b_transition_allowed(text, text);
drop function if exists public.fn_phase_b_handoff_guard();
drop function if exists public.fn_phase_b_workflow_owner_guard();
drop function if exists public.fn_phase_b_owner_guard();
drop function if exists public.fn_phase_b_resolve_role(text);

-- ---- the aliases Phase B added ----
-- Matched on the reason text the forward migration wrote, never on alias name alone: an alias
-- that already existed under a different reason belongs to whoever created it.
delete from public.org_role_alias
where reason = 'Phase B package addresses this role by descriptive name'
   or reason like 'Phase B reconciliation: %';

commit;

-- After this runs, both of these must hold:
--   select count(*) from public.fn_phase_a_baseline_drift();                  -- 0
--   select count(*) from information_schema.tables
--    where table_schema = 'public' and table_name like 'phase\_b\_%';         -- 0
