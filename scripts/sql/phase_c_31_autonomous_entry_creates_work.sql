-- Phase C correction 3 — the autonomous entry point has to create work.
--
-- What the audit measured, by calling the canonical entry points itself rather than reading a
-- registry: a W05 workflow start and a W05-S01 step advance both returned ok:true, evaluated
-- twelve gates, checked authority and bypassed the founder and the Chief of Staff exactly as
-- designed — and created ZERO tasks and ZERO events. The step finished in the same statement it
-- opened, with input_hash = output_hash = e3b0c442…b855, the SHA-256 of the empty string.
--
-- The design says: event -> canonical event router -> canonical workflow and step -> exact
-- accountable employee -> specialists/reviewers -> outcome and KPI -> manager response. It reached
-- "canonical workflow and step" and stopped.
--
-- fn_phase_c_event_ingress below is the missing transaction. It is atomic by construction: every
-- object it must produce is asserted non-null before it returns, so a partial ingress raises
-- instead of leaving a workflow run nobody owns.

-- ================================================================ 1. a run carries its own trace
-- TRACE-WORKFLOW is trace_required=YES, completed_without_trace_allowed=NO, and every workflow run
-- the audit created had trace_id NULL. The trace is now written by the starter, in the same
-- transaction, and becomes the parent of every task the run produces.
create or replace function public.fn_phase_c_workflow_start(
  p_workflow_id text, p_business_object_id text, p_ctx jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare w public.phase_b_workflow%rowtype; v_id bigint; v_dedupe text; v_state text; v_trace bigint;
begin
  select * into w from public.phase_b_workflow where workflow_id = p_workflow_id;
  if not found then
    raise exception 'unknown workflow % — fail closed', p_workflow_id using errcode = '23503';
  end if;
  if not public.fn_phase_c_actor_may_own(w.accountable_role_id) then
    raise exception 'workflow % owner % does not resolve to an active canonical role',
      p_workflow_id, w.accountable_role_id using errcode = '23514';
  end if;
  v_dedupe := p_workflow_id || ':' || p_business_object_id || ':' || coalesce(p_ctx->>'object_version', '1');
  select run_id into v_id from public.phase_c_workflow_run where dedupe_key = v_dedupe;
  if v_id is not null then return v_id; end if;         -- idempotent start, not a duplicate run
  select state into v_state from public.phase_b_workflow_state
    where state in ('queued','not_started','initiated') order by state limit 1;
  insert into public.phase_c_workflow_run
    (workflow_id, business_object_id, object_version, start_event, accountable_role_id,
     state, dedupe_key, command_id)
  values (p_workflow_id, p_business_object_id, coalesce((p_ctx->>'object_version')::bigint, 1),
          coalesce(p_ctx->>'start_event', w.start_event), w.accountable_role_id,
          coalesce(v_state, (select state from public.phase_b_workflow_state order by state limit 1)),
          v_dedupe, (p_ctx->>'command_id')::bigint)
  returning run_id into v_id;
  if v_id is null then
    raise exception 'fn_phase_c_workflow_start wrote no row for %', p_workflow_id using errcode = '23502';
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-WORKFLOW', jsonb_build_object(
    'subject_kind','workflow_run', 'subject_ref', v_id::text, 'run_id', v_id,
    'command_id', (p_ctx->>'command_id')::bigint,
    'actor_role_id', w.accountable_role_id, 'system_actor_id','system.workflow_engine',
    'input_hash', encode(sha256(convert_to(coalesce(p_ctx::text,'{}'), 'UTF8')), 'hex'),
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'business_object_id', p_business_object_id, 'dedupe_key', v_dedupe,
      'source', coalesce(p_ctx->>'source','unspecified'))),
    'state_before','', 'state_after', coalesce(v_state,'queued'), 'status','open'));
  update public.phase_c_workflow_run set trace_id = v_trace where run_id = v_id;
  if (select trace_id from public.phase_c_workflow_run where run_id = v_id) is null then
    raise exception 'workflow run % has no trace after start', v_id using errcode = '23502';
  end if;
  return v_id;
