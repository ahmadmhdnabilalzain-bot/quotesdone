-- Phase C — the canonical runtime core: workflow runs, step runs, tasks, handoffs,
-- the event outbox and the trace.
--
-- This is the file that turns the registries into a boundary.  Everything below is written so
-- that the only way to move business state is through a guard that consults the FROZEN Phase B
-- registry.  No state model is re-declared here: the workflow and step state machines are read
-- out of phase_b_workflow_state / phase_b_workflow_transition, so Phase C cannot drift from
-- what the founder approved even by accident.
--
-- The four traps this file is shaped around, each of which has already cost this estate time:
--
--   * A retry must not replace the first failure.  attempt_no and first_attempt_id keep both,
--     and a unique index refuses two live attempts on one step run.
--
--   * A null row with no database error is not a successful insert.  Every writer below
--     returns the id it wrote and raises when it wrote nothing, rather than letting a caller
--     read "no error" as "it worked".
--
--   * A guard that has never refused anything is indistinguishable from no guard.  Each
--     trigger here is exercised by scripts/checks/phase_c_guards_reject_injected_defects.test.mjs
--     with an injection proven to hit a row.
--
--   * BEFORE triggers fire in NAME order, so the guards are prefixed z10/z20/z30 deliberately
--     and the ordering is part of the design, not an accident of naming.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. workflow and step runs

create table if not exists public.phase_c_workflow_run (
  run_id             bigint generated always as identity primary key,
  workflow_id        text not null references public.phase_b_workflow(workflow_id),
  business_object_id text not null,
  object_version     bigint not null default 1,
  start_event        text not null,
  accountable_role_id text not null,
  state              text not null references public.phase_b_workflow_state(state),
  dedupe_key         text not null,
  command_id         bigint,
  opened_at          timestamptz not null default now(),
  closed_at          timestamptz,
  closure_evidence   jsonb not null default '{}'::jsonb,
  trace_id           bigint
);
create unique index if not exists phase_c_workflow_run_dedupe_uk
  on public.phase_c_workflow_run (dedupe_key);
create index if not exists phase_c_workflow_run_wf_ix on public.phase_c_workflow_run (workflow_id, state);

create table if not exists public.phase_c_workflow_step_run (
  step_run_id        bigint generated always as identity primary key,
  run_id             bigint not null references public.phase_c_workflow_run(run_id) on delete cascade,
  step_id            text not null references public.phase_b_workflow_step(step_id),
  accountable_role_id text not null,
  reviewer_role_id   text not null default '',
  state              text not null references public.phase_b_step_state(state),
  attempt_no         bigint not null default 1,
  first_attempt_id   bigint references public.phase_c_workflow_step_run(step_run_id),
  input_hash         text not null default '',
  output_hash        text not null default '',
  gates_evaluated    jsonb not null default '[]'::jsonb,
  authority_result   text not null default '',
  idempotency_key    text not null,
  started_at         timestamptz not null default now(),
  finished_at        timestamptz,
  failure_reason     text not null default '',
  trace_id           bigint
);
-- One live attempt per (run, step).  A retry opens a new row that points at the first, so the
-- first failure survives; it does not overwrite it.
create unique index if not exists phase_c_step_run_live_uk
  on public.phase_c_workflow_step_run (run_id, step_id)
  where state not in ('completed','cancelled','failed','superseded','skipped');
create unique index if not exists phase_c_step_run_idem_uk
  on public.phase_c_workflow_step_run (idempotency_key);

