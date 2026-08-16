-- fn_phase_c_step_advance — the definition as it stands after step-order enforcement.
--
-- scripts/sql/the_boundary_refused_the_wrong_actor_but_not_the_wrong_order.sql performs the change
-- as a targeted substitution on pg_get_functiondef(), which is a smaller and more reviewable diff
-- than restating a 122-line body. That leaves the REPOSITORY behind the database, and
-- scripts/checks/sql_files_match_live.test.mjs is right to refuse it.
--
-- So this file carries the definition read back OUT of the database after the change, verbatim.
-- The check ranks files by COMMIT order, so this only becomes the newest definition once committed.
--
-- The only difference from the previous definition is the prerequisite gate: a step with a declared
-- phase_b_handoff predecessor is refused with error 'out_of_order' until that predecessor has
-- reached completed, skipped or superseded in the same run. Entry points -- 96 of the 257 steps have
-- no incoming edge -- are unaffected.

CREATE OR REPLACE FUNCTION public.fn_phase_c_step_advance(p_run_id bigint, p_step_id text, p_actor text, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s public.phase_b_workflow_step%rowtype;
  r public.phase_c_workflow_run%rowtype;
  g record; a record; o record;
  v_owner text; v_step_run bigint; v_trace bigint;
  v_prev bigint; v_prev_attempt bigint; v_attempt bigint;
  v_idem text; v_evidence jsonb; v_gates jsonb := '[]'::jsonb; v_action text;
begin
  select * into r from public.phase_c_workflow_run where run_id = p_run_id;
  if not found then return jsonb_build_object('ok', false, 'error','unknown_run'); end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    return jsonb_build_object('ok', false, 'error','unknown_step',
      'message', format('%L is not a step in the frozen Phase B registry — fail closed', p_step_id));
  end if;
  if s.workflow_id <> r.workflow_id then
    return jsonb_build_object('ok', false, 'error','step_not_in_this_workflow',
      'step_workflow', s.workflow_id, 'run_workflow', r.workflow_id);
  end if;

  -- PREREQUISITES. phase_b_handoff declares from_step_id -> to_step_id for every ordered
  -- pair; a step with no incoming edge is an entry point and always startable. Checked
  -- before the actor is resolved, because order is a property of the run rather than of
  -- the caller, and a correct owner arriving early should be told the step is not ready
  -- rather than that they are the wrong person.
  if exists (select 1 from public.phase_b_handoff h where h.to_step_id = p_step_id) then
    if not exists (select 1 from public.phase_b_handoff h
                    join public.phase_c_workflow_step_run pr
                      on pr.step_id = h.from_step_id and pr.run_id = p_run_id
                   where h.to_step_id = p_step_id
                     and pr.state in ('completed','skipped','superseded')) then
      return jsonb_build_object('ok', false, 'error','out_of_order',
        'step', p_step_id,
        'awaiting', (select string_agg(h.from_step_id, ', ' order by h.from_step_id)
                       from public.phase_b_handoff h where h.to_step_id = p_step_id),
        'message', 'Phase B declares a predecessor for this step and it has not reached '
                   'completed, skipped or superseded in this run.');
    end if;
  end if;

  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_actor);
  if v_owner is null then
    return jsonb_build_object('ok', false, 'error','actor_not_resolvable', 'actor', p_actor);
  end if;
  if s.accountable_role_id = 'relevant_category_overlay' then
    if not public.fn_phase_c_step_owner_valid(p_step_id, v_owner) then
      return jsonb_build_object('ok', false, 'error','not_an_eligible_category_overlay',
        'step_owner', s.accountable_role_id, 'actor', v_owner,
        'message','This step is owned by the category overlay placeholder; only an active overlay in the declared scope may advance it.');
    end if;
  elsif v_owner <> s.accountable_role_id then
    return jsonb_build_object('ok', false, 'error','not_the_accountable_owner',
      'step_owner', s.accountable_role_id, 'actor', v_owner,
      'message','Phase B froze step ownership; Phase C does not reassign it at runtime.');
  elsif not public.fn_phase_c_actor_may_own(v_owner) then
    return jsonb_build_object('ok', false, 'error','actor_not_canonical', 'actor', p_actor);
  end if;

  v_evidence := coalesce(p_body->'gate_evidence', '{}'::jsonb)
                || jsonb_build_object('actor_role_id', v_owner)
                || jsonb_build_object('evidence_ref',
                     coalesce(p_body->'gate_evidence'->>'evidence_ref',
                              'run:' || p_run_id || ':step:' || p_step_id));
  for g in select * from public.fn_phase_c_gates_for_step(p_step_id) loop
    declare res record;
    begin
      select * into res from public.fn_phase_c_gate_evaluate(g.gate_id, v_evidence);
      if not res.passed and g.gate_type = 'hard' then
        return jsonb_build_object('ok', false, 'error','gate_failed', 'gate', g.gate_id,
          'gate_name', g.gate_name, 'reason', res.reason);
      end if;
      v_gates := v_gates || jsonb_build_array(jsonb_build_object(
        'gate_id', g.gate_id, 'type', g.gate_type, 'passed', res.passed, 'reason', res.reason));
    end;
  end loop;

  v_action := coalesce(p_body->>'authority_class', 'routine_operational_decision');
  select * into a from public.fn_phase_c_authority_check(
    v_action, v_owner, nullif(s.independent_reviewer_role_id,''));
  if not a.allowed then
    return jsonb_build_object('ok', false, 'error','authority_refused', 'reason', a.reason,
      'founder_boundary', s.founder_gate, 'action_class', v_action);
  end if;

  if p_body ? 'output' then
    select * into o from public.fn_phase_c_output_validate(p_step_id, p_body->'output');
    if not o.valid then
      return jsonb_build_object('ok', false, 'error','failed_incomplete', 'reason', o.reason,
        'message','A truncated or invalid consequential output creates no side effect.');
    end if;
  end if;

  -- SELECT INTO with no rows nulls every target, so the attempt number is derived AFTER the
  -- lookup rather than by mutating an initialiser the lookup may have wiped.
  select step_run_id, attempt_no into v_prev, v_prev_attempt
  from public.phase_c_workflow_step_run
  where run_id = p_run_id and step_id = p_step_id
  order by attempt_no desc limit 1;
  v_attempt := coalesce(v_prev_attempt, 0) + 1;

  v_idem := s.idempotency_scope || '|' || p_run_id || '|' || p_step_id || '|' || v_attempt;

  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no, first_attempt_id,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key, finished_at)
  values (p_run_id, p_step_id, v_owner, coalesce(s.independent_reviewer_role_id,''),
          coalesce(p_body->>'state','completed'), v_attempt,
          -- the FIRST attempt is what every retry points at, not the immediately previous one
          coalesce((select first_attempt_id from public.phase_c_workflow_step_run
                    where step_run_id = v_prev), v_prev),
          encode(sha256(convert_to(coalesce(p_body->>'input',''), 'UTF8')), 'hex'),
          encode(sha256(convert_to(coalesce(p_body->'output'->>'output',''), 'UTF8')), 'hex'),
          v_gates, a.reason, v_idem, now())
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_phase_c_step_advance wrote no step run for %', p_step_id using errcode = '23502';
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', v_step_run::text, 'run_id', p_run_id,
    'step_run_id', v_step_run, 'actor_role_id', v_owner,
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'reviewer_independent', public.fn_phase_c_reviewer_independent(v_owner, s.independent_reviewer_role_id),
    'authority_result', a.reason, 'gates', v_gates,
    'evidence_refs', jsonb_build_array(jsonb_build_object('founder_boundary', s.founder_gate)),
    'state_before','active', 'state_after', coalesce(p_body->>'state','completed'), 'status','sealed'));
  update public.phase_c_workflow_step_run set trace_id = v_trace where step_run_id = v_step_run;

  return jsonb_build_object('ok', true, 'step_run_id', v_step_run, 'attempt', v_attempt,
                            'first_attempt_id', coalesce((select first_attempt_id from public.phase_c_workflow_step_run
                                                          where step_run_id = v_step_run), v_prev),
                            'owner', v_owner, 'trace_id', v_trace,
                            'gates_evaluated', v_gates, 'founder_boundary', s.founder_gate,
                            'authority', a.reason);
end $function$
;
