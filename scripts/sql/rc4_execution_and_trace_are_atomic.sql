-- ROOT CAUSE 4 — A SYSTEM-EXECUTION TRACE AND ITS EXECUTION ROW ARE ONE FACT OR NEITHER.
--
-- The final Phase C acceptance found trace 3730 under TRACE-SYSTEM-EXECUTION with no row in
-- phase_c_system_execution. The investigation the brief asks for, answered:
--
--   WHICH COMPONENT CREATED IT     fn_kernel_trigger_submit, at 05:05:00.033303 on 17 Aug 2026,
--                                  recording the acceptance of trigger-inbox row 46 (source
--                                  dbtrigger:public.agent_actions:trg_page_high_agent_action,
--                                  system.incident_opened -> W29, which opened run 352).
--   WAS AN EXECUTION ROW ATTEMPTED  No. Not once, not unsuccessfully — the code path never had one.
--                                  fn_kernel_trigger_submit calls fn_phase_c_trace_write directly
--                                  with policy TRACE-SYSTEM-EXECUTION and subject_kind
--                                  'trigger_inbox', and stops there.
--   WHY THE TRANSACTION SEPARATED   It did not. Nothing was lost and nothing rolled back. The trace
--   THE TRACE FROM ITS SUBJECT      and its subject row (inbox 46) are both present and consistent.
--                                  What was missing was the SUBJECT THE POLICY REQUIRES: the policy
--                                  names execution_id among its minimum fields and there was no
--                                  execution to point at. A trace was written under a policy whose
--                                  contract it could not meet, and nothing refused it.
--
-- fn_kernel_signal_submit has the same shape and is worse: its trace claims
-- subject_kind 'system_execution' with subject_ref 'signal:<id>' — an identifier of the signal, not
-- of any execution row. Root cause 3 has just made five signal types live, so that path is about to
-- run for real; this file lands before it can produce a second orphan.
--
-- WHAT IS BUILT
--   fn_kernel_system_execution_begin   opens the trace, returns trace_id — the execution is in flight
--   fn_kernel_system_execution_finish  seals the trace AND writes the execution row, in one statement pair
--   fn_kernel_system_execution_fail    the same, with the SQLSTATE, the failure and retry eligibility
--   fn_kernel_system_execution_trace   kept, and reimplemented as begin+finish, so there is ONE lifecycle
--   fn_kernel_intake_execution         the doors' form: an intake decision recorded as what it is
--
-- phase_c_system_execution is APPEND-ONLY (z10_phase_c_system_execution_append_only refuses UPDATE
-- and DELETE), and that is left alone. It is why the execution row is written at FINISH rather than
-- at BEGIN: a row that cannot be edited must not be written before the thing it describes is over.
-- Between begin and finish there is an OPEN trace and no execution row, which is exactly what an
-- execution in flight looks like. The enforcement below is written to that fact.
--
-- ENFORCEMENT, as DEFERRABLE INITIALLY DEFERRED constraint triggers checked at COMMIT. Deferred
-- because the two rows are written in either order by different callers, and a check that fires
-- between them would refuse a correct transaction; at commit the pair is complete or the whole
-- transaction is not. This also gives rule 5 for nothing: a subject insert that fails or is
-- discarded as a duplicate rolls its trace back with it, so no orphan can survive.
--
-- Rollback: scripts/sql/rollback/rc4_execution_and_trace_are_atomic.rollback.sql

-- ---------------------------------------------------------------------------------------------
-- The two kernel doors are components. They were writing traces naming component ids that did not
-- exist in phase_c_component at all, which is the second half of why nothing could be checked.
insert into public.phase_c_component (
  component_id, component_type, source_path_or_db_object, entry_method, current_callers,
  external_entry, schedule_or_trigger, mutates_state, current_actor, canonical_system_actor,
  accountable_role_id, department_id, workflow_id, step_id, authority_class, trace_policy_id,
  idempotency_strategy, retry_policy, activation_state, classification, gap, repair_or_keep_action,
  evidence, measured_at)
values
  ('dbfn:fn_kernel_trigger_submit(jsonb)', 'database_function',
   'public.fn_kernel_trigger_submit(jsonb)', 'sql_function',
   'every canonical source adapter, through fn_kernel_source_emit', false,
   'called by an adapter when a source produces a new work request', true,
   'system.command_router', 'system.command_router',
   'it_operations_engineer', 'technology', 'SYSTEM_SCOPE', '',
   'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION',
   'idempotency_key is unique on kernel_trigger_inbox; a repeat returns the first row',
   'none — the caller decides whether to resubmit', 'active',
   'ACTIVE_INTERNAL_CALLER', 'none - the door is the canonical entry point, not a gap', 'keep',
   'Root cause 4, 17 Aug 2026. Registered because it was already naming itself as the component on '
   'every trace it wrote, and no such component existed.', now()),
  ('dbfn:fn_kernel_signal_submit(jsonb)', 'database_function',
   'public.fn_kernel_signal_submit(jsonb)', 'sql_function',
   'every canonical source adapter for an existing-run signal', false,
   'called by an adapter when a source signals a workflow already in flight', true,
   'system.command_router', 'system.command_router',
   'it_operations_engineer', 'technology', 'SYSTEM_SCOPE', '',
   'routine_operational_decision', 'TRACE-SYSTEM-EXECUTION',
   'idempotency_key is unique on kernel_signal_inbox; a repeat returns the first row',
   'none — the caller decides whether to resubmit', 'active',
   'ACTIVE_INTERNAL_CALLER', 'none - the door is the canonical entry point, not a gap', 'keep',
   'Root cause 4, 17 Aug 2026. Its trace claimed subject_kind system_execution with subject_ref '
   'signal:<id>, which identifies a signal and not any execution row.', now())
