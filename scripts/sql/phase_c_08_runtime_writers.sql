-- Phase C — the remaining canonical runtime writers, plus the tool and knowledge interfaces.
--
-- Every routine named in a Phase C binding row exists after this file.  That matters more than
-- it sounds: a binding CSV that names a function which is not deployed is a document, not a
-- connection, and scripts/checks/phase_c_invariants.test.mjs re-reads each of these out of
-- pg_proc for exactly that reason.
--
-- The tool and knowledge sections connect INTERFACES.  No embedding is computed, no model is
-- called and no knowledge content is created, changed or certified here — that is Phase C's
-- declared boundary and the zero-cost rule depends on it holding.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. the task writer
create or replace function public.fn_phase_c_task_create(p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_id bigint; v_owner text; v_manager text; v_dept text;
begin
  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_body->>'accountable_role_id');
  if v_owner is null or not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_phase_c_task_create: owner %L does not resolve to an active canonical role',
      p_body->>'accountable_role_id' using errcode = '23514';
  end if;
  select r.manager_role_id, r.primary_department_id into v_manager, v_dept
    from public.org_role r where r.role_id = v_owner;
  insert into public.phase_c_task (
    source_kind, source_ref, command_id, run_id, workflow_id, step_id, accountable_role_id,
    manager_role_id, department_id, objective, required_inputs, requested_output,
    acceptance_criteria, closure_criteria, priority, due_at, sla_policy_id, reviewer_required,
    reviewer_role_id, authority_class, idempotency_key, state)
  values (
    coalesce(p_body->>'source_kind','management'), coalesce(p_body->>'source_ref',''),
    (p_body->>'command_id')::bigint, (p_body->>'run_id')::bigint,
    nullif(p_body->>'workflow_id',''), nullif(p_body->>'step_id',''),
    v_owner, coalesce(v_manager,''), coalesce(v_dept,''),
    coalesce(p_body->>'objective','(objective not stated)'),
    coalesce(p_body->>'required_inputs',''), coalesce(p_body->>'requested_output',''),
    coalesce(p_body->>'acceptance_criteria','Evidence-backed outcome accepted by the manager.'),
    coalesce(p_body->>'closure_criteria','Closure criteria of the bound workflow satisfied.'),
    coalesce(p_body->>'priority','P2'), (p_body->>'due_at')::timestamptz,
    coalesce(p_body->>'sla_policy_id',''),
    coalesce((p_body->>'reviewer_required')::boolean, false),
    coalesce(p_body->>'reviewer_role_id',''),
    coalesce(p_body->>'authority_class','routine_operational_decision'),
    coalesce(nullif(p_body->>'idempotency_key',''),
             'task:' || md5(coalesce(p_body->>'source_ref','') || ':' || v_owner || ':' || coalesce(p_body->>'objective',''))),
    'queued')
  on conflict (idempotency_key) do nothing
  returning task_id into v_id;
  if v_id is null then
    -- the duplicate path: return the row that already exists rather than invent a second
    select task_id into v_id from public.phase_c_task
      where idempotency_key = coalesce(nullif(p_body->>'idempotency_key',''),
        'task:' || md5(coalesce(p_body->>'source_ref','') || ':' || v_owner || ':' || coalesce(p_body->>'objective','')));
  end if;
  if v_id is null then
    raise exception 'fn_phase_c_task_create wrote no row and found none' using errcode = '23502';
  end if;
  return v_id;
end $$;
revoke all on function public.fn_phase_c_task_create(jsonb) from public;
grant execute on function public.fn_phase_c_task_create(jsonb) to service_role;

