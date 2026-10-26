-- ROLLBACK for kernel_k6_trace_ledger.sql
--
-- Restores every routine and trigger K6 changed to the definition it had on 17 Aug 2026, and drops
-- everything K6 created.
--
-- IT DOES NOT UNDO THE DATA REPAIRS, and that is deliberate:
--   * the 3 sealed_at stamps — removing them puts three rows back into the state where they
--     present as sealed evidence and are silently rewritable;
--   * the 3 task_id reverse links — removing them re-breaks the link between a task and the trace
--     that task itself names;
--   * the 7 orphan annotations — removing them deletes the only surviving explanation of why those
--     rows exist;
--   * the 3 reconstructed step traces — removing them returns three step runs to trace_id NULL,
--     which is the exact violation of TRACE-STEP that K6 was written to end.
-- Every one of those rows carries an evidence_ref keyed 'k6_backfill' saying what was written, from
-- what source, and that it is a backfill rather than a contemporaneous observation. If any of them
-- is wrong it is visible by name and can be superseded deliberately, as its own migration. A
-- rollback that destroys evidence is not a rollback.
--
-- ORDER MATTERS. phase_c_trace_sealed_ck must be dropped BEFORE fn_phase_c_trace_write is restored:
-- the pre-K6 writer inserts the caller's status and never stamps sealed_at, so with the constraint
-- still in place every caller that asks for a sealed trace — fn_kernel_cancel and
-- fn_phase_c_step_advance both do — would start failing on its next call.

begin;

-- ---- 1. the commit-time assertions --------------------------------------------------------
drop trigger if exists z95_phase_c_task_trace_committed on public.phase_c_task;
drop trigger if exists z95_phase_c_step_run_trace_committed on public.phase_c_workflow_step_run;
drop function if exists public.fn_phase_c_task_trace_committed();
drop function if exists public.fn_phase_c_step_run_trace_committed();

-- ---- 2. the sealed CHECK, before the writer that would violate it --------------------------
alter table public.phase_c_trace drop constraint if exists phase_c_trace_sealed_ck;

-- ---- 3. phase_c_workflow_step_run goes back to having no triggers at all -------------------
drop trigger if exists a00_phase_c_step_run_trace_guard on public.phase_c_workflow_step_run;
drop trigger if exists z90_phase_c_step_run_trace_subject on public.phase_c_workflow_step_run;
drop function if exists public.fn_phase_c_step_run_trace_guard();
drop function if exists public.fn_phase_c_step_run_trace_subject();

-- ---- 4. founder_command: back to BEFORE UPDATE only ----------------------------------------
create or replace function public.fn_founder_command_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.phase_c_trace%rowtype;
begin
  if new.state is not distinct from old.state then return new; end if;
  if new.state = 'received' then return new; end if;
  if old.state = 'received' and new.state = 'interpreting' and new.trace_id is null then
    return new;
  end if;
  if new.trace_id is null then
    raise exception 'founder_command %: cannot leave % without a root trace', new.command_id, old.state
      using errcode = '23514';
  end if;
  select * into t from public.phase_c_trace where trace_id = new.trace_id;
  if not found then
    raise exception 'founder_command %: root trace % does not exist', new.command_id, new.trace_id
      using errcode = '23503';
  end if;
  perform public.fn_phase_c_trace_advance(
    new.trace_id, new.state,
    new.state in ('completed','failed','cancelled','refused','superseded'),
    jsonb_build_object('evidence_refs', jsonb_build_array(
      jsonb_build_object('command_transition', old.state || ' -> ' || new.state, 'at', now()))));
  select * into t from public.phase_c_trace where trace_id = new.trace_id;
  if t.state_after is distinct from new.state then
    raise exception 'founder_command %: state % but root trace % still says %',
      new.command_id, new.state, new.trace_id, t.state_after using errcode = '23514';
  end if;
  return new;
end $fn$;