end $$;
revoke all on function public.fn_phase_c_workflow_start(text, text, jsonb) from public;
grant execute on function public.fn_phase_c_workflow_start(text, text, jsonb) to service_role;

-- ================================================================ 2. the entry step
-- Deterministic and registry-driven: the step in this workflow that no handoff points at. W05 has
-- three such steps (S01, S08, S09), so the lowest id is taken and the choice is stated rather than
-- left to row order.
create or replace function public.fn_phase_c_entry_step(p_workflow_id text)
returns text language sql stable set search_path to 'public', 'pg_temp' as $$
  select min(s.step_id)
    from public.phase_b_workflow_step s
   where s.workflow_id = p_workflow_id
     and not exists (select 1 from public.phase_b_handoff h where h.to_step_id = s.step_id);
$$;
revoke all on function public.fn_phase_c_entry_step(text) from public;
grant execute on function public.fn_phase_c_entry_step(text) to service_role;

-- ================================================================ 3. the ingress transaction
-- One valid canonical event in; a run, a step run, an owner, a task, traces and a durable outbox
-- record out — or nothing at all.
create or replace function public.fn_phase_c_event_ingress(
  p_event_id text, p_business_object_id text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  e public.phase_b_event%rowtype;
  s public.phase_b_workflow_step%rowtype;
  v_run bigint; v_step text; v_step_run bigint; v_task bigint; v_outbox bigint;
  v_owner text; v_input_hash text; v_run_trace bigint; v_task_trace bigint;
begin
  select * into e from public.phase_b_event where event_id = p_event_id;
  if not found then
    raise exception 'fn_phase_c_event_ingress: % is not a canonical Phase B event — fail closed',
      p_event_id using errcode = '23503';
  end if;
  if coalesce(btrim(p_business_object_id),'') = '' then
    raise exception 'fn_phase_c_event_ingress: a business object id is required' using errcode = '23502';
  end if;

  v_input_hash := encode(sha256(convert_to(
    p_event_id || '|' || p_business_object_id || '|' || coalesce(p_ctx::text,'{}'), 'UTF8')), 'hex');

  -- (a) workflow run, with its own trace
  v_run := public.fn_phase_c_workflow_start(e.workflow_id, p_business_object_id,
             p_ctx || jsonb_build_object('start_event', p_event_id));
  select trace_id into v_run_trace from public.phase_c_workflow_run where run_id = v_run;

  -- (b) the current step
  v_step := public.fn_phase_c_entry_step(e.workflow_id);
  if v_step is null then
    raise exception 'fn_phase_c_event_ingress: workflow % declares no entry step', e.workflow_id
      using errcode = '23502';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = v_step;

  -- (c) the accountable canonical role, resolved not assumed
  select role_id into v_owner from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  if v_owner is null or not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_phase_c_event_ingress: step % owner % does not resolve to an active canonical role',
      v_step, s.accountable_role_id using errcode = '23514';
  end if;

  -- (d) the step run, OPEN. An ingress starts work; it does not finish it in the same statement.
  select step_run_id into v_step_run from public.phase_c_workflow_step_run
   where run_id = v_run and step_id = v_step and state = 'active';
  if v_step_run is null then
    insert into public.phase_c_workflow_step_run
      (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
       input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
    values (v_run, v_step, v_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
            v_input_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet',
            s.idempotency_scope || '|' || v_run || '|' || v_step || '|ingress')
    on conflict (idempotency_key) do nothing
    returning step_run_id into v_step_run;
    if v_step_run is null then
      select step_run_id into v_step_run from public.phase_c_workflow_step_run
       where idempotency_key = s.idempotency_scope || '|' || v_run || '|' || v_step || '|ingress';
    end if;
  end if;

  -- (e) the operational task the accountable employee actually receives.  This is the object whose
  --     absence made the whole autonomous path a no-op.  Its trace is written by the trigger in
  --     phase_c_20 and parented to the run trace.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind','workflow_event', 'source_ref', p_event_id || ':' || p_business_object_id,
    'run_id', v_run, 'workflow_id', e.workflow_id, 'step_id', v_step,
    'accountable_role_id', v_owner,
    'objective', format('%s: perform %s for %s.', e.event_name, v_step, p_business_object_id),
    'required_inputs', coalesce(p_ctx->>'required_inputs',''),
    'requested_output', 'The step output required by the frozen Phase B contract, with evidence.',
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || v_step));
  select trace_id into v_task_trace from public.phase_c_task where task_id = v_task;

  -- (f) the durable event record.  Same transaction as the business state, by construction.
  v_outbox := public.fn_phase_c_outbox_emit(
    p_event_id, coalesce(p_ctx->>'producer', e.emitted_by),
    jsonb_build_object('run_id', v_run, 'step_id', v_step, 'task_id', v_task,
                       'business_object_id', p_business_object_id,
                       'workflow_id', e.workflow_id, 'input_hash', v_input_hash),
    'ingress:' || p_event_id || ':' || p_business_object_id);
  update public.phase_c_event_outbox set trace_id = v_run_trace
    where outbox_id = v_outbox and trace_id is null;

  -- Atomic or nothing.  Each of these is a thing the audit found missing; none of them is allowed
  -- to be quietly absent from a successful return.
  if v_run is null or v_step_run is null or v_task is null or v_outbox is null
     or v_run_trace is null or v_task_trace is null then
    raise exception 'fn_phase_c_event_ingress incomplete: run=% step_run=% task=% outbox=% run_trace=% task_trace=%',
      v_run, v_step_run, v_task, v_outbox, v_run_trace, v_task_trace using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'event_id', p_event_id, 'workflow_id', e.workflow_id,
    'business_object_id', p_business_object_id, 'run_id', v_run, 'step_id', v_step,
    'step_run_id', v_step_run, 'accountable_role_id', v_owner, 'task_id', v_task,
    'outbox_id', v_outbox, 'run_trace_id', v_run_trace, 'task_trace_id', v_task_trace,
    'input_hash', v_input_hash);