create or replace function public.fn_phase_c_task_transition(
  p_task_id bigint, p_to_state text, p_actor text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare t public.phase_c_task%rowtype; v_trace bigint;
begin
  select * into t from public.phase_c_task where task_id = p_task_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error','not_found','task_id', p_task_id);
  end if;
  if not public.fn_phase_c_task_transition_allowed(t.state, p_to_state) then
    return jsonb_build_object('ok', false, 'error','invalid_transition',
      'from', t.state, 'to', p_to_state,
      'message','The Phase C task state model does not allow that move.');
  end if;
  if p_to_state = 'completed' and t.reviewer_required
     and not public.fn_phase_c_reviewer_independent(t.accountable_role_id, t.reviewer_role_id) then
    return jsonb_build_object('ok', false, 'error','reviewer_not_independent',
      'owner', t.accountable_role_id, 'reviewer', t.reviewer_role_id);
  end if;
  if p_to_state = 'blocked' and coalesce(p_ctx->>'blocker','') = '' then
    return jsonb_build_object('ok', false, 'error','blocker_required',
      'message','A blocked task must name its blocker and the owner who resolves it.');
  end if;

  update public.phase_c_task set
    state = p_to_state,
    blocker = case when p_to_state = 'blocked' then p_ctx->>'blocker' else '' end,
    blocker_owner_role_id = case when p_to_state = 'blocked' then coalesce(p_ctx->>'blocker_owner_role_id','') else '' end,
    closed_at = case when p_to_state in ('completed','cancelled','failed','superseded') then now() else null end
  where task_id = p_task_id;

  v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
    'subject_kind','task', 'subject_ref', p_task_id::text, 'task_id', p_task_id,
    'command_id', t.command_id, 'actor_role_id', p_actor, 'manager_role_id', t.manager_role_id,
    'state_before', t.state, 'state_after', p_to_state, 'status', 'sealed'));
  update public.phase_c_task set trace_id = v_trace where task_id = p_task_id;
  return jsonb_build_object('ok', true, 'task_id', p_task_id, 'from', t.state, 'to', p_to_state,
                            'trace_id', v_trace);
end $$;
revoke all on function public.fn_phase_c_task_transition(bigint, text, text, jsonb) from public;
grant execute on function public.fn_phase_c_task_transition(bigint, text, text, jsonb) to service_role;

-- ============================================================ 1b. the one overlay exception
--
-- Phase B froze exactly one step whose accountable owner is not a standing employee: W14-S05,
-- an `analysis` step, owned by the dynamic actor `relevant_category_overlay`.  Master spec §12
-- lets overlays contribute to W05, W06, W07, W10 and W14, and hold accountability only for an
-- analysis step inside that scope.  Measured on 15 Aug 2026: exactly one of the 257 steps has a
-- non-canonical owner and it is that one.
--
-- This is stated as its own function rather than folded into fn_phase_c_actor_may_own, because
-- the two questions are genuinely different: an overlay may never OWN A TASK (that guard stays
-- absolute) and may own this ONE frozen analysis step.  Collapsing them would have weakened the
-- first to accommodate the second.
create or replace function public.fn_phase_c_step_owner_valid(p_step_id text, p_owner text)
returns boolean language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare s public.phase_b_workflow_step%rowtype; v_kind text;
begin
  if public.fn_phase_c_actor_may_own(p_owner) then return true; end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then return false; end if;
  if p_owner = 'relevant_category_overlay'
     and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10','W14') then
    return true;
  end if;
  select kind into v_kind from public.fn_phase_c_resolve_actor(p_owner);
  return v_kind = 'overlay' and s.step_type = 'analysis'
     and s.workflow_id in ('W05','W06','W07','W10','W14');
end $$;
revoke all on function public.fn_phase_c_step_owner_valid(text, text) from public;
grant execute on function public.fn_phase_c_step_owner_valid(text, text) to service_role;