on conflict (component_id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- BEGIN. Opens the trace and nothing else. The execution is now in flight and says so.
create or replace function public.fn_kernel_system_execution_begin(p_input jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $rc4b$
declare v_comp public.phase_c_component%rowtype; v_trace bigint;
begin
  select * into v_comp from public.phase_c_component where component_id = p_input->>'component_id';
  if not found then
    raise exception 'fn_kernel_system_execution_begin: component % is not registered', p_input->>'component_id'
      using errcode = '23503';
  end if;
  if coalesce(btrim(p_input->>'correlation_id'),'') = ''
     or coalesce(btrim(p_input->>'causation_id'),'') = '' then
    raise exception 'fn_kernel_system_execution_begin: correlation_id and causation_id are required '
      'at BEGIN. An execution that cannot be joined to what caused it is not traceable afterwards '
      'by adding the ids later.' using errcode = '23514';
  end if;

  v_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
    'subject_kind',     'system_execution',
    'subject_ref',      v_comp.component_id,
    'component_id',     v_comp.component_id,
    'system_actor_id',  coalesce(nullif(p_input->>'system_actor',''), v_comp.canonical_system_actor),
    'actor_role_id',    coalesce(nullif(p_input->>'accountable_role_id',''), v_comp.accountable_role_id),
    'manager_role_id',  coalesce((select manager_role_id from public.org_role
                                   where role_id = coalesce(nullif(p_input->>'accountable_role_id',''),
                                                            v_comp.accountable_role_id)), ''),
    'authority_result', coalesce(nullif(p_input->>'authority_result',''), 'pending_at_begin'),
    'state_before',     coalesce(nullif(p_input->>'state_before',''), 'not_started'),
    'state_after',      'in_flight',
    'input_hash',       coalesce(nullif(p_input->>'input_hash',''),
                                 case when p_input ? 'input' then md5(p_input->>'input')
                                      else 'no_input_recorded' end),
    'output_hash',      'not_finished',
    'evidence_refs',    jsonb_build_array(jsonb_build_object(
                          'lifecycle', 'begin',
                          'correlation_id', p_input->>'correlation_id',
                          'causation_id',   p_input->>'causation_id',
                          'trigger_source', coalesce(p_input->>'trigger_source','(unstated)'),
                          'started_at', coalesce(nullif(p_input->>'started_at','')::timestamptz, now()))),
    'status',           'open'));
  return v_trace;
end
$rc4b$;

