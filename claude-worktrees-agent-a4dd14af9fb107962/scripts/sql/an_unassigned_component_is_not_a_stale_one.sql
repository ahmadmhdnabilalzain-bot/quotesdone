-- THE KERNEL GATE THAT REFUSED THE COMPANY'S OWN DELIBERATE STATE
--
-- fn_kernel_system_execution_trace refused any execution whose accountable role did not resolve in
-- org_role. That was correct while there was an organisation. On 7 September 2026 the founder
-- removed the chart, told me not to link everything to the ceo -- "keep them unlinked now till we
-- come up with the new structure" -- and then "all those kernel gates that are causing issues can
-- be removed".
--
-- With 1,664 components deliberately unowned, this gate stopped every scheduled job in the estate,
-- the WhatsApp send job included. It is removed rather than softened: a gate kept as a warning is a
-- gate that has stopped checking while still looking like protection.
--
-- The accountable role is still written into the trace, so ownership is recorded wherever it
-- exists. Reinstating the requirement belongs with the new structure.
CREATE OR REPLACE FUNCTION public.fn_kernel_system_execution_trace(p_input jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  k          text;
  v_comp     public.phase_c_component%rowtype;
  v_result   text;
  v_started  timestamptz;
  v_finished timestamptz;
  v_wf       text;
  v_step     text;
  v_scope    text;
  v_trace    bigint;
begin
  if p_input is null then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: no payload at all. A system execution that records '
      'nothing is an untraced execution, which the policy forbids '
      '(trace_required=YES, completed_without_trace_allowed=NO).'
      using errcode = '23514';
  end if;

  -- ---- class 1: the twelve scalars that must be present and non-empty ----------------------
  foreach k in array -- accountable_role_id LEFT THIS LIST on 7 Sep 2026 with the class 5 gate below it. While the
  -- founder rebuilds the structure most components are deliberately unowned, and a required-field
  -- check on the very field he told me to leave empty refuses the company's own state.
  array['component_id','system_actor','trigger_source',
                           'authority_result','state_before','state_after','result',
                           'correlation_id','causation_id','started_at','finished_at']
  loop
    if coalesce(btrim(p_input->>k), '') = '' then
      raise exception
        'TRACE-SYSTEM-EXECUTION incomplete: "%" is missing or empty. The policy''s minimum fields '
        'are execution_id; system_actor; accountable_role; component_id; input_hash; output_hash; '
        'status; timestamps, and this kernel additionally requires scope, trigger source, '
        'authority result, state_before, state_after, result, failure, correlation_id and '
        'causation_id. A record without "%" is not a system-execution trace.', k, k
        using errcode = '23514';
    end if;
  end loop;

  -- ---- class 2: 'failure' must exist as a key, even when it is null ------------------------
  if not (p_input ? 'failure') then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: the "failure" field is absent. It may be null — an '
      'execution that did not fail says so with null — but it may not be missing. An omitted '
      'field is not the same statement as a null one.'
      using errcode = '23514';
  end if;

  -- ---- class 3: the component must exist and must be on this policy ------------------------
  select * into v_comp from public.phase_c_component
   where component_id = p_input->>'component_id';
  if not found then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: component "%" is not in phase_c_component. A trace '
      'anchored to a component nobody can look up cannot be audited.', p_input->>'component_id'
      using errcode = '23514';
  end if;
  if v_comp.trace_policy_id <> 'TRACE-SYSTEM-EXECUTION' then
    raise exception
      'TRACE-SYSTEM-EXECUTION refused: component "%" is scoped to "%", not to '
      'TRACE-SYSTEM-EXECUTION. Write the trace under the policy the component actually carries, '
      'or move the component with a recorded exemption.',
      v_comp.component_id, v_comp.trace_policy_id
      using errcode = '23514';
  end if;

  -- ---- class 4: the system actor must be one of the ten canonical actors -------------------
  if not exists (select 1 from public.phase_c_system_actor
                  where system_actor_id = p_input->>'system_actor') then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: system actor "%" does not resolve in '
      'phase_c_system_actor. "Something ran it" is not an actor.', p_input->>'system_actor'
      using errcode = '23514';
  end if;

  -- ---- class 5: REMOVED 7 September 2026 -----------------------------------------------------
  -- This refused any execution whose accountable_role_id did not resolve in org_role. The founder
  -- removed the organisation chart that day, said "dont link everything to CEO ... keep them
  -- unlinked now till we come up with the new structure", and then "all those kernel gates that are
  -- causing issues can be removed".
  --
  -- So it is gone, not defaulted and not softened into a warning. While there is no structure there
  -- is nothing for it to check, and a gate that refuses the deliberate state of the company is not
  -- protecting anything -- it stopped every scheduled job in the estate, the WhatsApp send included.
  -- The role is still WRITTEN to the trace below, so who owned an execution is still recorded when
  -- there is an owner to record. Reinstating this belongs with the new structure, not before it.

  -- ---- class 6: workflow/step OR a justified technical scope --------------------------------
  v_wf    := nullif(btrim(coalesce(p_input->>'workflow_id','')), '');
  v_step  := nullif(btrim(coalesce(p_input->>'step_id','')), '');
  v_scope := nullif(btrim(coalesce(p_input->>'technical_scope','')), '');

  if v_wf is null and v_scope is null then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: no scope. Give workflow_id (and step_id where the '
      'execution is a step), or give technical_scope with at least 20 characters saying why this '
      'execution belongs to no workflow. Silence is not a justification.'
      using errcode = '23514';
  end if;
  if v_wf is null and length(v_scope) < 20 then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: technical_scope "%" is too short to be a justification. '
      'An execution outside every workflow has to say what it is instead.', v_scope
      using errcode = '23514';
  end if;
  -- A workflow id that is not one of the thirty Phase B workflows is admitted only as a declared
  -- technical scope. OUT_OF_SCOPE and SYSTEM_SCOPE are exactly that case and they must carry the
  -- justification rather than borrow the authority of a workflow id.
  if v_wf is not null
     and not exists (select 1 from public.phase_b_workflow where workflow_id = v_wf)
     and coalesce(length(v_scope), 0) < 20 then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: workflow "%" is not one of the thirty Phase B '
      'workflows, and no technical_scope was given. A non-workflow scope must be justified, not '
      'spelled like a workflow.', v_wf
      using errcode = '23514';
  end if;
  if v_step is not null
     and not exists (select 1 from public.phase_b_workflow_step where step_id = v_step) then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: step "%" does not resolve in phase_b_workflow_step.',
      v_step
      using errcode = '23514';
  end if;

  -- ---- class 7: result vocabulary, and failure consistency ----------------------------------
  v_result := p_input->>'result';
  if v_result <> all (array['succeeded','failed','refused','no_op']) then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: result "%" is not one of succeeded, failed, refused, '
      'no_op.', v_result
      using errcode = '23514';
  end if;
  if v_result = 'failed' and coalesce(btrim(p_input->>'failure'), '') = '' then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: result is "failed" and failure is empty. A failure with '
      'no stated cause is the shape that lets an outage read as a quiet success.'
      using errcode = '23514';
  end if;
  if v_result <> 'failed' and coalesce(btrim(p_input->>'failure'), '') <> '' then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: result is "%" and yet a failure string was supplied. '
      'One of the two is wrong and the trace may not carry both.', v_result
      using errcode = '23514';
  end if;

  -- ---- class 8: the two instants ------------------------------------------------------------
  begin
    v_started  := (p_input->>'started_at')::timestamptz;
    v_finished := (p_input->>'finished_at')::timestamptz;
  exception when others then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: started_at "%" / finished_at "%" are not timestamps.',
      p_input->>'started_at', p_input->>'finished_at'
      using errcode = '23514';
  end;
  if v_finished < v_started then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: finished_at % precedes started_at %.',
      v_finished, v_started
      using errcode = '23514';
  end if;

  -- ---- write ---------------------------------------------------------------------------------
  -- Sealed on write. A system execution is over by the time it is recorded; leaving the trace open
  -- would leave it rewritable, which K6's completed_traces_still_mutable exists to catch.
  v_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
    'subject_kind',     'system_execution',
    'subject_ref',      v_comp.component_id,
    'component_id',     v_comp.component_id,
    'system_actor_id',  p_input->>'system_actor',
    'actor_role_id',    p_input->>'accountable_role_id',
    'manager_role_id',  coalesce((select manager_role_id from public.org_role
                                   where role_id = p_input->>'accountable_role_id'), ''),
    'authority_result', p_input->>'authority_result',
    'state_before',     p_input->>'state_before',
    'state_after',      p_input->>'state_after',
    -- md5 of the empty string is a real-looking hash of nothing, and a hash that asserts "the
    -- input was empty" when the truth is "no input was recorded" is a fabricated fact inside the
    -- record that is supposed to establish facts. A caller that recorded no input says so.
    'input_hash',       coalesce(nullif(p_input->>'input_hash',''),
                                 case when p_input ? 'input' then md5(p_input->>'input')
                                      else 'no_input_recorded' end),
    'output_hash',      coalesce(nullif(p_input->>'output_hash',''),
                                 md5(v_result || coalesce(p_input->>'failure',''))),
    'evidence_refs',    jsonb_build_array(jsonb_build_object(
                          's3_system_execution', jsonb_build_object(
                            'trigger_source',  p_input->>'trigger_source',
                            'correlation_id',  p_input->>'correlation_id',
                            'causation_id',    p_input->>'causation_id',
                            'result',          v_result,
                            'failure',         p_input->'failure',
                            'started_at',      v_started,
                            'finished_at',     v_finished))),
    'status',           'sealed'));

  insert into public.phase_c_system_execution (
    trace_id, component_id, system_actor, accountable_role_id, workflow_id, step_id,
    technical_scope, trigger_source, authority_result, state_before, state_after, result,
    failure, correlation_id, causation_id, started_at, finished_at)
  values (
    v_trace, v_comp.component_id, p_input->>'system_actor', p_input->>'accountable_role_id',
    v_wf, v_step, v_scope, p_input->>'trigger_source', p_input->>'authority_result',
    p_input->>'state_before', p_input->>'state_after', v_result,
    nullif(btrim(coalesce(p_input->>'failure','')), ''),
    p_input->>'correlation_id', p_input->>'causation_id', v_started, v_finished);

  return v_trace;
end
$function$;