-- ============================================================ 2. the step advance
--
-- The single door through which a workflow step moves.  It resolves the actor, evaluates the
-- gate, checks authority, validates the output, writes the step run and emits the event — and
-- refuses at the first failure without changing protected state.
create or replace function public.fn_phase_c_step_advance(
  p_run_id bigint, p_step_id text, p_actor text, p_body jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  s public.phase_b_workflow_step%rowtype;
  r public.phase_c_workflow_run%rowtype;
  g record; a record; o record;
  v_owner text; v_step_run bigint; v_trace bigint; v_prev bigint; v_attempt bigint := 1;
  v_idem text;
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

  select role_id into v_owner from public.fn_phase_c_resolve_actor(p_actor);
  if v_owner is null then
    return jsonb_build_object('ok', false, 'error','actor_not_resolvable', 'actor', p_actor);
  end if;
  -- The accountable owner of the step is frozen.  A different employee may not simply take it.
  -- The single exception is the frozen overlay-owned analysis step, where the placeholder
  -- resolves at runtime to whichever category overlay the inquiry selected.
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

  if coalesce(s.founder_gate,'') <> '' then
    select * into g from public.fn_phase_c_gate_evaluate(s.founder_gate,
      coalesce(p_body->'gate_evidence','{}'::jsonb) || jsonb_build_object('actor_role_id', v_owner));
    if not g.passed then
      return jsonb_build_object('ok', false, 'error','gate_failed', 'gate', s.founder_gate, 'reason', g.reason);
    end if;
  end if;

  select * into a from public.fn_phase_c_authority_check(
    coalesce(p_body->>'authority_class','routine_operational_decision'), v_owner,
    nullif(s.independent_reviewer_role_id,''));
  if not a.allowed then
    return jsonb_build_object('ok', false, 'error','authority_refused', 'reason', a.reason);
  end if;

  if p_body ? 'output' then
    select * into o from public.fn_phase_c_output_validate(p_step_id, p_body->'output');
    if not o.valid then
      return jsonb_build_object('ok', false, 'error','failed_incomplete', 'reason', o.reason,
        'message','A truncated or invalid consequential output creates no side effect.');
    end if;
  end if;

  -- Retry preserves the first attempt: a new row that points at the original, never an update.
  select step_run_id, attempt_no into v_prev, v_attempt from public.phase_c_workflow_step_run
    where run_id = p_run_id and step_id = p_step_id order by attempt_no desc limit 1;
  if v_prev is not null then v_attempt := v_attempt + 1; end if;
  v_idem := s.idempotency_scope || '|' || p_run_id || '|' || p_step_id || '|' || v_attempt;

  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no, first_attempt_id,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key, finished_at)
  values (p_run_id, p_step_id, v_owner, coalesce(s.independent_reviewer_role_id,''),
          coalesce(p_body->>'state','completed'), v_attempt,
          coalesce(v_prev, null),
          encode(sha256(convert_to(coalesce(p_body->>'input',''), 'UTF8')), 'hex'),
          encode(sha256(convert_to(coalesce(p_body->'output'->>'output',''), 'UTF8')), 'hex'),
          case when coalesce(s.founder_gate,'') <> '' then jsonb_build_array(s.founder_gate) else '[]'::jsonb end,
          a.reason, v_idem, now())
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_phase_c_step_advance wrote no step run for %', p_step_id using errcode = '23502';
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', v_step_run::text, 'run_id', p_run_id,
    'step_run_id', v_step_run, 'actor_role_id', v_owner,
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'reviewer_independent', public.fn_phase_c_reviewer_independent(v_owner, s.independent_reviewer_role_id),
    'authority_result', a.reason,
    'gates', case when coalesce(s.founder_gate,'') <> '' then jsonb_build_array(s.founder_gate) else '[]'::jsonb end,
    'state_before','active', 'state_after', coalesce(p_body->>'state','completed'), 'status','sealed'));
  update public.phase_c_workflow_step_run set trace_id = v_trace where step_run_id = v_step_run;

  return jsonb_build_object('ok', true, 'step_run_id', v_step_run, 'attempt', v_attempt,
                            'first_attempt_id', v_prev, 'owner', v_owner, 'trace_id', v_trace,
                            'authority', a.reason);
end $$;
revoke all on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) from public;
grant execute on function public.fn_phase_c_step_advance(bigint, text, text, jsonb) to service_role;