drop trigger if exists a00_founder_command_trace_guard on public.founder_command;
create trigger a00_founder_command_trace_guard
  before update on public.founder_command
  for each row execute function public.fn_founder_command_trace_guard();

-- ---- 5. phase_c_task: the BEFORE INSERT trace writer comes back ----------------------------
-- This is the shape that produced the seven orphan traces. It is restored exactly, because a
-- rollback that half-restores is worse than either state.
create or replace function public.fn_phase_c_task_trace_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_parent bigint; v_trace bigint;
begin
  if tg_op = 'INSERT' then
    if new.trace_id is null then
      select c.trace_id into v_parent from public.founder_command c where c.command_id = new.command_id;
      if v_parent is null then
        select r.trace_id into v_parent from public.phase_c_workflow_run r where r.run_id = new.run_id;
      end if;
      v_trace := public.fn_phase_c_trace_write('TRACE-TASK', jsonb_build_object(
        'subject_kind','task', 'subject_ref', coalesce(new.idempotency_key, ''),
        'command_id', new.command_id, 'run_id', new.run_id,
        'actor_role_id', new.accountable_role_id, 'manager_role_id', new.manager_role_id,
        'system_actor_id', case when new.command_id is not null
                                then 'system.command_router' else 'system.workflow_engine' end,
        'authority_result', coalesce(new.authority_class,''),
        'reviewer_role_id', coalesce(new.reviewer_role_id,''),
        'input_hash', encode(sha256(convert_to(coalesce(new.objective,''), 'UTF8')), 'hex'),
        'state_before','', 'state_after', coalesce(new.state,'queued'), 'status','open'));
      if v_parent is not null then
        update public.phase_c_trace set parent_trace_id = v_parent where trace_id = v_trace;
      end if;
      new.trace_id := v_trace;
    end if;
    return new;
  end if;

  if new.state in ('assigned','accepted','in_progress','review_required','revision_required',
                   'completed','failed','cancelled','superseded','blocked')
     and new.trace_id is null then
    raise exception 'phase_c_task %: state % requires a trace and trace_id is null',
      new.task_id, new.state using errcode = '23514';
  end if;
  if new.state is distinct from old.state and new.trace_id is not null then
    perform public.fn_phase_c_trace_advance(
      new.trace_id, new.state,
      new.state in ('completed','failed','cancelled','superseded'),
      jsonb_build_object('evidence_refs', jsonb_build_array(
        jsonb_build_object('transition', old.state || ' -> ' || new.state, 'at', now()))));
  end if;
  return new;
end $fn$;

drop trigger if exists a00_phase_c_task_trace_guard on public.phase_c_task;
create trigger a00_phase_c_task_trace_guard
  before insert or update on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_guard();

create or replace function public.fn_phase_c_task_trace_subject()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.trace_id is not null then
    update public.phase_c_trace
       set task_id = new.task_id, subject_ref = new.task_id::text
     where trace_id = new.trace_id and task_id is null;
  end if;
  return null;
end $fn$;

drop trigger if exists z90_phase_c_task_trace_subject on public.phase_c_task;
create trigger z90_phase_c_task_trace_subject
  after insert on public.phase_c_task
  for each row execute function public.fn_phase_c_task_trace_subject();