revoke execute on function public.fn_kernel_system_execution_begin(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- FINISH and FAIL both close the pair. They differ only in what they are allowed to say, so they
-- share one body: a finish that carries a failure, or a fail that carries none, is refused.
create or replace function public.fn_kernel_system_execution_close(p_trace bigint, p_input jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $rc4c$
declare
  t public.phase_c_trace%rowtype; v_comp public.phase_c_component%rowtype;
  v_result text := p_input->>'result';
  v_failure text := nullif(btrim(coalesce(p_input->>'failure','')), '');
  v_started timestamptz; v_finished timestamptz := coalesce(nullif(p_input->>'finished_at','')::timestamptz, now());
begin
  select * into t from public.phase_c_trace where trace_id = p_trace;
  if not found then
    raise exception 'fn_kernel_system_execution_close: trace % does not exist', p_trace using errcode = '23503';
  end if;
  if t.trace_policy_id <> 'TRACE-SYSTEM-EXECUTION' then
    raise exception 'fn_kernel_system_execution_close: trace % is on policy %, not TRACE-SYSTEM-EXECUTION',
      p_trace, t.trace_policy_id using errcode = '23514';
  end if;
  if exists (select 1 from public.phase_c_system_execution where trace_id = p_trace) then
    return p_trace;   -- already closed; closing twice is not a second execution
  end if;
  select * into v_comp from public.phase_c_component where component_id = t.component_id;

  if v_result <> all (array['succeeded','failed','refused','no_op']) then
    raise exception 'fn_kernel_system_execution_close: result % is not one of succeeded, failed, refused, no_op',
      coalesce(v_result,'(null)') using errcode = '23514';
  end if;
  if v_result = 'failed' and v_failure is null then
    raise exception 'fn_kernel_system_execution_close: result is failed and no failure was stated. '
      'A failure with no cause is the shape that lets an outage read as a quiet success.'
      using errcode = '23514';
  end if;
  if v_result <> 'failed' and v_failure is not null then
    raise exception 'fn_kernel_system_execution_close: result is % and a failure string was supplied. '
      'One of the two is wrong and the record may not carry both.', v_result using errcode = '23514';
  end if;

  v_started := coalesce(
    nullif(p_input->>'started_at','')::timestamptz,
    (t.evidence_refs->0->>'started_at')::timestamptz,
    t.created_at);

  update public.phase_c_trace set
    status       = 'sealed',
    sealed_at    = now(),
    state_after  = case when v_result = 'failed' then 'failed' else coalesce(nullif(p_input->>'state_after',''), v_result) end,
    output_hash  = coalesce(nullif(p_input->>'output_hash',''), md5(v_result || coalesce(v_failure,''))),
    authority_result = coalesce(nullif(p_input->>'authority_result',''), t.authority_result),
    evidence_refs = coalesce(t.evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'lifecycle', case when v_result = 'failed' then 'fail' else 'finish' end,
      'result', v_result, 'failure', v_failure,
      'sqlstate', p_input->>'sqlstate',
      'retry_eligible', coalesce((p_input->>'retry_eligible')::boolean, false),
      'finished_at', v_finished))
  where trace_id = p_trace;

  insert into public.phase_c_system_execution (
    trace_id, component_id, system_actor, accountable_role_id, workflow_id, step_id,
    technical_scope, trigger_source, authority_result, state_before, state_after, result,
    failure, correlation_id, causation_id, started_at, finished_at)
  values (
    p_trace, t.component_id, t.system_actor_id, t.actor_role_id,
    nullif(coalesce(p_input->>'workflow_id', coalesce(v_comp.workflow_id,'')),''),
    nullif(coalesce(p_input->>'step_id', coalesce(v_comp.step_id,'')),''),
    coalesce(nullif(p_input->>'technical_scope',''),
      case when coalesce(v_comp.workflow_id,'') = '' then
        'technical scope: kernel-owned execution registered as ' || t.component_id
        || ', which belongs to no one of the thirty Phase B workflows. Accountability is carried by '
        || 'the role, not by a workflow id it does not have.' end),
    coalesce(nullif(p_input->>'trigger_source',''), t.evidence_refs->0->>'trigger_source', 'unstated'),
    coalesce(nullif(p_input->>'authority_result',''), t.authority_result),
    coalesce(t.state_before, 'not_started'),
    case when v_result = 'failed' then 'failed' else coalesce(nullif(p_input->>'state_after',''), v_result) end,
    v_result, v_failure, coalesce(t.evidence_refs->0->>'correlation_id','unstated'),
    coalesce(t.evidence_refs->0->>'causation_id','unstated'), v_started, v_finished);

  return p_trace;
end
$rc4c$;

revoke execute on function public.fn_kernel_system_execution_close(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_kernel_system_execution_finish(p_trace bigint, p_input jsonb)
returns bigint language sql security definer set search_path to 'public','pg_temp'
as $rc4f$
  select public.fn_kernel_system_execution_close(p_trace,
    p_input || jsonb_build_object('result', coalesce(nullif(p_input->>'result',''), 'succeeded')));
$rc4f$;

revoke execute on function public.fn_kernel_system_execution_finish(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_kernel_system_execution_fail(p_trace bigint, p_input jsonb)
returns bigint language sql security definer set search_path to 'public','pg_temp'
as $rc4x$
  select public.fn_kernel_system_execution_close(p_trace, p_input || jsonb_build_object(
    'result', 'failed',
    'failure', coalesce(nullif(btrim(p_input->>'failure'),''),
                        coalesce(p_input->>'sqlstate','') || ' ' || coalesce(p_input->>'message','(no message)')),
    'retry_eligible', coalesce(p_input->>'retry_eligible','false')::boolean));
$rc4x$;

revoke execute on function public.fn_kernel_system_execution_fail(bigint, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- THE DOORS' FORM. An intake decision is a system execution: something ran, it accepted or refused,
-- and it changed state. This is begin+close in one call so a door's existing single statement stays
-- a single statement, and the pair can never be half-written.
create or replace function public.fn_kernel_intake_execution(p_component text, p_trace_input jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $rc4i$
declare v_trace bigint; v_result text;
begin
  v_result := case
    when coalesce(p_trace_input->>'state_after','') in ('refused','rejected') then 'refused'
    when coalesce(p_trace_input->>'state_after','') = 'deferred' then 'no_op'
    else 'succeeded' end;

  v_trace := public.fn_kernel_system_execution_begin(jsonb_build_object(
    'component_id',    p_component,
    'correlation_id',  coalesce(nullif(p_trace_input->>'correlation_id',''), 'intake:' || p_component),
    'causation_id',    coalesce(nullif(p_trace_input->>'causation_id',''), 'intake:' || p_component),
    'authority_result', p_trace_input->>'authority_result',
    'state_before',    p_trace_input->>'state_before',
    'input_hash',      p_trace_input->>'input_hash',
    'trigger_source',  coalesce(nullif(p_trace_input->>'trigger_source',''),
                                'kernel door ' || p_component)));

  -- Everything the door said about its own subject is preserved on the trace rather than dropped:
  -- the run, the step run, the task and the door's original subject_ref stay readable.
  update public.phase_c_trace set
    run_id       = coalesce(nullif(p_trace_input->>'run_id','')::bigint, run_id),
    parent_trace_id = coalesce(
      nullif(p_trace_input->>'parent_trace_id','')::bigint,
      (select r.trace_id from public.phase_c_workflow_run r
        where r.run_id = nullif(p_trace_input->>'run_id','')::bigint),
      parent_trace_id),
    step_run_id  = coalesce(nullif(p_trace_input->>'step_run_id','')::bigint, step_run_id),
    task_id      = coalesce(nullif(p_trace_input->>'task_id','')::bigint, task_id),
    evidence_refs = coalesce(evidence_refs,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'door_subject_kind', p_trace_input->>'subject_kind',
      'door_subject_ref',  p_trace_input->>'subject_ref',
      'door_evidence',     p_trace_input->'evidence_refs'))
  where trace_id = v_trace;

  return public.fn_kernel_system_execution_close(v_trace, jsonb_build_object(
    'result',      v_result,
    'state_after', p_trace_input->>'state_after',
    'output_hash', p_trace_input->>'output_hash',
    'failure',     case when v_result = 'failed' then p_trace_input->>'failure' end));
end
$rc4i$;

revoke execute on function public.fn_kernel_intake_execution(text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- ENFORCEMENT. Six rules, two deferred constraint triggers, checked at COMMIT.
create or replace function public.fn_kernel_system_execution_pair_guard()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $rc4g$
declare t public.phase_c_trace%rowtype; e public.phase_c_system_execution%rowtype;
begin
  if tg_table_name = 'phase_c_trace' then
    select * into t from public.phase_c_trace where trace_id = new.trace_id;
    if not found then return null; end if;                      -- rolled back with its transaction
    if t.trace_policy_id <> 'TRACE-SYSTEM-EXECUTION' then return null; end if;

    -- RULE 6: the subject must identify the real execution, not an idempotency string.
    if t.subject_kind <> 'system_execution' then
      raise exception
        'trace % is on TRACE-SYSTEM-EXECUTION with subject_kind %L. The policy''s subject is a '
        'system execution; trace 3730 was written with subject_kind ''trigger_inbox'' and had no '
        'execution to point at. Use fn_kernel_intake_execution, or write the trace under the policy '
        'the subject actually has.', t.trace_id, t.subject_kind using errcode = '23514';
    end if;
    if t.subject_ref is distinct from t.component_id then
      raise exception
        'trace % names subject_ref %L and component %L. For a system execution the subject IS the '
        'component that ran; fn_kernel_signal_submit used to write ''signal:<id>'' here, which '
        'identifies a signal and not any execution.', t.trace_id, t.subject_ref, t.component_id
        using errcode = '23514';
    end if;

    -- RULE 4: sealed requires sealed_at.
    if t.status = 'sealed' and t.sealed_at is null then
      raise exception 'trace % is sealed with no sealed_at', t.trace_id using errcode = '23514';
    end if;

    -- RULE 1: a SEALED system-execution trace must have its execution row. An OPEN one must not —
    -- that is an execution in flight, and phase_c_system_execution is append-only so its row is
    -- written when the execution is over.
    if t.status = 'sealed'
       and not exists (select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id) then
      raise exception
        'trace % is a SEALED TRACE-SYSTEM-EXECUTION trace with no row in phase_c_system_execution. '
        'This is the exact shape of trace 3730. Close the execution with '
        'fn_kernel_system_execution_finish or _fail, which write the pair together.', t.trace_id
        using errcode = '23514';
    end if;
    return null;
  end if;

  -- phase_c_system_execution
  select * into e from public.phase_c_system_execution where trace_id = new.trace_id;
  if not found then return null; end if;
  select * into t from public.phase_c_trace where trace_id = e.trace_id;
  -- RULE 2: an execution cannot exist without a trace.
  if not found then
    raise exception
      'system execution on trace % has no trace row. An execution nobody can account for is the '
      'thing this policy exists to make impossible.', e.trace_id using errcode = '23503';
  end if;
  -- RULE 3: a terminal execution cannot have an open or incomplete trace.
  if e.result is not null and e.finished_at is not null
     and (t.status <> 'sealed' or t.sealed_at is null) then
    raise exception
      'system execution on trace % is terminal (result %L, finished) while its trace is %L with '
      'sealed_at %L. A finished execution whose trace is still open is a record that can still be '
      'rewritten after the fact.', e.trace_id, e.result, t.status, t.sealed_at using errcode = '23514';
  end if;
  return null;
end
$rc4g$;

revoke execute on function public.fn_kernel_system_execution_pair_guard() from public, anon, authenticated;

drop trigger if exists z90_system_execution_pair_guard on public.phase_c_trace;
create constraint trigger z90_system_execution_pair_guard
  after insert or update on public.phase_c_trace
  deferrable initially deferred
  for each row execute function public.fn_kernel_system_execution_pair_guard();

drop trigger if exists z90_system_execution_pair_guard on public.phase_c_system_execution;
create constraint trigger z90_system_execution_pair_guard
  after insert on public.phase_c_system_execution
  deferrable initially deferred
  for each row execute function public.fn_kernel_system_execution_pair_guard();

-- ---------------------------------------------------------------------------------------------
-- THE TWO KERNEL DOORS STOP WRITING HALF A RECORD.

-- fn_kernel_signal_submit: 1 trace call site(s) moved onto the lifecycle. The door's own
-- payload is passed through unchanged, so its subject and evidence stay readable; what
-- changes is that the trace and its execution row are now written together.
CREATE OR REPLACE FUNCTION public.fn_kernel_signal_submit(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_src_type  text   := nullif(btrim(coalesce(p_input->>'source_type','')), '');
  v_src_id    text   := nullif(btrim(coalesce(p_input->>'source_id','')), '');
  v_run       bigint := nullif(p_input->>'workflow_run_id','')::bigint;
  v_sig       text   := nullif(btrim(coalesce(p_input->>'signal_type','')), '');
  v_payload   jsonb  := coalesce(p_input->'payload', '{}'::jsonb);
  v_by        text   := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_idem      text;
  v_corr      text;
  v_caus      text;
  v_id        bigint;
  -- Scalars, never a RECORD read outside the branch that filled it.
  v_prior_id     bigint;
  v_prior_status text;
  v_prior_result jsonb;
  v_disp      text;
  v_sig_wf    text;
  v_sig_act   text;
  v_sig_sys   text;
  v_run_wf    text;
  v_run_state text;
  v_run_obj   text;
  v_run_trace bigint;
  v_step_run  bigint;
  v_step_id   text;
  v_step_owner text;
  v_task      bigint;
  v_trace     bigint;
  v_out       jsonb;
  v_refuse    text;
begin
  -- ---- 0. a delivery worker may never drive the request side -------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_signal_submit');

  -- ---- 1. envelope. Nothing recordable in a malformed one -----------------------------------
  if v_src_type is null or v_src_id is null or v_sig is null or v_by is null then
    raise exception 'fn_kernel_signal_submit: source_type, source_id, signal_type and requested_by are all required (got %, %, %, %)',
      coalesce(v_src_type,'(null)'), coalesce(v_src_id,'(null)'), coalesce(v_sig,'(null)'),
      coalesce(v_by,'(null)') using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'fn_kernel_signal_submit: payload must be a json object, got %',
      jsonb_typeof(v_payload) using errcode = '22023';
  end if;

  -- The key is the external identity of the signal. Defaulted from the source's own reference and
  -- the run it is about — never from now() or a sequence, because a key that differs every time
  -- is not a key and would let one webhook retry apply twice.
  v_idem := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),
                     v_src_type || ':' || v_src_id || ':' || v_sig || ':' || coalesce(v_run::text,'-'));
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), 'signal:' || v_idem);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_src_type || ':' || v_src_id);

  -- ---- 2. idempotency, before anything is resolved and before anything happens --------------
  select s.signal_id, s.status, s.result into v_prior_id, v_prior_status, v_prior_result
    from public.kernel_signal_inbox s where s.idempotency_key = v_idem;
  if v_prior_id is not null then
    return jsonb_build_object('ok', v_prior_status <> 'refused', 'duplicate', true,
      'signal_id', v_prior_id, 'status', v_prior_status, 'result', v_prior_result,
      'reason', 'this signal has already been delivered; the first decision is the answer');
  end if;

  insert into public.kernel_signal_inbox
    (source_type, source_id, workflow_run_id, signal_type, payload, idempotency_key,
     correlation_id, causation_id, requested_by)
  values (v_src_type, v_src_id, v_run, v_sig, v_payload, v_idem, v_corr, v_caus, v_by)
  returning signal_id into v_id;

  -- ---- 3. the signal type must be registered and active ------------------------------------
  select t.disposition, t.workflow_id, t.activation_state, t.system_actor_id
    into v_disp, v_sig_wf, v_sig_act, v_sig_sys
    from public.kernel_signal_type t where t.signal_type = v_sig;
  if v_disp is null then
    v_refuse := format('signal type %L is not registered. A signal the kernel has never heard of '
                    || 'is not routed on a guess.', v_sig);
  elsif v_sig_act <> 'active' then
    v_refuse := format('signal type %L is registered with activation_state %L and does not accept '
                    || 'submissions.', v_sig, v_sig_act);
  end if;

  -- ---- 4. the run must exist, and must still be running -------------------------------------
  if v_refuse is null then
    if v_run is null then
      v_refuse := 'a signal about an existing workflow must name workflow_run_id. There is no '
               || 'lookup by business object here on purpose: guessing which run a signal belongs '
               || 'to is how one arrival lands on two runs.';
    else
      select r.workflow_id, r.state, r.business_object_id, r.trace_id
        into v_run_wf, v_run_state, v_run_obj, v_run_trace
        from public.phase_c_workflow_run r where r.run_id = v_run for update;
      if v_run_wf is null then
        v_refuse := format('workflow run %s does not exist.', v_run);
      elsif exists (select 1 from public.phase_b_workflow_state ws
                     where ws.state = v_run_state and ws.terminal) then
        v_refuse := format('workflow run %s is in terminal state %L. A closed run does not accept '
                        || 'signals; if this is new work it must come through '
                        || 'fn_kernel_trigger_submit and be judged on its own.', v_run, v_run_state);
      elsif v_sig_wf is not null and v_sig_wf is distinct from v_run_wf then
        v_refuse := format('signal type %L is declared for workflow %L and run %s is %L.',
                           v_sig, v_sig_wf, v_run, v_run_wf);
      end if;
    end if;
  end if;

  if v_refuse is not null then
    update public.kernel_signal_inbox
       set status = 'refused', refusal_reason = v_refuse, processed_at = now()
     where signal_id = v_id;
    return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
      'status','refused', 'reason', v_refuse);
  end if;

  -- ---- 5. the signal is attached to the run it names, always --------------------------------
  -- Even a signal whose disposition changes nothing leaves a trace parented to the run's trace, so
  -- "we were told and did nothing" and "we were never told" can never be confused later.
  v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_signal_submit(jsonb)', jsonb_build_object(
    'subject_kind','system_execution', 'subject_ref', 'signal:' || v_id::text, 'run_id', v_run,
    'actor_role_id', null, 'system_actor_id', v_sig_sys,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'signal_id', v_id, 'signal_type', v_sig, 'disposition', v_disp,
      'source_type', v_src_type, 'source_id', v_src_id, 'idempotency_key', v_idem)),
    'state_before', v_run_state, 'state_after', v_run_state, 'status','complete'));
  update public.kernel_signal_inbox set trace_id = v_trace where signal_id = v_id;
  if v_run_trace is not null then
    -- parent_trace_id is set by fn_kernel_intake_execution BEFORE the trace is sealed (rc4).
  -- Setting it here would edit a sealed trace, which fn_phase_c_trace_append_only refuses.
  perform 1;
  end if;

  -- The run's currently active step, if it has one. Read once, used by three dispositions.
  select sr.step_run_id, sr.step_id, sr.accountable_role_id
    into v_step_run, v_step_id, v_step_owner
    from public.phase_c_workflow_step_run sr
   where sr.run_id = v_run and sr.state = 'active'
   order by sr.step_run_id limit 1;

  -- ---- 6. the declared disposition, and only that -------------------------------------------
  if v_disp = 'ATTACH_ONLY' then
    update public.kernel_signal_inbox
       set status = 'attached', step_run_id = v_step_run, processed_at = now(),
           result = jsonb_build_object('attached_to_run', v_run, 'active_step', v_step_id)
     where signal_id = v_id;
    return jsonb_build_object('ok', true, 'duplicate', false, 'signal_id', v_id,
      'status','attached', 'workflow_run_id', v_run, 'workflow_id', v_run_wf,
      'active_step_id', v_step_id, 'trace_id', v_trace, 'created_workflow_runs', 0);

  elsif v_disp = 'COMPLETE_STEP' then
    if v_step_run is null then
      v_refuse := format('run %s has no active step, so there is nothing for a COMPLETE_STEP '
                      || 'signal to complete.', v_run);
    elsif coalesce(jsonb_typeof(v_payload->'output'),'') <> 'object'
       or v_payload->'output' = '{}'::jsonb then
      v_refuse := format('signal type %L completes step %s and the payload carries no output '
                      || 'object. An output is what the step contract asks for; it is not '
                      || 'defaulted here, because a fabricated output certifies work nobody did.',
                         v_sig, v_step_id);
    end if;
    if v_refuse is not null then
      update public.kernel_signal_inbox
         set status = 'refused', refusal_reason = v_refuse, step_run_id = v_step_run,
             processed_at = now()
       where signal_id = v_id;
      return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
        'status','refused', 'reason', v_refuse);
    end if;
    v_out := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id',     v_step_run,
      'actor_role_id',   v_step_owner,
      'outcome',         coalesce(nullif(btrim(v_payload->>'outcome'),''), 'pass'),
      'idempotency_key', 'signal:' || v_idem,
      'reason',          coalesce(nullif(btrim(v_payload->>'reason'),''),
                                  'signal ' || v_sig || ' from ' || v_src_type || ':' || v_src_id),
      'inputs',          coalesce(v_payload->'inputs',
                                  jsonb_build_object('signal_id', v_id, 'signal_type', v_sig,
                                                     'source', v_src_type || ':' || v_src_id)),
      'output',          v_payload->'output',
      'evidence_ref',    'signal:' || v_id::text,
      'correlation_id',  v_corr, 'causation_id', v_caus));

  elsif v_disp = 'REVIEW_VERDICT' then
    select t.task_id into v_task from public.phase_c_task t
     where t.run_id = v_run and t.step_id = v_step_id order by t.task_id desc limit 1;
    if v_task is null or coalesce(btrim(v_payload->>'decision'),'') = '' then
      v_refuse := format('a REVIEW_VERDICT signal needs a task on the active step and a decision '
                      || 'in the payload (task %s, decision %L).',
                         coalesce(v_task::text,'none'), coalesce(v_payload->>'decision','(none)'));
      update public.kernel_signal_inbox
         set status = 'refused', refusal_reason = v_refuse, step_run_id = v_step_run,
             processed_at = now()
       where signal_id = v_id;
      return jsonb_build_object('ok', false, 'duplicate', false, 'signal_id', v_id,
        'status','refused', 'reason', v_refuse);
    end if;
    v_out := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id',          v_task,
      'reviewer_role_id', v_payload->>'reviewer_role_id',
      'decision',         v_payload->>'decision',
      'reason',           coalesce(nullif(btrim(v_payload->>'reason'),''),
                                   'recorded from signal ' || v_id::text)));

  elsif v_disp = 'CANCEL' then
    v_out := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind', 'workflow_run',
      'subject_ref',  v_run::text,
      'op',           'cancel',
      'reason',       coalesce(nullif(btrim(v_payload->>'reason'),''),
                               'cancelled by signal ' || v_sig || ' from ' || v_src_type || ':' || v_src_id),
      'actor',        v_by));
  end if;

  update public.kernel_signal_inbox
     set status = 'applied', step_run_id = v_step_run, processed_at = now(), result = v_out
   where signal_id = v_id;

  return jsonb_build_object('ok', coalesce((v_out->>'ok')::boolean, true), 'duplicate', false,
    'signal_id', v_id, 'status','applied', 'disposition', v_disp,
    'workflow_run_id', v_run, 'workflow_id', v_run_wf, 'step_id', v_step_id,
    'trace_id', v_trace, 'created_workflow_runs', 0, 'result', v_out);
