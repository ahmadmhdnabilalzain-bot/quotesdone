-- PBCR-001 execution rehearsal: drive one W14 run from start to its explicit closure step,
-- entirely inside the aborted transaction. This is the founder's actual requirement — not that
-- the graph validator likes the registry, but that W14 RUNS THROUGH W14-S05 and closes.
do $walk$
declare
  v_out jsonb; v_run bigint; v_i int := 0;
  r record; v_path text := ''; v_state text; v_closed timestamptz; v_last text := '';
  v_hops int := 0; v_s05_actor text; v_s05_state text;
begin
  v_out := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        'W14',
    'business_object_id', 'ZZ-REHEARSAL-QUOTE-PBCR001',
    'source_kind',        'autonomous',
    'source_ref',         'rehearsal:pbcr-001',
    'requested_by',       'kernel:rehearsal',
    'priority',           'P2'));
  v_run := (v_out->>'run_id')::bigint;
  if v_run is null then
    raise exception E'REHEARSAL PBCR-001 WALK: workflow_start did not return a run_id: %', v_out;
  end if;

  -- Walk: accept whatever handoff is waiting, then complete whatever step is open, until the run
  -- is no longer running. Bounded so a registry cycle cannot spin here.
  loop
    v_i := v_i + 1;
    exit when v_i > 40;

    -- One row at a time, re-queried every pass: a cursor held open across these writes would hand
    -- back a handoff that has already been accepted.
    select hr2.handoff_run_id, hr2.receiving_role_id into r
      from public.phase_c_handoff_run hr2
     where hr2.run_id = v_run and hr2.status = 'open'
     order by hr2.handoff_run_id limit 1;
    if r.handoff_run_id is not null then
      v_hops := v_hops + 1;
      v_out := public.fn_kernel_handoff_accept(jsonb_build_object(
        'handoff_run_id', r.handoff_run_id,
        'actor_role_id',  r.receiving_role_id,
        'outcome',        'accept',
        'packet', jsonb_build_object(
          'business_object_id', 'ZZ-REHEARSAL-QUOTE-PBCR001',
          'object_version',     1,
          'output',             'PBCR-001 rehearsal packet',
          'evidence_refs',      jsonb_build_array('rehearsal:pbcr-001'),
          'requested_action',   'continue')));
      continue;
    end if;

    select sr.step_run_id, sr.step_id, sr.accountable_role_id, sr.reviewer_role_id into r
      from public.phase_c_workflow_step_run sr
     where sr.run_id = v_run and sr.state = 'active'
     order by sr.step_run_id limit 1;
    exit when r.step_run_id is null;

    v_path := v_path || case when v_path = '' then '' else ' -> ' end || r.step_id;
    v_last := r.step_id;
    if r.step_id = 'W14-S05' then
      v_s05_actor := r.accountable_role_id;
    end if;

    -- A step that names an independent reviewer needs that verdict on record first.
    if r.reviewer_role_id is not null then
      v_out := public.fn_kernel_review_decide(jsonb_build_object(
        'task_id',          (select t.task_id from public.phase_c_task t where t.run_id = v_run and t.step_id = r.step_id order by t.task_id desc limit 1),
        'reviewer_role_id', r.reviewer_role_id,
        'decision',         'approved',
        'reason',           'PBCR-001 rehearsal: independent review recorded so the walk can prove '
                            || 'the step contract, not bypass it.'));
    end if;

    v_out := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id',     r.step_run_id,
      'actor_role_id',   r.accountable_role_id,
      'outcome',         'pass',
      'idempotency_key', 'rehearsal:pbcr-001:' || r.step_id,
      'reason',          'PBCR-001 rehearsal',
      'inputs',          jsonb_build_object('source', 'PBCR-001 rehearsal', 'step_id', r.step_id),
      'output',          jsonb_build_object('status', 'ok', 'output', 'PBCR-001 rehearsal output for ' || r.step_id),
      'evidence_ref',    'rehearsal:pbcr-001'));
    if coalesce((v_out->>'ok')::boolean, false) is not true then
      raise exception E'REHEARSAL PBCR-001 WALK stopped at %\n  step_complete returned: %\n  path so far: %',
        r.step_id, v_out, v_path;
    end if;
  end loop;

  select state, closed_at into v_state, v_closed from public.phase_c_workflow_run where run_id = v_run;
  select state into v_s05_state from public.phase_c_workflow_step_run
   where run_id = v_run and step_id = 'W14-S05';

  raise exception E'REHEARSAL PBCR-001 WALK (rolled back)\n'
    '  run_id ................. %\n'
    '  steps executed ......... %\n'
    '  handoffs accepted ...... %\n'
    '  path ................... %\n'
    '  W14-S05 executed by .... %  (expect quote_evaluation)\n'
    '  W14-S05 final state .... %\n'
    '  last step reached ...... %  (W14-S09 is the closure step)\n'
    '  run state .............. %\n'
    '  run closed_at .......... %',
    v_run, v_i - 1, v_hops, v_path, v_s05_actor, v_s05_state, v_last, v_state, v_closed;
end
$walk$;
