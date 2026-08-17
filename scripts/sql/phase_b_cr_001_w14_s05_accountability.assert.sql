-- Assertions for the PBCR-001 rehearsal. Always ends in a raise, so the transaction aborts.
do $rehearse$
declare
  v_owner text; v_token text; v_kind text; v_contrib text; v_may boolean;
  v_handoffs bigint; v_steps bigint; v_workflows bigint; v_overlay_steps bigint;
  v_bad_graph bigint; v_summary record; v_cr bigint; v_a_drift bigint; v_b_drift bigint;
  v_open jsonb; v_run bigint;
begin
  select accountable_role_id, package_accountable_token, actor_kind, array_to_string(contributors,';')
    into v_owner, v_token, v_kind, v_contrib
    from public.phase_b_workflow_step where step_id = 'W14-S05';
  select may_be_accountable into v_may from public.phase_b_dynamic_actor
   where actor_token = 'relevant_category_overlay';
  select count(*) into v_handoffs   from public.phase_b_handoff;
  select count(*) into v_steps      from public.phase_b_workflow_step;
  select count(*) into v_workflows  from public.phase_b_workflow;
  select count(*) into v_overlay_steps from public.phase_b_workflow_step where actor_kind = 'category_overlay';
  select count(*) into v_cr from public.phase_b_change_request;
  select count(*) into v_bad_graph from public.fn_kernel_workflow_graph_validate()
   where verdict <> 'OK' and workflow_id <> 'SUMMARY';
  select * into v_summary from public.fn_kernel_workflow_graph_validate() where workflow_id = 'SUMMARY';
  select count(*) into v_a_drift from public.fn_phase_a_baseline_drift();
  select count(*) into v_b_drift from public.fn_phase_b_baseline_drift();

  -- the whole point: the step the engine refused must now open. Aborted with everything else.
  begin
    v_open := public.fn_kernel_open_step(jsonb_build_object(
      'probe', true, 'step_id', 'W14-S05'));
  exception when others then
    v_open := jsonb_build_object('raised', sqlerrm);
  end;

  raise exception E'REHEARSAL PBCR-001 (rolled back)\n'
    '  W14-S05 owner ............ %\n'
    '  W14-S05 token ............ %\n'
    '  W14-S05 actor_kind ....... %\n'
    '  W14-S05 contributors ..... %\n'
    '  overlay may_be_accountable %\n'
    '  steps with overlay actor . %  (expect 0)\n'
    '  handoffs ................. %  (expect 159)\n'
    '  steps .................... %  (expect 257)\n'
    '  workflows ................ %  (expect 30)\n'
    '  change requests recorded . %  (expect 1)\n'
    '  workflows not OK ......... %  (expect 0)\n'
    '  unresolved successor owners %  (expect 0)\n'
    '  owners_unresolved ........ %  (expect 0)\n'
    '  closure_path_executable .. %  (expect true)\n'
    '  phase A drift rows ....... %  (expect 0)\n'
    '  phase B drift rows ....... %  (expect >0 until re-freeze)\n'
    '  open_step probe .......... %',
    v_owner, v_token, v_kind, v_contrib, v_may, v_overlay_steps, v_handoffs, v_steps, v_workflows,
    v_cr, v_bad_graph, v_summary.unresolved_successor_owners, v_summary.owners_unresolved,
    v_summary.closure_path_executable, v_a_drift, v_b_drift, v_open;
end
$rehearse$;
