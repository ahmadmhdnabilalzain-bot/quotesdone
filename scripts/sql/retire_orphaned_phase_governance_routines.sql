-- RETIRE TWELVE ORPHANED PHASE-GOVERNANCE ROUTINES — measured dead, not assumed.
--
-- The founder lifted every phase freeze on 2 Sep 2026 (remove_the_phase_freeze_totally.sql,
-- lift_all_phase_freezes.sql). The guard functions those freezes ran are now orphans: their triggers
-- are gone, nothing calls them, and their only remaining mentions are the attach/lift history files
-- that put them there. Nine more Phase C/D measurement, observation, residue and handoff routines
-- were never wired to anything.
--
-- MEASURED before removal, 3 Sep 2026, for each of the twelve: 0 callers in any other routine body
-- (all 1,339 public routines scanned), 0 cron commands or execution wrappers, 0 triggers
-- (pg_trigger.tgfoid exact join), 0 view definitions, 0 RLS policies, 0 references from
-- scripts/checks, supabase/functions, scripts/phase_c, scripts/phase_d or .github, not discovered as
-- a board by fn_kernel_all_boards(), not registered in kernel_write_authority or kernel_retired_path,
-- and not named by any phase_c_*_binding, phase_c_component or cutover row. Their scripts/sql
-- mentions were classified CALL vs MENTION per file: every one is a MENTION (a registry row or the
-- freeze attach/lift history), 0 CALLs.
--
-- Deliberately NOT retired: fn_kernel_wrap_and_enable_cron (an operator tool, 6 calling scripts),
-- fn_kernel_workflow_graph_validate / fn_phase_d_external_state / _outbound_state / _slug (called),
-- every *_state routine fn_kernel_all_boards() discovers by signature (17 live boards with no
-- textual caller), fn_kernel_assert_in_kernel (registered in kernel_write_authority), and
-- fn_kernel_system_execution_fail (unused API surface over _close, not scaffolding), and
-- fn_phase_c_event_runtime_observation (pg_depend: view v_phase_c_event_binding_state uses it — a
-- text scan of view bodies missed it; pg_depend, not text, is the pre-check).
--
-- Reversibility is git: each routine's canonical file stays in scripts/sql; scripts/sql/DROPPED.txt
-- records the absence so the canonical engine reads it as retired, not as failed-to-deploy. No
-- CASCADE anywhere; each drop names its exact signature.
--
--   node scripts/apply_sql.mjs scripts/sql/retire_orphaned_phase_governance_routines.sql --apply --ddl

begin;

drop function if exists public.fn_phase_a_freeze_guard();
drop function if exists public.fn_phase_b_freeze_guard();
drop function if exists public.fn_phase_b_step_transition_allowed(text, text);
drop function if exists public.fn_phase_c_freeze_amendment_approver_guard();
drop function if exists public.fn_phase_c_trace_coverage();
drop function if exists public.fn_phase_d_actual_caller_measure();
drop function if exists public.fn_phase_d_application_connection_measure();
drop function if exists public.fn_phase_d_external_residue();
drop function if exists public.fn_phase_d_handoff_cancel(jsonb);
drop function if exists public.fn_phase_d_handoff_reject(jsonb);
drop function if exists public.fn_phase_d_disposition_state();
drop function if exists public.fn_phase_d_reference_fold_state();

do $ctl$
declare v_left int;
begin
  select count(*) into v_left from pg_proc
   where pronamespace = 'public'::regnamespace
     and proname in ('fn_phase_a_freeze_guard','fn_phase_b_freeze_guard','fn_phase_b_step_transition_allowed',
                     'fn_phase_c_freeze_amendment_approver_guard',
                     'fn_phase_c_trace_coverage','fn_phase_d_actual_caller_measure',
                     'fn_phase_d_application_connection_measure','fn_phase_d_external_residue',
                     'fn_phase_d_handoff_cancel','fn_phase_d_handoff_reject','fn_phase_d_disposition_state',
                     'fn_phase_d_reference_fold_state');
  if v_left > 0 then
    raise exception 'retire_orphaned_phase_governance_routines: % of the 12 routines still present', v_left;
  end if;
end $ctl$;

commit;

-- COMPONENT RETIREMENT (added after the first apply). Three of the twelve had phase_c_component rows
-- that outlived their routine; the exposure board then read a null derivation against a recorded
-- external_entry. Mark them with the estate's retirement vocabulary (inactive / INTENTIONALLY_RETIRED)
-- and take the one that was in the frozen exposure scope out of it — a dropped routine has no object
-- to derive exposure from. Mirrored line-for-line in docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv.
begin;
update public.phase_c_component set activation_state='inactive', classification='INTENTIONALLY_RETIRED', external_entry='no', gap='routine dropped 3 Sep 2026; no object remains', repair_or_keep_action='retired', evidence='retire_orphaned_phase_governance_routines.sql 2026-09-03: orphan of the Phase A freeze the founder lifted 2 Sep 2026 (trigger already dropped); measured 0 callers/cron/trigger/view/RLS/repo refs before removal; function dropped' where component_id='dbfn:fn_phase_a_freeze_guard()';
update public.phase_c_component set activation_state='inactive', classification='INTENTIONALLY_RETIRED', external_entry='no', gap='routine dropped 3 Sep 2026; no object remains', repair_or_keep_action='retired', evidence='retire_orphaned_phase_governance_routines.sql 2026-09-03: orphan of the Phase B freeze the founder lifted 2 Sep 2026 (trigger already dropped); measured 0 callers/cron/trigger/view/RLS/repo refs before removal; function dropped' where component_id='dbfn:fn_phase_b_freeze_guard()';
update public.phase_c_component set activation_state='inactive', classification='INTENTIONALLY_RETIRED', external_entry='no', gap='routine dropped 3 Sep 2026; no object remains', repair_or_keep_action='retired', evidence='retire_orphaned_phase_governance_routines.sql 2026-09-03: freeze-era transition rule with 0 callers that was anon-EXECUTABLE over PostgREST (K11 2026-08-16 measured has_function_privilege(anon)=t); dropping it closed that unauthenticated public entry; removed from phase_c_component_exposure_scope because a dropped routine has no object to derive exposure from' where component_id='dbfn:fn_phase_b_step_transition_allowed(p_from text, p_to text)';
delete from public.phase_c_component_exposure_scope where component_id='dbfn:fn_phase_b_step_transition_allowed(p_from text, p_to text)';
commit;