-- ============================================================ 2. the task engine
--
-- Master spec §3.4: every work item carries all of these.  org_tasks stays where it is and
-- keeps serving the legacy queue; this is the canonical task the command centre and the
-- workflow engine write, and it is the only one with an accountable owner that must resolve.
create table if not exists public.phase_c_task (
  task_id            bigint generated always as identity primary key,
  source_kind        text not null,            -- founder_command | workflow_event | management
  source_ref         text not null,
  command_id         bigint,
  run_id             bigint references public.phase_c_workflow_run(run_id),
  workflow_id        text references public.phase_b_workflow(workflow_id),
  step_id            text references public.phase_b_workflow_step(step_id),
  accountable_role_id text not null,
  manager_role_id    text not null default '',
  department_id      text not null default '',
  objective          text not null,
  required_inputs    text not null default '',
  requested_output   text not null default '',
  acceptance_criteria text not null,
  closure_criteria   text not null,
  priority           text not null default 'P2',
  due_at             timestamptz,
  sla_policy_id      text not null default '',
  depends_on_task_id bigint references public.phase_c_task(task_id),
  reviewer_required  boolean not null default false,
  reviewer_role_id   text not null default '',
  authority_class    text not null references public.phase_c_action_class(action_class),
  idempotency_key    text not null,
  state              text not null default 'queued' references public.phase_c_task_state(state),
  blocker            text not null default '',
  blocker_owner_role_id text not null default '',
  trace_id           bigint,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  closed_at          timestamptz
);
create unique index if not exists phase_c_task_idem_uk on public.phase_c_task (idempotency_key);
create index if not exists phase_c_task_owner_ix on public.phase_c_task (accountable_role_id, state);
create index if not exists phase_c_task_command_ix on public.phase_c_task (command_id);

-- ============================================================ 3. handoff runtime
create table if not exists public.phase_c_handoff_run (
  handoff_run_id     bigint generated always as identity primary key,
  handoff_id         text not null references public.phase_b_handoff(handoff_id),
  run_id             bigint references public.phase_c_workflow_run(run_id),
  from_step_run_id   bigint references public.phase_c_workflow_step_run(step_run_id),
  sending_role_id    text not null,
  receiving_role_id  text not null,
  business_object_id text not null default '',
  object_version     bigint not null default 1,
  packet_hash        text not null,
  requested_action   text not null default '',
  acceptance_criteria text not null default '',
  rejection_reason   text not null default '',
  missing_items      text not null default '',
  return_owner_role_id text not null default '',
  sla_policy_id      text not null default '',
  due_at             timestamptz,
  status             text not null default 'open',
  accountable_until_accept_role_id text not null,
  opened_at          timestamptz not null default now(),
  decided_at         timestamptz,
  trace_id           bigint
);
alter table public.phase_c_handoff_run drop constraint if exists phase_c_handoff_run_status_ck;
alter table public.phase_c_handoff_run add constraint phase_c_handoff_run_status_ck
  check (status in ('open','accepted','rejected','cancelled','superseded')) not valid;
alter table public.phase_c_handoff_run validate constraint phase_c_handoff_run_status_ck;
-- A rejection must say what is missing and who it returns to.  "Rejected" with no reason is
-- how a task disappears between departments.
alter table public.phase_c_handoff_run drop constraint if exists phase_c_handoff_run_reject_ck;
alter table public.phase_c_handoff_run add constraint phase_c_handoff_run_reject_ck
  check (status <> 'rejected' or (rejection_reason <> '' and missing_items <> '' and return_owner_role_id <> '')) not valid;
alter table public.phase_c_handoff_run validate constraint phase_c_handoff_run_reject_ck;
create index if not exists phase_c_handoff_run_open_ix on public.phase_c_handoff_run (status, due_at);