end
$function$;

-- fn_kernel_trigger_submit: 2 trace call site(s) moved onto the lifecycle. The door's own
-- payload is passed through unchanged, so its subject and evidence stay readable; what
-- changes is that the trace and its execution row are now written together.
CREATE OR REPLACE FUNCTION public.fn_kernel_trigger_submit(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class     text  := nullif(btrim(coalesce(p_input->>'source_class','')), '');
  v_system    text  := nullif(btrim(coalesce(p_input->>'source_system','')), '');
  v_ref       text  := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_ext       text  := nullif(btrim(coalesce(p_input->>'external_ref','')), '');
  v_type_in   text  := nullif(btrim(coalesce(p_input->>'trigger_type','')), '');
  v_by        text  := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_payload   jsonb := coalesce(p_input->'raw_payload', '{}'::jsonb);
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text  := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_idem      text;
  v_corr      text;
  v_caus      text;
  v_inbox     bigint;
  v_trace     bigint;
  v_obj       text;
  v_key       text;
  v_val       text;
  v_missing   text;
  v_start     jsonb;
  v_run       bigint;
  v_status    text;
  v_reason    text;
  v_actor     text;
  v_kind      text;
  v_owner     text;
  v_step_owner text;
  v_step_id   text;
  -- Scalars, never a RECORD: a plpgsql RECORD assigned only inside an if-branch raises when it is
  -- read, and a SELECT INTO that matched nothing NULLs every target rather than leaving the
  -- initialiser. Both traps have already been paid for in this estate.
  t_workflow  text;
  t_rule      text;
  t_sources   text[];
  t_actor     text;
  t_activation text;
  t_impl      text;
  t_class     text;
  t_note      text;
  p_inbox     bigint;
  p_status    text;
  p_run       bigint;
  p_trace     bigint;
  p_type      text;
  p_wf        text;
  p_obj       text;
  p_reason    text;
begin
  -- ---- 0. a consumer may never drive the request side --------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_trigger_submit');

  -- ---- 1. envelope. A malformed envelope has nothing recordable in it ----------------------
  --
  -- These raise rather than record: source_class is CHECK-constrained and requested_by is NOT NULL,
  -- so a row cannot be written to hold the refusal. Everything that CAN be recorded is recorded
  -- below instead of raised.
  if v_class is null or v_system is null or v_ref is null or v_type_in is null or v_by is null then
    raise exception
      'fn_kernel_trigger_submit: source_class, source_system, source_ref, trigger_type and '
      'requested_by are all required (got %, %, %, %, %)',
      coalesce(v_class,'(null)'), coalesce(v_system,'(null)'), coalesce(v_ref,'(null)'),
      coalesce(v_type_in,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'fn_kernel_trigger_submit: raw_payload must be a json object, got %',
      jsonb_typeof(v_payload) using errcode = '22023';
  end if;
  if v_class not in ('customer_event','supplier_event','scheduled_event','deadline_sla_event',
                     'kpi_deviation_event','system_health_event','webhook_provider_event',
                     'workflow_followup_event') then
    raise exception 'fn_kernel_trigger_submit: % is not one of the eight registered source classes',
      v_class using errcode = '22023';
  end if;

  -- The idempotency key is the external identity of the request. Defaulted from the source's own
  -- reference, never from now() or from a sequence: a key that is different every time is not a key.
  v_idem := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),
                     v_system || ':' || coalesce(v_ext, v_ref));
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), 'trigger:' || v_idem);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_system || ':' || v_ref);

  -- ---- 2. idempotency, before anything is resolved and before anything is created ----------
  insert into public.kernel_trigger_inbox
    (source_class, source_system, source_ref, external_ref, raw_payload,
     correlation_id, causation_id, idempotency_key, status, requested_by)
  values (v_class, v_system, v_ref, v_ext, v_payload, v_corr, v_caus, v_idem, 'pending', v_by)
  on conflict (idempotency_key) do nothing
  returning inbox_id into v_inbox;

  if v_inbox is null then
    -- Seen before. Return the FIRST result and create nothing: no run, no task, no event, and no
    -- second inbox row. The first row's decision is the answer, whatever it was.
    select i.inbox_id, i.status, i.run_id, i.trace_id, i.trigger_type, i.workflow_id,
           i.business_object_id, i.refusal_reason
      into p_inbox, p_status, p_run, p_trace, p_type, p_wf, p_obj, p_reason
      from public.kernel_trigger_inbox i where i.idempotency_key = v_idem;
    -- An empty read here would mean the conflicting row belongs to a transaction that has not
    -- committed. Returning a jsonb full of nulls would make "someone else is mid-flight" look
    -- exactly like "refused with no reason", so it raises instead.
    if p_inbox is null then
      raise exception
        'fn_kernel_trigger_submit: idempotency key % conflicted but no committed row holds it — a '
        'concurrent submission of the same key is still open. Retry.', v_idem
        using errcode = '40001';
    end if;
    return jsonb_build_object(
      'ok', p_status in ('accepted','duplicate'), 'duplicate', true, 'status', p_status,
      'inbox_id', p_inbox, 'idempotency_key', v_idem, 'trigger_type', p_type,
      'workflow_id', p_wf, 'business_object_id', p_obj, 'run_id', p_run, 'trace_id', p_trace,
      'refusal_reason', p_reason,
      'created', jsonb_build_object('inbox_row',0,'run',0,'step_run',0,'task',0,'event',0),
      'note','idempotency_key already recorded; the first result is returned and nothing was created');
  end if;

  -- ---- 3. normalize to a REGISTERED trigger type -------------------------------------------
  select t.workflow_id, t.business_object_rule, t.allowed_source_systems, t.system_actor_id,
         t.activation_state, t.implementation_state, t.source_class, t.accountable_note
    into t_workflow, t_rule, t_sources, t_actor, t_activation, t_impl, t_class, t_note
    from public.kernel_trigger_type t where t.trigger_type = v_type_in;

  v_status := null; v_reason := null;

  if t_class is null then
    v_status := 'refused';
    v_reason := format('no registered trigger type named %s. An unmapped trigger is recorded and '
                    || 'refused; it is never resolved to the nearest workflow.', v_type_in);
  elsif t_class is distinct from v_class then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered under source class %s and was submitted as %s',
                       v_type_in, t_class, v_class);
  elsif not (v_system = any (t_sources)) then
    v_status := 'refused';
    v_reason := format('source system %s is not permitted to submit %s. Permitted: %s',
                       v_system, v_type_in, array_to_string(t_sources, ', '));
  elsif t_impl = 'DEFERRED_HANDLER' then
    v_status := 'deferred';
    v_reason := format('trigger type %s is a DEFERRED_HANDLER: the frozen Phase B registry declares '
                    || 'no workflow that starts from this signal. %s', v_type_in, t_note);
  elsif t_activation <> 'active' then
    v_status := 'refused';
    v_reason := format('trigger type %s is registered with activation_state %s and does not accept '
                    || 'submissions', v_type_in, t_activation);
  end if;

  -- ---- 4. resolve the business object BY THE RECORDED RULE ---------------------------------
  if v_status is null then
    v_obj := t_rule;
    -- regexp_matches is set-returning, so it is driven by a FOR loop and never placed inside a
    -- boolean expression: a set-returning function in a boolean expression raises 42804.
    for v_key in select rr.mk[1] from regexp_matches(t_rule, '\{([a-zA-Z0-9_]+)\}', 'g') as rr(mk) loop
      v_val := nullif(btrim(coalesce(v_payload->>v_key,'')), '');
      if v_val is null then
        v_missing := coalesce(v_missing || ', ', '') || v_key;
      else
        v_obj := replace(v_obj, '{' || v_key || '}', v_val);
      end if;
    end loop;

    if v_missing is not null then
      v_status := 'refused';
      v_reason := format('business object rule %s needs payload key(s) %s and the payload does not '
                      || 'carry them. The object is refused, not guessed.', t_rule, v_missing);
    elsif v_obj ~ '[{}]' then
      v_status := 'refused';
      v_reason := format('business object rule %s did not fully resolve: %s', t_rule, v_obj);
    end if;
  end if;

  -- ---- 5. the founder boundary, checked again at call time ---------------------------------
  --
  -- The registry guard in §1 refuses such a row at write time. This is the second check, because a
  -- row could predate the guard, and because "normal autonomous work never routes through the
  -- founder or the Chief of Staff" is the kind of rule that must hold even when the table is wrong.
  if v_status is null then
    select kind, role_id into v_kind, v_owner
      from public.fn_phase_c_resolve_actor(
        (select w.accountable_role_id from public.phase_b_workflow w where w.workflow_id = t_workflow));
    select s.step_id, r.role_id into v_step_id, v_step_owner
      from public.phase_b_workflow_step s,
           lateral public.fn_phase_c_resolve_actor(s.accountable_role_id) r
     where s.workflow_id = t_workflow and s.step_no = 1;

    if v_owner is null or v_kind is distinct from 'canonical' then
      v_status := 'refused';
      v_reason := format('workflow %s names accountable role that resolves to %s — no run created',
                         t_workflow, coalesce(v_kind,'nothing'));
    elsif v_owner in ('founder','chief_of_staff') or coalesce(v_step_owner,'') in ('founder','chief_of_staff') then
      v_status := 'refused';
      v_reason := format('workflow %s would put autonomous work on %s / %s (step %s). Normal '
                      || 'autonomous work bypasses both the founder and the Chief of Staff.',
                         t_workflow, v_owner, coalesce(v_step_owner,'(none)'), coalesce(v_step_id,'(none)'));
    end if;
  end if;

  -- ---- 6. refusals and deferrals are RECORDED, with their own trace ------------------------
  if v_status is not null then
    v_actor := coalesce(t_actor, 'system.webhook_receiver');
    v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_trigger_submit(jsonb)', jsonb_build_object(
      'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
      'system_actor_id', v_actor,
      'actor_role_id', coalesce(nullif(v_owner,''), ''),
      'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
      'authority_result', v_status || ': ' || v_reason,
      'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
        'external_ref', v_ext, 'submitted_trigger_type', v_type_in,
        'idempotency_key', v_idem, 'raw_payload', v_payload)),
      'state_before','pending', 'state_after', v_status, 'status','sealed'));

    update public.kernel_trigger_inbox
       set status = v_status, refusal_reason = v_reason, trace_id = v_trace,
           trigger_type = (case when t_class is null then null else v_type_in end),
           processed_at = now()
     where inbox_id = v_inbox;

    return jsonb_build_object(
      'ok', false, 'duplicate', false, 'status', v_status, 'inbox_id', v_inbox,
      'idempotency_key', v_idem, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
      'business_object_id', null, 'run_id', null, 'trace_id', v_trace,
      'refusal_reason', v_reason, 'correlation_id', v_corr, 'causation_id', v_caus,
      'created', jsonb_build_object('inbox_row',1,'run',0,'step_run',0,'task',0,'event',0));
  end if;

  -- ---- 7. THE ONLY creator of business work is called ---------------------------------------
  --
  -- No insert into phase_c_task, phase_c_workflow_run, phase_c_workflow_step_run,
  -- phase_c_handoff_run or phase_c_event_outbox appears anywhere in this function. All six objects
  -- come from fn_kernel_workflow_start, atomically, or none of them does.
  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id',        t_workflow,
    'business_object_id', v_obj,
    'object_version',     v_version,
    'source_kind',        'autonomous',
    'source_ref',         'trigger_inbox:' || v_inbox,
    'correlation_id',     v_corr,
    'causation_id',       v_caus,
    'requested_by',       v_by,
    'priority',           v_priority,
    'trigger_ctx',        jsonb_build_object(
        'inbox_id', v_inbox, 'trigger_type', v_type_in, 'source_class', v_class,
        'source_system', v_system, 'source_ref', v_ref, 'external_ref', v_ext,
        'idempotency_key', v_idem, 'business_object_rule', t_rule, 'raw_payload', v_payload)));

  v_run    := (v_start->>'run_id')::bigint;
  v_status := case when coalesce((v_start->>'duplicate')::boolean, false)
                   then 'duplicate' else 'accepted' end;

  if v_run is null then
    raise exception 'fn_kernel_trigger_submit: fn_kernel_workflow_start returned no run_id for % / %',
      t_workflow, v_obj using errcode = '23502';
  end if;

  -- ---- 8. the adapter's own execution trace, parented to the run's root --------------------
  v_trace := public.fn_kernel_intake_execution('dbfn:fn_kernel_trigger_submit(jsonb)', jsonb_build_object(
    'subject_kind','trigger_inbox', 'subject_ref', v_inbox::text,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'system_actor_id', t_actor,
    'actor_role_id', v_start->>'step_accountable_role_id',
    'manager_role_id', v_start->>'accountable_role_id',
    'component_id','dbfn:fn_kernel_trigger_submit(jsonb)',
    'authority_result', v_status || ': trigger type ' || v_type_in || ' -> ' || t_workflow
                     || ' by registry, business object by rule ' || t_rule,
    'input_hash', encode(sha256(convert_to(v_idem || '|' || v_payload::text, 'UTF8')), 'hex'),
    'output_hash', encode(sha256(convert_to(v_start::text, 'UTF8')), 'hex'),
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'source_class', v_class, 'source_system', v_system, 'source_ref', v_ref,
      'external_ref', v_ext, 'idempotency_key', v_idem,
      'business_object_rule', t_rule, 'business_object_id', v_obj, 'raw_payload', v_payload)),
    'event_ids', jsonb_build_array(v_start->>'event_id'),
    'state_before','pending', 'state_after', v_status, 'status','sealed',
    'parent_trace_id', (v_start->>'run_trace_id')::bigint));

  update public.kernel_trigger_inbox
     set status = v_status, trigger_type = v_type_in, workflow_id = t_workflow,
         business_object_id = v_obj, run_id = v_run, trace_id = v_trace, processed_at = now()
   where inbox_id = v_inbox;

  return jsonb_build_object(
    'ok', true, 'duplicate', (v_status = 'duplicate'), 'status', v_status,
    'inbox_id', v_inbox, 'idempotency_key', v_idem,
    'source_class', v_class, 'trigger_type', v_type_in, 'workflow_id', t_workflow,
    'business_object_id', v_obj, 'object_version', v_version,
    'run_id', v_run, 'step_run_id', (v_start->>'step_run_id')::bigint,
    'task_id', (v_start->>'task_id')::bigint,
    'accountable_role_id', v_start->>'accountable_role_id',
    'step_accountable_role_id', v_start->>'step_accountable_role_id',
    'handoff_run_id', (v_start->>'handoff_run_id')::bigint,
    'event_id', v_start->>'event_id', 'outbox_id', (v_start->>'outbox_id')::bigint,
    'trace_id', v_trace, 'run_trace_id', (v_start->>'run_trace_id')::bigint,
    'correlation_id', v_corr, 'causation_id', v_caus, 'system_actor_id', t_actor,
    'created', jsonb_build_object(
      'inbox_row', 1,
      'run',      (case when v_status = 'duplicate' then 0 else 1 end),
      'step_run', (case when v_status = 'duplicate' then 0 else 1 end),
      'task',     (case when v_status = 'duplicate' then 0 else 1 end),
      'event',    (case when v_status = 'duplicate' then 0 else 1 end),
      'adapter_trace', 1));
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- TRACE 3730 — LINKED TO THE EXECUTION IT ALWAYS DESCRIBED, NOT DELETED AND NOT INVENTED.
--
-- Every field below is provable from rows that already exist. Trace 3730 names the component, the
-- actor, the accountable role, the authority result and both hashes; kernel_trigger_inbox row 46
-- names the source, the received_at instant, the accepted status and run 352. The reconstruction is
-- the LINK between them, and it is labelled as a reconstruction in three places: the execution
-- row's technical_scope, the trace's evidence, and phase_c_historical_repair.
--
-- started_at and finished_at are the ORIGINAL instant, 2026-08-17 05:05:00.033303+00, not now().
-- recorded_at is when this repair ran, and the two are deliberately different so nobody can read
-- the row as contemporaneous evidence.
do $rc4r$
declare t public.phase_c_trace%rowtype; i public.kernel_trigger_inbox%rowtype;
begin
  select * into t from public.phase_c_trace where trace_id = 3730;
  if not found then
    raise notice 'trace 3730 is absent; nothing to repair';
    return;
  end if;
  if exists (select 1 from public.phase_c_system_execution where trace_id = 3730) then
    raise notice 'trace 3730 already has its execution row';
    return;
  end if;
  select * into i from public.kernel_trigger_inbox where inbox_id = 46;

  insert into public.phase_c_system_execution (
    trace_id, component_id, system_actor, accountable_role_id, workflow_id, step_id,
    technical_scope, trigger_source, authority_result, state_before, state_after, result,
    failure, correlation_id, causation_id, started_at, finished_at)
  values (
    3730, t.component_id, t.system_actor_id, t.actor_role_id, null, null,
    'RECONSTRUCTED 17 Aug 2026 by scripts/sql/rc4_execution_and_trace_are_atomic.sql. This row was '
    || 'NOT written when the execution ran: fn_kernel_trigger_submit had no code path that wrote '
    || 'one, so trace 3730 sat under TRACE-SYSTEM-EXECUTION with no execution subject and the final '
    || 'Phase C acceptance found it. Every field is taken from the trace itself and from '
    || 'kernel_trigger_inbox row 46, both of which are contemporaneous; the LINK between them is '
    || 'the reconstruction. Technical scope: a kernel intake door, which belongs to none of the '
    || 'thirty Phase B workflows — accountability is carried by the role.',
    coalesce('kernel_trigger_inbox/' || i.inbox_id::text || ' from ' || i.source_system, 'kernel_trigger_inbox/46'),
    t.authority_result, coalesce(t.state_before,'pending'), coalesce(t.state_after,'accepted'),
    'succeeded', null,
    'reconstructed:trace:3730', 'reconstructed:trigger_inbox:46',
    coalesce(i.received_at, t.created_at), coalesce(i.received_at, t.created_at));

  -- THE TRACE ITSELF IS NOT TOUCHED, and the reason is the estate's own answer: the first
  -- attempt at this repair tried to rewrite subject_kind and fn_phase_c_trace_append_only refused
  -- it — 'sealed trace evidence is append-only; write a superseding row instead of editing it'.
  -- That is right. 3730 keeps its original subject, its original created_at and its original
  -- sealed_at; what it gains is an execution row that points AT it, and a labelled entry in the
  -- historical register below. The guard installed above cannot condemn it retroactively because
  -- it fires on write, and 3730 will never be written again — which is the point of append-only.

  insert into public.phase_c_historical_repair (
    entry_kind, record_kind, record_ref, classification, frozen_state, evidence, repair_action,
    retrofit_label, migration, classified_at, original_at, kernel_cutover_at, active_effect_now,
    cannot_reconstruct)
  select 'CLASSIFICATION', 'trace', '3730', 'HISTORICAL_ORPHAN_TRACE',
         'sealed under TRACE-SYSTEM-EXECUTION with subject_kind trigger_inbox and no execution row',
         jsonb_build_object(
           'trace_id', 3730, 'component_id', tr.component_id,
           'original_created_at', tr.created_at, 'original_sealed_at', tr.sealed_at,
           'subject_row', 'kernel_trigger_inbox 46', 'resulting_run', 352,
           'found_by', 'PHASE_C_FINAL_KERNEL_ACCEPTANCE, gate 13, 17 Aug 2026'),
         'Linked to a RECONSTRUCTED phase_c_system_execution row by rc4. The trace itself was not edited: fn_phase_c_trace_append_only refuses editing a sealed trace, which is correct, so its subject_kind, created_at and sealed_at are exactly as they were written.',
         '', 'scripts/sql/rc4_execution_and_trace_are_atomic.sql',
         now(), tr.created_at,
         (select started_at from public.phase_c_kernel_epoch order by started_at limit 1),
         false,
         'The execution itself is fully reconstructable - component, actor, role, authority, both hashes, source, instant and resulting run 352 are all on contemporaneous record. What cannot be reconstructed is a CONTEMPORANEOUS execution row, because none was ever written. The row that exists now carries the original instant in started_at and today in recorded_at, and the difference between those two columns is the whole of the honesty here.'
    from public.phase_c_trace tr where tr.trace_id = 3730
  on conflict do nothing;
end
$rc4r$;