-- ---- 6. the trace writer and the advance, as they were ------------------------------------
create or replace function public.fn_phase_c_trace_advance(
  p_trace_id bigint, p_state_after text, p_seal boolean default false, p_body jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.phase_c_trace%rowtype; v_new bigint;
begin
  if p_trace_id is null then return null; end if;
  select * into t from public.phase_c_trace where trace_id = p_trace_id;
  if not found then
    raise exception 'fn_phase_c_trace_advance: no trace %', p_trace_id using errcode = '23503';
  end if;
  if t.sealed_at is not null then
    v_new := public.fn_phase_c_trace_write(t.trace_policy_id, jsonb_build_object(
      'subject_kind', t.subject_kind, 'subject_ref', t.subject_ref,
      'command_id', t.command_id, 'run_id', t.run_id, 'step_run_id', t.step_run_id,
      'task_id', t.task_id, 'actor_role_id', t.actor_role_id,
      'manager_role_id', t.manager_role_id, 'system_actor_id', t.system_actor_id,
      'state_before', t.state_after, 'state_after', p_state_after,
      'evidence_refs', coalesce(p_body->'evidence_refs', '[]'::jsonb),
      'status', case when p_seal then 'sealed' else 'open' end));
    update public.phase_c_trace set parent_trace_id = coalesce(t.parent_trace_id, t.trace_id)
      where trace_id = v_new;
    update public.phase_c_trace set superseded_by = v_new where trace_id = p_trace_id;
    if p_seal then update public.phase_c_trace set sealed_at = now() where trace_id = v_new; end if;
    return v_new;
  end if;
  update public.phase_c_trace set
    state_before  = coalesce(nullif(t.state_before,''), t.state_after),
    state_after   = p_state_after,
    status        = case when p_seal then 'sealed' else 'open' end,
    sealed_at     = case when p_seal then now() else null end,
    output_hash   = coalesce(nullif(p_body->>'output_hash',''), t.output_hash),
    evidence_refs = case when p_body ? 'evidence_refs'
                         then coalesce(t.evidence_refs,'[]'::jsonb) || (p_body->'evidence_refs')
                         else t.evidence_refs end
  where trace_id = p_trace_id;
  return p_trace_id;
end $fn$;

create or replace function public.fn_phase_c_trace_write(p_policy text, p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if not exists (select 1 from public.phase_c_trace_policy where trace_policy_id = p_policy) then
    raise exception 'unknown trace policy %', p_policy using errcode = '23503';
  end if;
  insert into public.phase_c_trace (
    trace_policy_id, subject_kind, subject_ref, command_id, run_id, step_run_id, task_id,
    actor_role_id, manager_role_id, system_actor_id, component_id, authority_result,
    reviewer_role_id, reviewer_independent, gates, rules, evidence_refs, input_hash,
    output_hash, state_before, state_after, event_ids, status)
  values (
    p_policy,
    coalesce(p_body->>'subject_kind', 'unknown'), coalesce(p_body->>'subject_ref', ''),
    (p_body->>'command_id')::bigint, (p_body->>'run_id')::bigint,
    (p_body->>'step_run_id')::bigint, (p_body->>'task_id')::bigint,
    coalesce(p_body->>'actor_role_id',''), coalesce(p_body->>'manager_role_id',''),
    coalesce(p_body->>'system_actor_id',''), coalesce(p_body->>'component_id',''),
    coalesce(p_body->>'authority_result',''), coalesce(p_body->>'reviewer_role_id',''),
    (p_body->>'reviewer_independent')::boolean,
    coalesce(p_body->'gates','[]'::jsonb), coalesce(p_body->'rules','[]'::jsonb),
    coalesce(p_body->'evidence_refs','[]'::jsonb), coalesce(p_body->>'input_hash',''),
    coalesce(p_body->>'output_hash',''), coalesce(p_body->>'state_before',''),
    coalesce(p_body->>'state_after',''), coalesce(p_body->'event_ids','[]'::jsonb),
    coalesce(p_body->>'status','open'))
  returning trace_id into v_id;
  if v_id is null then
    raise exception 'phase_c_trace_write produced no row for policy %', p_policy using errcode = '23502';
  end if;
  return v_id;
end $fn$;

-- ---- 7. the invariant --------------------------------------------------------------------
drop function if exists public.fn_kernel_trace_integrity();

-- Deliberately NOT reverted (see the header): the sealed_at stamps, the task_id reverse links,
-- the orphan annotations and the reconstructed step traces. All 16 rows are identifiable with
--   select trace_id from public.phase_c_trace
--    where exists (select 1 from jsonb_array_elements(evidence_refs) e where e ? 'k6_backfill');

commit;