end $$;
revoke all on function public.fn_phase_c_event_ingress(text, text, jsonb) from public;
grant execute on function public.fn_phase_c_event_ingress(text, text, jsonb) to service_role;
comment on function public.fn_phase_c_event_ingress(text, text, jsonb) is
  'The canonical autonomous entry: one valid Phase B event becomes a workflow run, an open step '
  'run, a resolved accountable employee, an operational task, decision traces and a durable outbox '
  'record — atomically, or it raises. The founder and the Chief of Staff are not on this path.';

-- ================================================================ 4. the step-level event
-- EV-W05-S01-COMPLETED is named phase_b.w05.w05_s01.completed in the registry, so the step event is
-- resolved by querying that registry on the workflow and the step's own name. The id is never
-- assembled: a miss returns NULL and the caller emits nothing.
create or replace function public.fn_phase_c_step_event(p_step_id text, p_lifecycle text)
returns text language sql stable set search_path to 'public', 'pg_temp' as $$
  select e.event_id
    from public.phase_b_workflow_step s
    join public.phase_b_event e on e.workflow_id = s.workflow_id
   where s.step_id = p_step_id
     and e.event_name like '%.' || lower(replace(p_step_id, '-', '_')) || '.'
                                || lower(btrim(coalesce(p_lifecycle,'')))
   order by e.event_id
   limit 1;
$$;
revoke all on function public.fn_phase_c_step_event(text, text) from public;
grant execute on function public.fn_phase_c_step_event(text, text) to service_role;