-- ============================================================ 3. the handoff runtime
create or replace function public.fn_phase_c_handoff_packet_valid(p_handoff_id text, p_packet jsonb)
returns table (valid boolean, missing text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare h public.phase_b_handoff%rowtype; v_missing text;
begin
  select * into h from public.phase_b_handoff where handoff_id = p_handoff_id;
  if not found then
    valid := false; missing := format('unknown handoff %L — fail closed', p_handoff_id); return next; return;
  end if;
  if p_packet is null or jsonb_typeof(p_packet) <> 'object' then
    valid := false; missing := 'no packet supplied'; return next; return;
  end if;
  v_missing := coalesce((select string_agg(k, ', ')
    from unnest(array['business_object_id','object_version','output','evidence_refs','requested_action']) k
    where not (p_packet ? k)), '');
  valid := (v_missing = '');
  missing := v_missing;
  return next;
end $$;
revoke all on function public.fn_phase_c_handoff_packet_valid(text, jsonb) from public;
grant execute on function public.fn_phase_c_handoff_packet_valid(text, jsonb) to service_role;

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_handoff_open was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_phase_c_handoff_open(bigint, text, jsonb) from public;
grant execute on function public.fn_phase_c_handoff_open(bigint, text, jsonb) to service_role;

create or replace function public.fn_phase_c_handoff_decide(
  p_handoff_run_id bigint, p_decision text, p_actor text, p_ctx jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare hr public.phase_c_handoff_run%rowtype; v_actor text; v_trace bigint;
begin
  select * into hr from public.phase_c_handoff_run where handoff_run_id = p_handoff_run_id for update;
  if not found then return jsonb_build_object('ok', false, 'error','not_found'); end if;
  if hr.status <> 'open' then
    return jsonb_build_object('ok', false, 'error','already_decided', 'status', hr.status);
  end if;
  select role_id into v_actor from public.fn_phase_c_resolve_actor(p_actor);
  if v_actor is distinct from hr.receiving_role_id then
    return jsonb_build_object('ok', false, 'error','not_the_receiver',
      'receiver', hr.receiving_role_id, 'actor', coalesce(v_actor, p_actor));
  end if;
  if p_decision = 'reject'
     and (coalesce(p_ctx->>'reason','') = '' or coalesce(p_ctx->>'missing','') = '') then
    return jsonb_build_object('ok', false, 'error','rejection_must_be_specific',
      'message','A rejection must state the exact missing or invalid item and the return owner.');
  end if;

  update public.phase_c_handoff_run set
    status = case when p_decision = 'accept' then 'accepted' else 'rejected' end,
    rejection_reason = case when p_decision = 'accept' then '' else p_ctx->>'reason' end,
    missing_items = case when p_decision = 'accept' then '' else p_ctx->>'missing' end,
    return_owner_role_id = case when p_decision = 'accept' then return_owner_role_id
                                else coalesce(nullif(p_ctx->>'return_owner',''), return_owner_role_id, sending_role_id) end
  where handoff_run_id = p_handoff_run_id;

  v_trace := public.fn_phase_c_trace_write('TRACE-HANDOFF', jsonb_build_object(
    'subject_kind','handoff', 'subject_ref', p_handoff_run_id::text, 'run_id', hr.run_id,
    'actor_role_id', v_actor, 'state_before','open',
    'state_after', case when p_decision = 'accept' then 'accepted' else 'rejected' end,
    'status','sealed'));
  return jsonb_build_object('ok', true, 'handoff_run_id', p_handoff_run_id,
    'status', case when p_decision = 'accept' then 'accepted' else 'rejected' end,
    'accountable_now', (select accountable_until_accept_role_id from public.phase_c_handoff_run
                        where handoff_run_id = p_handoff_run_id),
    'trace_id', v_trace);
end $$;
revoke all on function public.fn_phase_c_handoff_decide(bigint, text, text, jsonb) from public;
grant execute on function public.fn_phase_c_handoff_decide(bigint, text, text, jsonb) to service_role;

create or replace function public.fn_phase_c_handoff_overdue()
returns table (handoff_run_id bigint, handoff_id text, sender text, receiver text,
               due_at timestamptz, hours_late numeric)
language sql stable set search_path to 'public', 'pg_temp' as $$
  select h.handoff_run_id, h.handoff_id, h.sending_role_id, h.receiving_role_id, h.due_at,
         round(extract(epoch from (now() - h.due_at)) / 3600.0, 1)
  from public.phase_c_handoff_run h
  where h.status = 'open' and h.due_at is not null and h.due_at < now()
  order by h.due_at;
$$;
revoke all on function public.fn_phase_c_handoff_overdue() from public;
grant execute on function public.fn_phase_c_handoff_overdue() to service_role;

-- ============================================================ 4. overlay invocation
--
-- An overlay is invoked, advises, and returns to its owner.  It may NEVER hold dispatch
-- authority or own a required step; the trigger below refuses that write rather than trusting
-- a convention.
create or replace function public.fn_phase_c_overlay_invoke(p_overlay_id text, p_ctx jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare b public.phase_c_overlay_binding%rowtype; v_trace bigint; v_missing text;
begin
  select * into b from public.phase_c_overlay_binding where overlay_id = p_overlay_id;
  if not found then
    select * into b from public.phase_c_overlay_binding
      where live_role_id = (select role_id from public.fn_phase_c_resolve_actor(p_overlay_id));
  end if;
  if not found then
    return jsonb_build_object('ok', false, 'error','unknown_overlay', 'overlay_id', p_overlay_id);
  end if;
  v_missing := coalesce((select string_agg(k, ', ') from unnest(array['inquiry_id']) k
                         where not (coalesce(p_ctx,'{}'::jsonb) ? k)), '');
  v_trace := public.fn_phase_c_trace_write('TRACE-CATEGORY-ADVICE', jsonb_build_object(
    'subject_kind','overlay', 'subject_ref', b.overlay_id,
    'actor_role_id', b.live_role_id, 'status', case when v_missing = '' then 'sealed' else 'open' end,
    'evidence_refs', coalesce(p_ctx->'evidence_refs','[]'::jsonb)));
  return jsonb_build_object(
    'ok', v_missing = '', 'overlay_id', b.overlay_id, 'live_role_id', b.live_role_id,
    'inquiry_id', p_ctx->>'inquiry_id',
    'retrieved_fields', coalesce(p_ctx->'retrieved_fields','[]'::jsonb),
    'never_infer_checks', jsonb_build_array('quantity','specification','delivery_date','budget'),
    'missing_fields', v_missing,
    'return_owner', b.result_returns_to_role_id,
    'may_dispatch', false,
    'status', case when v_missing = '' then 'success' else 'empty' end,
    'trace_id', v_trace);
end $$;
revoke all on function public.fn_phase_c_overlay_invoke(text, jsonb) from public;
grant execute on function public.fn_phase_c_overlay_invoke(text, jsonb) to service_role;

create or replace function public.fn_phase_c_overlay_may_not_dispatch()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
declare v_kind text;
begin
  select kind into v_kind from public.fn_phase_c_resolve_actor(new.accountable_role_id);
  if v_kind = 'overlay' then
    raise exception 'phase_c_task: category overlay %L may advise but may never own a task or hold dispatch authority',
      new.accountable_role_id using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists z10_phase_c_overlay_not_accountable on public.phase_c_task;
create trigger z10_phase_c_overlay_not_accountable before insert or update on public.phase_c_task
  for each row execute function public.fn_phase_c_overlay_may_not_dispatch();

-- ============================================================ 5. context, tools, knowledge
--
-- Interfaces only.  No retrieval is performed, no embedding computed, no model called.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_role_context was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_phase_c_role_context(text) from public;
grant execute on function public.fn_phase_c_role_context(text) to service_role;

-- A role cannot claim a tool result without a stored one.  This answers authorization only;
-- the result itself lives in agent_tool_call and is referenced by id/hash.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_tool_authorized was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_phase_c_tool_authorized(text, text) from public;
grant execute on function public.fn_phase_c_tool_authorized(text, text) to service_role;

-- role + department + task + workflow + category + jurisdiction + stage -> permitted scopes.
-- Resolution and boundaries only: this returns WHICH scopes are permitted and which mappings
-- are missing.  It does not retrieve, embed or rank anything.
-- ROUTINE REMOVED 7 September 2026. public.fn_phase_c_knowledge_scope was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke all on function public.fn_phase_c_knowledge_scope(text, text, text) from public;
grant execute on function public.fn_phase_c_knowledge_scope(text, text, text) to service_role;