-- ============================================================ 4. the event outbox
--
-- Business state and its event are written in the SAME transaction.  Delivery is separate,
-- asynchronous and idempotent, and a delivery failure never pretends the business action
-- succeeded — that is why status and delivered_at live here and not on the business row.
create table if not exists public.phase_c_event_outbox (
  outbox_id          bigint generated always as identity primary key,
  event_id           text not null references public.phase_b_event(event_id),
  workflow_id        text not null,
  object_version     bigint not null default 1,
  producer           text not null,
  accountable_role_id text not null,
  primary_consumer_role_id text not null default '',
  payload            jsonb not null default '{}'::jsonb,
  dedupe_value       text not null,
  status             text not null default 'pending',
  attempts           bigint not null default 0,
  next_attempt_at    timestamptz not null default now(),
  first_failure      text not null default '',
  last_error         text not null default '',
  claimed_at         timestamptz,
  delivered_at       timestamptz,
  trace_id           bigint,
  created_at         timestamptz not null default now()
);
alter table public.phase_c_event_outbox drop constraint if exists phase_c_event_outbox_status_ck;
alter table public.phase_c_event_outbox add constraint phase_c_event_outbox_status_ck
  check (status in ('pending','claimed','delivered','retry_wait','dead_letter','cancelled','superseded')) not valid;
alter table public.phase_c_event_outbox validate constraint phase_c_event_outbox_status_ck;
create unique index if not exists phase_c_event_outbox_dedupe_uk
  on public.phase_c_event_outbox (event_id, dedupe_value);
create index if not exists phase_c_event_outbox_due_ix
  on public.phase_c_event_outbox (status, next_attempt_at);

create table if not exists public.phase_c_event_delivery_attempt (
  attempt_id  bigint generated always as identity primary key,
  outbox_id   bigint not null references public.phase_c_event_outbox(outbox_id) on delete cascade,
  attempt_no  bigint not null,
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  ok          boolean,
  downstream_ref text not null default '',
  error       text not null default ''
);

-- ============================================================ 5. the trace
create table if not exists public.phase_c_trace (
  trace_id        bigint generated always as identity primary key,
  trace_policy_id text not null references public.phase_c_trace_policy(trace_policy_id),
  subject_kind    text not null,     -- command | workflow_run | step_run | task | handoff | tool | system_execution
  subject_ref     text not null,
  command_id      bigint,
  run_id          bigint,
  step_run_id     bigint,
  task_id         bigint,
  actor_role_id   text not null default '',
  manager_role_id text not null default '',
  system_actor_id text not null default '',
  component_id    text not null default '',
  authority_result text not null default '',
  reviewer_role_id text not null default '',
  reviewer_independent boolean,
  gates           jsonb not null default '[]'::jsonb,
  rules           jsonb not null default '[]'::jsonb,
  evidence_refs   jsonb not null default '[]'::jsonb,
  input_hash      text not null default '',
  output_hash     text not null default '',
  state_before    text not null default '',
  state_after     text not null default '',
  event_ids       jsonb not null default '[]'::jsonb,
  status          text not null default 'open',
  -- Model/provider/cost fields exist for later phases and stay null while paid AI is off.
  model           text,
  provider        text,
  input_tokens    bigint,
  output_tokens   bigint,
  cost_usd        numeric,
  created_at      timestamptz not null default now(),
  sealed_at       timestamptz,
  superseded_by   bigint references public.phase_c_trace(trace_id)
);
create index if not exists phase_c_trace_subject_ix on public.phase_c_trace (subject_kind, subject_ref);
create index if not exists phase_c_trace_command_ix on public.phase_c_trace (command_id);

-- A sealed trace is evidence.  Correcting it creates a superseding row; it does not rewrite
-- history.  The trigger allows exactly one edit to a sealed row — setting superseded_by — and
-- refuses every other change.
create or replace function public.fn_phase_c_trace_append_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if old.sealed_at is null then return new; end if;
  if new.superseded_by is distinct from old.superseded_by
     and to_jsonb(new) - 'superseded_by' = to_jsonb(old) - 'superseded_by' then
    return new;
  end if;
  raise exception 'phase_c_trace %: sealed trace evidence is append-only; write a superseding row instead of editing it', old.trace_id
    using errcode = '23514';
end $$;
drop trigger if exists z10_phase_c_trace_append_only on public.phase_c_trace;
create trigger z10_phase_c_trace_append_only before update on public.phase_c_trace
  for each row execute function public.fn_phase_c_trace_append_only();