-- ================================================================ 5. executing a step
-- Reproduced from the live definition with three changes, each answering an audit finding: the
-- output hash is the real structured output, a completion with no output is refused, and the
-- canonical step event is emitted and the step's task closed in the same transaction.
CREATE OR REPLACE FUNCTION public.fn_phase_c_step_advance(p_run_id bigint, p_step_id text, p_actor text, p_body jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_output_hash text; v_state_out text; v_step_event text; v_task_closed bigint;
  v_hop text; v_from text;
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

  -- THE OUTPUT HASH IS THE OUTPUT, NOT THE ABSENCE OF ONE.
  -- This read p_body->'output'->>'output' — a key nothing writes — so every successful step hashed
  -- the empty string and produced e3b0c442…b855. A constant is not evidence, and a step that
  -- completes with no output has not completed. Refused, never defaulted.
  v_state_out := coalesce(p_body->>'state','completed');
  if v_state_out = 'completed'
     and coalesce(p_body->'output', 'null'::jsonb) in ('null'::jsonb, '{}'::jsonb, '""'::jsonb) then
    return jsonb_build_object('ok', false, 'error','output_required',
      'step', p_step_id,
      'message','A step cannot complete with no structured output. Send body.output, or advance the '
                'step to a non-terminal state.');
  end if;
  v_output_hash := case when p_body ? 'output'
    then encode(sha256(convert_to((p_body->'output')::text, 'UTF8')), 'hex') else '' end;

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
          v_output_hash,
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

  -- The canonical step event, resolved from the frozen registry, written in the same transaction.
  -- Before this, fn_founder_command_submit was the ONLY routine in the database that emitted
  -- anything at all, so 347 CONNECTED event bindings had one producer between them.
  v_step_event := public.fn_phase_c_step_event(p_step_id, v_state_out);
  if v_step_event is not null then
    perform public.fn_phase_c_outbox_emit(v_step_event, v_owner,
      jsonb_build_object('run_id', p_run_id, 'step_id', p_step_id, 'step_run_id', v_step_run,
                         'output_hash', v_output_hash, 'attempt', v_attempt),
      'step:' || v_step_run);
  end if;

  -- The task the ingress created for this step follows the step. Leaving it open would put the
  -- step run and the employee's queue in permanent disagreement.
  -- The task follows its step through the STATE MODEL, one legal hop at a time. A direct
  -- UPDATE to 'completed' was refused by fn_phase_c_task_state_guard, correctly: queued -> completed
  -- is not a transition this company recognises, and forcing it would have written a closure nobody
  -- ever picked up. Each hop goes through fn_phase_c_task_transition, so each hop is traced.
  if v_state_out in ('completed','failed') then
    for v_task_closed in
      select t.task_id from public.phase_c_task t
       where t.run_id = p_run_id and t.step_id = p_step_id
         and t.state in ('queued','assigned','accepted','in_progress','blocked','review_required')
       order by t.task_id
    loop
      foreach v_hop in array (case when v_state_out = 'completed'
                                   then array['assigned','accepted','in_progress','completed']
                                   else array['failed'] end) loop
        select t.state into v_from from public.phase_c_task t where t.task_id = v_task_closed;
        continue when v_from = v_hop;
        exit when not public.fn_phase_c_task_transition_allowed(v_from, v_hop);
        perform public.fn_phase_c_task_transition(v_task_closed, v_hop, v_owner,
          jsonb_build_object('evidence', 'step ' || p_step_id || ' ' || v_state_out,
                             'output_hash', v_output_hash));
      end loop;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'step_run_id', v_step_run, 'attempt', v_attempt,
                            'first_attempt_id', coalesce((select first_attempt_id from public.phase_c_workflow_step_run
                                                          where step_run_id = v_step_run), v_prev),
                            'owner', v_owner, 'trace_id', v_trace,
                            'gates_evaluated', v_gates, 'founder_boundary', s.founder_gate,
                            'authority', a.reason,
                            'output_hash', v_output_hash, 'event_emitted', v_step_event,
                            'task_closed', v_task_closed);
end $function$;
revoke all on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) from public;
grant execute on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) to service_role;