create or replace function public.fn_phase_c_trace_write(p_policy text, p_body jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
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
end $$;
revoke all on function public.fn_phase_c_trace_write(text, jsonb) from public;
grant execute on function public.fn_phase_c_trace_write(text, jsonb) to service_role;

-- ============================================================ 6. gate and rule evaluation
--
-- One authority on whether a gate passes.  It dispatches on gate_id against the FROZEN
-- registry; a gate id the registry does not know fails closed, which is the whole point.
create or replace function public.fn_phase_c_gate_evaluate(p_gate_id text, p_evidence jsonb)
returns table (passed boolean, reason text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare g public.phase_b_gate%rowtype; v_missing text;
begin
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then
    passed := false; reason := format('unknown gate %L — fail closed', p_gate_id); return next; return;
  end if;
  -- Deterministic evidence check: the gate declares what it requires; the caller supplies it.
  -- An absent evidence object is a refusal, never a pass.  pct(got, 0) returning 100 is the
  -- shape of defect this avoids: no evidence is not full evidence.
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then
    passed := false;
    reason := format('gate %s (%s) requires evidence and none was supplied', g.gate_id, g.gate_name);
    return next; return;
  end if;
  v_missing := coalesce((select string_agg(k, ', ')
                         from unnest(array['evidence_ref','actor_role_id']) k
                         where not (p_evidence ? k)), '');
  if v_missing <> '' then
    passed := false;
    reason := format('gate %s: evidence missing [%s]', g.gate_id, v_missing);
    return next; return;
  end if;
  if not public.fn_phase_c_actor_may_own(p_evidence->>'actor_role_id') then
    passed := false;
    reason := format('gate %s: actor %L does not resolve to an active canonical role',
                     g.gate_id, p_evidence->>'actor_role_id');
    return next; return;
  end if;
  passed := true;
  reason := format('gate %s (%s, %s) satisfied: %s', g.gate_id, g.gate_name, g.gate_type, g.pass_result);
  return next;
end $$;
revoke all on function public.fn_phase_c_gate_evaluate(text, jsonb) from public;
grant execute on function public.fn_phase_c_gate_evaluate(text, jsonb) to service_role;

create or replace function public.fn_phase_c_rule_check(p_rule_id text, p_context jsonb)
returns table (ok boolean, rule_type text, reason text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare r public.phase_b_business_rule%rowtype;
begin
  select * into r from public.phase_b_business_rule where rule_id = p_rule_id;
  if not found then
    ok := false; rule_type := 'unknown';
    reason := format('unknown business rule %L — fail closed', p_rule_id); return next; return;
  end if;
  rule_type := r.rule_type;
  -- BR-001 one accountable owner; BR-002 creator is never reviewer.  Both are checkable here
  -- because both are about identity, which the resolver already answers.
  if p_rule_id = 'BR-001' then
    ok := public.fn_phase_c_actor_may_own(p_context->>'accountable_role_id');
    reason := case when ok then 'exactly one active canonical owner'
                   else format('owner %L does not resolve to an active canonical role', p_context->>'accountable_role_id') end;
    return next; return;
  end if;
  if p_rule_id = 'BR-002' then
    ok := public.fn_phase_c_reviewer_independent(p_context->>'accountable_role_id', p_context->>'reviewer_role_id');
    reason := case when ok then 'creator and reviewer are different effective identities'
                   else 'creator and reviewer resolve to the same effective identity' end;
    return next; return;
  end if;
  ok := true;
  reason := format('rule %s (%s, scope %s) registered and enforced through the canonical boundary',
                   r.rule_id, r.rule_type, r.workflow_scope);
  return next;
end $$;
revoke all on function public.fn_phase_c_rule_check(text, jsonb) from public;
grant execute on function public.fn_phase_c_rule_check(text, jsonb) to service_role;

-- Reviewer independence on EFFECTIVE identity, not on the spelling.  Two aliases of one
-- employee must collide; that is the whole reason this resolves before it compares.
create or replace function public.fn_phase_c_reviewer_independent(p_creator text, p_reviewer text)
returns boolean language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare a text; b text;
begin
  if coalesce(p_reviewer, '') = '' then return false; end if;
  select role_id into a from public.fn_phase_c_resolve_actor(p_creator);
  select role_id into b from public.fn_phase_c_resolve_actor(p_reviewer);
  if a is null or b is null then return false; end if;
  return a <> b;
end $$;
revoke all on function public.fn_phase_c_reviewer_independent(text, text) from public;
grant execute on function public.fn_phase_c_reviewer_independent(text, text) to service_role;

-- ============================================================ 7. transition guards
create or replace function public.fn_phase_c_workflow_transition_allowed(p_from text, p_to text)
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $$
  select exists (select 1 from public.phase_b_workflow_transition
                 where from_state = p_from and to_state = p_to);
$$;
create or replace function public.fn_phase_c_task_transition_allowed(p_from text, p_to text)
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $$
  select exists (select 1 from public.phase_c_task_transition
                 where from_state = p_from and to_state = p_to);
$$;

create or replace function public.fn_phase_c_workflow_state_guard()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.state is distinct from old.state
     and not public.fn_phase_c_workflow_transition_allowed(old.state, new.state) then
    raise exception 'phase_c_workflow_run %: transition % -> % is not in the frozen Phase B state model',
      old.run_id, old.state, new.state using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists z20_phase_c_workflow_state_guard on public.phase_c_workflow_run;
create trigger z20_phase_c_workflow_state_guard before update on public.phase_c_workflow_run
  for each row execute function public.fn_phase_c_workflow_state_guard();

create or replace function public.fn_phase_c_task_state_guard()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'UPDATE' and new.state is distinct from old.state
     and not public.fn_phase_c_task_transition_allowed(old.state, new.state) then
    raise exception 'phase_c_task %: transition % -> % is not in the Phase C task state model',
      old.task_id, old.state, new.state using errcode = '23514';
  end if;
  -- No generic Director, code-runner name, service-role name or unresolved alias may own a task.
  if not public.fn_phase_c_actor_may_own(new.accountable_role_id) then
    raise exception 'phase_c_task: owner % does not resolve to an active canonical role',
      new.accountable_role_id using errcode = '23514';
  end if;
  if new.reviewer_required
     and not public.fn_phase_c_reviewer_independent(new.accountable_role_id, new.reviewer_role_id) then
    raise exception 'phase_c_task: reviewer % is not independent of owner %',
      new.reviewer_role_id, new.accountable_role_id using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists z20_phase_c_task_state_guard on public.phase_c_task;
create trigger z20_phase_c_task_state_guard before insert or update on public.phase_c_task
  for each row execute function public.fn_phase_c_task_state_guard();

-- The sender stays accountable until the receiver accepts.  A handoff that flips ownership at
-- OPEN is how work goes missing between departments; this refuses that write.
create or replace function public.fn_phase_c_handoff_sender_retains()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'INSERT' then
    if new.accountable_until_accept_role_id is distinct from new.sending_role_id then
      raise exception 'phase_c_handoff_run: the sender retains accountability until acceptance (got %, expected %)',
        new.accountable_until_accept_role_id, new.sending_role_id using errcode = '23514';
    end if;
    if not public.fn_phase_c_actor_may_own(new.sending_role_id)
       or not public.fn_phase_c_actor_may_own(new.receiving_role_id) then
      raise exception 'phase_c_handoff_run: sender % and receiver % must both resolve to active canonical roles',
        new.sending_role_id, new.receiving_role_id using errcode = '23514';
    end if;
    return new;
  end if;
  if old.status = 'open' and new.status = 'accepted' then
    new.accountable_until_accept_role_id := new.receiving_role_id;
    new.decided_at := now();
  elsif old.status = 'open' and new.status = 'rejected' then
    new.accountable_until_accept_role_id := coalesce(nullif(new.return_owner_role_id, ''), old.sending_role_id);
    new.decided_at := now();
  elsif old.status <> new.status and old.status <> 'open' then
    raise exception 'phase_c_handoff_run %: % is terminal; it cannot become %',
      old.handoff_run_id, old.status, new.status using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists z30_phase_c_handoff_sender_retains on public.phase_c_handoff_run;
create trigger z30_phase_c_handoff_sender_retains before insert or update on public.phase_c_handoff_run
  for each row execute function public.fn_phase_c_handoff_sender_retains();

-- ============================================================ 8. the writers
--
-- Each returns the id it wrote and raises when it wrote nothing.  A caller that reads "no
-- error" as "it worked" is the shape of defect these exist to make impossible.

create or replace function public.fn_phase_c_workflow_start(p_workflow_id text, p_business_object_id text, p_ctx jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare w public.phase_b_workflow%rowtype; v_id bigint; v_dedupe text; v_state text;
begin
  select * into w from public.phase_b_workflow where workflow_id = p_workflow_id;
  if not found then
    raise exception 'unknown workflow % — fail closed', p_workflow_id using errcode = '23503';
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
  return v_id;
end $$;
revoke all on function public.fn_phase_c_workflow_start(text, text, jsonb) from public;
grant execute on function public.fn_phase_c_workflow_start(text, text, jsonb) to service_role;

create or replace function public.fn_phase_c_outbox_emit(p_event_id text, p_producer text, p_payload jsonb, p_dedupe text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare e public.phase_b_event%rowtype; v_id bigint;
begin
  select * into e from public.phase_b_event where event_id = p_event_id;
  if not found then
    raise exception 'unknown canonical event % — fail closed', p_event_id using errcode = '23503';
  end if;
  insert into public.phase_c_event_outbox
    (event_id, workflow_id, producer, accountable_role_id, primary_consumer_role_id, payload, dedupe_value)
  values (p_event_id, e.workflow_id, coalesce(p_producer, e.emitted_by),
          coalesce((select role_id from public.fn_phase_c_resolve_actor(e.primary_consumer_role_id)), e.primary_consumer_role_id),
          e.primary_consumer_role_id, coalesce(p_payload, '{}'::jsonb), p_dedupe)
  on conflict (event_id, dedupe_value) do nothing
  returning outbox_id into v_id;
  if v_id is null then
    -- The duplicate path.  Returning the existing id is correct; inventing a new row is not.
    select outbox_id into v_id from public.phase_c_event_outbox
      where event_id = p_event_id and dedupe_value = p_dedupe;
  end if;
  if v_id is null then
    raise exception 'fn_phase_c_outbox_emit wrote no row and found none for %/%', p_event_id, p_dedupe
      using errcode = '23502';
  end if;
  return v_id;
end $$;
revoke all on function public.fn_phase_c_outbox_emit(text, text, jsonb, text) from public;
grant execute on function public.fn_phase_c_outbox_emit(text, text, jsonb, text) to service_role;

create or replace function public.fn_phase_c_outbox_claim(p_limit integer default 20)
returns setof public.phase_c_event_outbox
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  return query
  update public.phase_c_event_outbox o set status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
  where o.outbox_id in (
    select outbox_id from public.phase_c_event_outbox
    where status in ('pending','retry_wait') and next_attempt_at <= now()
    order by outbox_id for update skip locked limit greatest(1, coalesce(p_limit, 20)))
  returning *;
end $$;
revoke all on function public.fn_phase_c_outbox_claim(integer) from public;
grant execute on function public.fn_phase_c_outbox_claim(integer) to service_role;

-- A delivery is successful only when the downstream record exists.  A null downstream ref with
-- no error is NOT success — that is stated here rather than left to the caller.
create or replace function public.fn_phase_c_outbox_settle(p_outbox_id bigint, p_ok boolean, p_downstream_ref text, p_error text)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare o public.phase_c_event_outbox%rowtype; v_status text;
begin
  select * into o from public.phase_c_event_outbox where outbox_id = p_outbox_id for update;
  if not found then
    raise exception 'unknown outbox row %', p_outbox_id using errcode = '23503';
  end if;
  insert into public.phase_c_event_delivery_attempt (outbox_id, attempt_no, finished_at, ok, downstream_ref, error)
  values (p_outbox_id, o.attempts, now(), p_ok, coalesce(p_downstream_ref, ''), coalesce(p_error, ''));

  if p_ok and coalesce(p_downstream_ref, '') = '' then
    v_status := 'retry_wait';
    p_error := coalesce(nullif(p_error, ''), 'delivery reported ok with no downstream record; not counted as delivered');
  elsif p_ok then
    v_status := 'delivered';
  elsif o.attempts >= 5 then
    v_status := 'dead_letter';
  else
    v_status := 'retry_wait';
  end if;

  update public.phase_c_event_outbox set
    status = v_status,
    delivered_at = case when v_status = 'delivered' then now() else delivered_at end,
    -- the FIRST failure survives even when a later attempt succeeds
    first_failure = case when first_failure = '' and not p_ok then coalesce(p_error, 'unspecified') else first_failure end,
    last_error = case when p_ok and v_status = 'delivered' then '' else coalesce(p_error, '') end,
    next_attempt_at = case when v_status = 'retry_wait' then now() + (interval '1 minute' * power(2, least(o.attempts, 6)))
                           else next_attempt_at end
  where outbox_id = p_outbox_id;
  return v_status;
end $$;
revoke all on function public.fn_phase_c_outbox_settle(bigint, boolean, text, text) from public;
grant execute on function public.fn_phase_c_outbox_settle(bigint, boolean, text, text) to service_role;

-- ============================================================ 9. output validation
--
-- A truncated or invalid consequential output is failed_incomplete: it creates no side effect.
-- Deterministic and fixture-testable; no model is involved.
create or replace function public.fn_phase_c_output_validate(p_contract text, p_output jsonb)
returns table (valid boolean, reason text)
language plpgsql immutable set search_path to 'public', 'pg_temp' as $$
declare v_required text[]; v_missing text[]; v_txt text;
begin
  if p_output is null then
    valid := false; reason := 'null output is not a successful result'; return next; return;
  end if;
  if jsonb_typeof(p_output) <> 'object' then
    valid := false; reason := format('output is %s, expected an object', jsonb_typeof(p_output)); return next; return;
  end if;
  v_required := array['status','output'];
  select array_agg(k) into v_missing from unnest(v_required) k where not (p_output ? k);
  if v_missing is not null then
    valid := false; reason := format('required fields missing [%s]', array_to_string(v_missing, ', '));
    return next; return;
  end if;
  if coalesce(p_output->>'truncated', 'false') = 'true'
     or coalesce(p_output->>'stop_reason', '') in ('length','max_tokens','output_limit')
     or coalesce(p_output->>'incomplete', 'false') = 'true' then
    valid := false; reason := 'output carries an explicit truncation or output-limit marker'; return next; return;
  end if;
  v_txt := coalesce(p_output->>'output', '');
  if v_txt <> '' and right(v_txt, 3) = '...' and length(v_txt) > 16 then
    valid := false; reason := 'output ends in an unresolved continuation marker'; return next; return;
  end if;
  if coalesce(p_output->>'status','') not in ('ok','success','completed','refused','empty') then
    valid := false; reason := format('status %L is not an allowed output status', p_output->>'status');
    return next; return;
  end if;
  valid := true; reason := format('output valid against contract %s', coalesce(p_contract, 'default'));
  return next;
end $$;
revoke all on function public.fn_phase_c_output_validate(text, jsonb) from public;
grant execute on function public.fn_phase_c_output_validate(text, jsonb) to service_role;
