-- Phase C — the Founder Command Center.
--
-- The founder gives an order; the Chief of Staff turns it into a command plan and real tasks
-- owned by exact canonical employees, in ONE transaction, before the API answers.  That last
-- clause is the whole design: a plan that is committed after the response has already been
-- sent is a plan that can be lost, and "the task table exists" is not an implementation.
--
-- Three properties this file is built to hold, each enforced rather than intended:
--
--   * No raw natural-language message executes a side effect.  fn_founder_command_submit is
--     the only entry point, it classifies against a REGISTERED rule table, and a low-confidence
--     input produces exactly one clarification question and zero tasks.
--
--   * The Chief of Staff owns every command and never usurps a department.  The command owner
--     column is constrained to chief_of_staff; each child task carries its own exact owner,
--     which the task guard in phase_c_03 refuses unless it resolves to an active canonical role.
--
--   * Interpretation is deterministic and free.  There is no model call anywhere in this file.
--     The classifier is a scored keyword registry with an explicit specificity requirement, so
--     "Make marketing better" — which names a real workflow but no deliverable — asks a
--     question instead of inventing work.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. the command objects

create table if not exists public.founder_command_session (
  session_id      bigint generated always as identity primary key,
  founder_identity text not null,
  opened_at       timestamptz not null default now(),
  closed_at       timestamptz
);

-- Append-only.  The exact bytes the founder sent, and their hash, so a later interpretation
-- can be checked against what was actually said rather than against a paraphrase of it.
create table if not exists public.founder_command_message (
  message_id      bigint generated always as identity primary key,
  session_id      bigint references public.founder_command_session(session_id),
  founder_identity text not null,
  raw_text        text not null,
  raw_text_hash   text not null,
  client_idempotency_key text not null,
  channel         text not null default 'command_center',
  received_at     timestamptz not null default now()
);
create unique index if not exists founder_command_message_idem_uk
  on public.founder_command_message (client_idempotency_key);

create or replace function public.fn_founder_command_message_immutable()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  raise exception 'founder_command_message %: the founder''s own words are append-only', old.message_id
    using errcode = '23514';
end $$;
drop trigger if exists z10_founder_command_message_immutable on public.founder_command_message;
create trigger z10_founder_command_message_immutable before update or delete
  on public.founder_command_message for each row
  execute function public.fn_founder_command_message_immutable();

create table if not exists public.founder_command (
  command_id      bigint generated always as identity primary key,
  message_id      bigint not null references public.founder_command_message(message_id),
  intent_id       text not null,
  outcome         text not null,
  command_owner_role_id text not null default 'chief_of_staff',
  state           text not null default 'received' references public.phase_c_command_state(state),
  priority        text not null default 'P2',
  primary_role_id text not null default '',
  founder_initiated_only boolean not null default false,
  refund_semantics boolean not null default false,
  due_at          timestamptz,
  created_at      timestamptz not null default now(),
  closed_at       timestamptz,
  trace_id        bigint,
  superseded_by   bigint references public.founder_command(command_id)
);
alter table public.founder_command drop constraint if exists founder_command_owner_ck;
alter table public.founder_command add constraint founder_command_owner_ck
  check (command_owner_role_id = 'chief_of_staff') not valid;
alter table public.founder_command validate constraint founder_command_owner_ck;

create table if not exists public.founder_command_interpretation (
  interpretation_id bigint generated always as identity primary key,
  command_id      bigint not null references public.founder_command(command_id) on delete cascade,
  version         bigint not null default 1,
  intent_id       text not null,
  confidence      numeric not null,
  matched_rule_id text not null default '',
  workflow_ids    text not null default '',
  specificity_signals text not null default '',
  reason          text not null,
  created_at      timestamptz not null default now()
);
create unique index if not exists founder_command_interpretation_version_uk
  on public.founder_command_interpretation (command_id, version);

create table if not exists public.founder_command_plan (
  plan_id         bigint generated always as identity primary key,
  command_id      bigint not null references public.founder_command(command_id) on delete cascade,
  summary         text not null,
  child_task_count bigint not null default 0,
  departments     text not null default '',
  created_at      timestamptz not null default now()
);
create unique index if not exists founder_command_plan_uk on public.founder_command_plan (command_id);

create table if not exists public.founder_command_workflow_link (
  command_id  bigint not null references public.founder_command(command_id) on delete cascade,
  workflow_id text not null references public.phase_b_workflow(workflow_id),
  run_id      bigint references public.phase_c_workflow_run(run_id),
  primary key (command_id, workflow_id)
);

create table if not exists public.founder_command_task_link (
  command_id bigint not null references public.founder_command(command_id) on delete cascade,
  task_id    bigint not null references public.phase_c_task(task_id) on delete cascade,
  primary key (command_id, task_id)
);

create table if not exists public.founder_command_clarification (
  clarification_id bigint generated always as identity primary key,
  command_id  bigint not null references public.founder_command(command_id) on delete cascade,
  question    text not null,
  asked_at    timestamptz not null default now(),
  answer_text text,
  answered_at timestamptz
);

create table if not exists public.founder_command_status_history (
  history_id bigint generated always as identity primary key,
  command_id bigint not null references public.founder_command(command_id) on delete cascade,
  from_state text not null default '',
  to_state   text not null,
  reason     text not null default '',
  at         timestamptz not null default now()
);

create table if not exists public.founder_command_completion (
  command_id bigint primary key references public.founder_command(command_id) on delete cascade,
  summary    text not null,
  evidence   jsonb not null default '{}'::jsonb,
  closed_at  timestamptz not null default now()
);

-- The command state machine, enforced against the registered transitions.
create or replace function public.fn_founder_command_state_guard()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'UPDATE' and new.state is distinct from old.state then
    if not exists (select 1 from public.phase_c_command_transition
                   where from_state = old.state and to_state = new.state) then
      raise exception 'founder_command %: transition % -> % is not in the Phase C command state model',
        old.command_id, old.state, new.state using errcode = '23514';
    end if;
    insert into public.founder_command_status_history (command_id, from_state, to_state, reason)
    values (old.command_id, old.state, new.state, 'state guard');
  end if;
  return new;
end $$;
drop trigger if exists z20_founder_command_state_guard on public.founder_command;
create trigger z20_founder_command_state_guard before update on public.founder_command
  for each row execute function public.fn_founder_command_state_guard();

-- ============================================================ 2. the deterministic registry
--
-- Ordered rules.  The first rule whose pattern matches decides the intent; ties are impossible
-- because rule_order is unique.  This is DATA, not code, so what the router will do with a
-- given sentence is inspectable with a select rather than by reading a function body.
create table if not exists public.phase_c_command_rule (
  rule_id        text primary key,
  rule_order     bigint not null unique,
  pattern        text not null,           -- POSIX regex, matched case-insensitively
  antipattern    text not null default '',
  intent_id      text not null,
  outcome        text not null,
  workflow_ids   text not null default '',
  primary_role_id text not null default '',
  child_role_ids text not null default '',
  requires_specificity boolean not null default true,
  priority       text not null default 'P2',
  notes          text not null default ''
);

-- What makes an instruction actionable rather than a wish.  A command must carry at least one:
-- a quantity, a date or deadline, a named identifier, or a concrete deliverable noun.  This is
-- why "Make marketing better" asks a question and "Add one extra social media post this week"
-- does not.
create table if not exists public.phase_c_command_specificity_signal (
  signal_id text primary key,
  pattern   text not null,
  kind      text not null
);

create or replace function public.fn_phase_c_command_specificity(p_text text)
returns text language sql stable set search_path to 'public', 'pg_temp' as $$
  select coalesce(string_agg(s.signal_id || '=' || s.kind, '; ' order by s.signal_id), '')
  from public.phase_c_command_specificity_signal s
  where p_text ~* s.pattern;
$$;

-- ============================================================ 3. the classifier
create or replace function public.fn_founder_command_classify(p_text text)
returns table (intent_id text, outcome text, workflow_ids text, primary_role_id text,
               child_role_ids text, priority text, confidence numeric, matched_rule_id text,
               specificity text, reason text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare r public.phase_c_command_rule%rowtype; v_txt text := coalesce(p_text, '');
begin
  specificity := public.fn_phase_c_command_specificity(v_txt);
  for r in select * from public.phase_c_command_rule order by rule_order loop
    if v_txt ~* r.pattern and (r.antipattern = '' or not (v_txt ~* r.antipattern)) then
      if r.requires_specificity and specificity = '' then
        intent_id := 'AMBIGUOUS'; outcome := 'CLARIFICATION_REQUIRED';
        workflow_ids := ''; primary_role_id := 'chief_of_staff'; child_role_ids := '';
        priority := 'P2'; confidence := 0.35; matched_rule_id := r.rule_id;
        reason := format('matched %s but the instruction names no quantity, deadline, identifier or deliverable', r.rule_id);
        return next; return;
      end if;
      intent_id := r.intent_id; outcome := r.outcome; workflow_ids := r.workflow_ids;
      primary_role_id := r.primary_role_id; child_role_ids := r.child_role_ids;
      priority := r.priority; confidence := 0.95; matched_rule_id := r.rule_id;
      reason := format('deterministic registry rule %s (%s)', r.rule_id, r.notes);
      return next; return;
    end if;
  end loop;
  intent_id := 'AMBIGUOUS'; outcome := 'CLARIFICATION_REQUIRED'; workflow_ids := '';
  primary_role_id := 'chief_of_staff'; child_role_ids := ''; priority := 'P2';
  confidence := 0.0; matched_rule_id := '';
  reason := 'no registered command intent matches this instruction';
  return next;
end $$;
revoke all on function public.fn_founder_command_classify(text) from public;
grant execute on function public.fn_founder_command_classify(text) to service_role;

-- ============================================================ 4. the atomic entry point
--
-- One transaction.  When this returns ok, the command row, the interpretation, the workflow
-- links, every immediate task, the outbox rows and the trace all exist — or none of them does.
create or replace function public.fn_founder_command_submit(
  p_founder_identity text, p_text text, p_idempotency_key text, p_ctx jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  c            record;
  v_msg        bigint;
  v_cmd        bigint;
  v_existing   bigint;
  v_trace      bigint;
  v_task       bigint;
  v_tasks      bigint[] := '{}';
  v_owners     text[] := '{}';
  v_wf         text;
  v_child      text;
  v_owner      text;
  v_manager    text;
  v_dept       text;
  v_action     text;
  v_due        timestamptz;
  v_intent     public.phase_c_command_intent%rowtype;
  v_plan_id    bigint;
  v_qn         text;
begin
  if coalesce(p_founder_identity, '') = '' then
    raise exception 'founder identity is required' using errcode = '28000';
  end if;
  -- Only the registered founder identity may command the company.
  if not exists (select 1 from public.phase_c_founder_identity
                 where identity = lower(btrim(p_founder_identity)) and active) then
    return jsonb_build_object('ok', false, 'error', 'not_the_founder',
      'message', 'The Command Center accepts commands from the registered founder identity only.');
  end if;

  -- Idempotency: the same client key returns the SAME command rather than a second one.
  select m.message_id into v_msg from public.founder_command_message m
   where m.client_idempotency_key = p_idempotency_key;
  if v_msg is not null then
    select fc.command_id into v_existing from public.founder_command fc where fc.message_id = v_msg;
    return public.fn_founder_command_status(v_existing::text)
           || jsonb_build_object('duplicate_of_idempotency_key', p_idempotency_key);
  end if;

  insert into public.founder_command_message
    (session_id, founder_identity, raw_text, raw_text_hash, client_idempotency_key,
     channel)
  values ((p_ctx->>'session_id')::bigint, lower(btrim(p_founder_identity)), p_text,
          encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'), p_idempotency_key,
          coalesce(p_ctx->>'channel', 'command_center'))
  returning message_id into v_msg;

  select * into c from public.fn_founder_command_classify(p_text);

  insert into public.founder_command
    (message_id, intent_id, outcome, state, priority, primary_role_id,
     founder_initiated_only, refund_semantics)
  values (v_msg, c.intent_id, c.outcome, 'received', c.priority,
          coalesce(nullif(c.primary_role_id,''), 'chief_of_staff'),
          c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE'),
          c.outcome = 'REFUND_APPROVAL')
  returning command_id into v_cmd;
  if v_cmd is null then
    raise exception 'fn_founder_command_submit wrote no command row' using errcode = '23502';
  end if;

  insert into public.founder_command_interpretation
    (command_id, version, intent_id, confidence, matched_rule_id, workflow_ids,
     specificity_signals, reason)
  values (v_cmd, 1, c.intent_id, c.confidence, c.matched_rule_id, c.workflow_ids,
          c.specificity, c.reason);

  update public.founder_command set state = 'interpreting' where command_id = v_cmd;

  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind','command', 'subject_ref', v_cmd::text, 'command_id', v_cmd,
    'actor_role_id','founder', 'system_actor_id','system.command_router',
    'input_hash', encode(sha256(convert_to(coalesce(p_text,''), 'UTF8')), 'hex'),
    'state_before','received', 'state_after','interpreting', 'status','open'));
  update public.founder_command set trace_id = v_trace where command_id = v_cmd;

  -- ---------------------------------------------------------------- unsafe or ambiguous
  if c.outcome = 'REFUSE_UNSCOPED_UNSAFE_COMMAND' then
    update public.founder_command set state = 'refused', closed_at = now() where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','refused',
      'intent', c.intent_id, 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','chief_of_staff', 'tasks_created', 0,
      'blocker', 'Unscoped destructive or financial instruction. Name the individual cases and the evidence, and it will route.',
      'trace_id', v_trace);
  end if;

  if c.intent_id = 'AMBIGUOUS' then
    v_qn := case
      when c.matched_rule_id <> ''
        then format('I can route this, but not safely yet. Which %s, and by when?',
                    coalesce(nullif(regexp_replace(c.matched_rule_id, '^CR-\d+-', ''), ''), 'deliverable'))
      else 'I have no registered intent for that. What outcome do you want, in which area, and by when?'
    end;
    insert into public.founder_command_clarification (command_id, question) values (v_cmd, v_qn);
    update public.founder_command set state = 'clarification_required' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','clarification_required',
      'intent','AMBIGUOUS', 'interpretation', c.reason, 'workflow_ids','[]'::jsonb,
      'task_ids','[]'::jsonb, 'owner','chief_of_staff', 'tasks_created', 0,
      'clarification', v_qn, 'trace_id', v_trace);
  end if;

  -- ---------------------------------------------------------------- control commands
  if c.intent_id in ('CMD-STATUS','CMD-CANCEL','CMD-REPRIORITIZE','CMD-EXPLAIN') then
    update public.founder_command set state = 'accepted' where command_id = v_cmd;
    return jsonb_build_object('ok', true, 'command_id', v_cmd, 'status','accepted',
      'intent', c.intent_id, 'interpretation', c.reason, 'control_command', true,
      'workflow_ids','[]'::jsonb, 'task_ids','[]'::jsonb, 'owner','chief_of_staff',
      'tasks_created', 0, 'trace_id', v_trace,
      'next', 'call fn_founder_command_control(command_id, target_ref, new_priority)');
  end if;

  -- ---------------------------------------------------------------- route and create work
  update public.founder_command set state = 'accepted' where command_id = v_cmd;
  select * into v_intent from public.phase_c_command_intent where intent_id = c.intent_id;

  v_due := now() + case c.priority when 'P0' then interval '4 hours'
                                   when 'P1' then interval '2 days'
                                   else interval '5 days' end;

  for v_wf in select btrim(x) from unnest(string_to_array(c.workflow_ids, ';')) x where btrim(x) <> '' loop
    if exists (select 1 from public.phase_b_workflow where workflow_id = v_wf) then
      insert into public.founder_command_workflow_link (command_id, workflow_id)
      values (v_cmd, v_wf) on conflict do nothing;
    end if;
  end loop;
  update public.founder_command set state = 'routed' where command_id = v_cmd;

  -- The primary task: owned by the exact canonical role the registry names, never by a
  -- department, a title or the Chief of Staff standing in for one.
  v_owner := coalesce(nullif(c.primary_role_id, ''), v_intent.default_accountable_role_id, 'chief_of_staff');
  if v_owner <> 'founder' then
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_owner);
    if v_owner is null then
      raise exception 'command %: primary owner does not resolve to an active canonical role', v_cmd
        using errcode = '23514';
    end if;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    v_wf := split_part(c.workflow_ids, ';', 1);
    v_action := case when c.outcome = 'REFUND_APPROVAL' then 'refund_decision'
                     else coalesce((select authority_class from public.phase_c_component
                                    where workflow_id = btrim(v_wf) limit 1),
                                   'routine_operational_decision') end;
    -- A non-refund routine action may never carry the refund action class.
    if v_action = 'refund_decision' and c.outcome <> 'REFUND_APPROVAL' then
      v_action := 'routine_operational_decision';
    end if;

    insert into public.phase_c_task (
      source_kind, source_ref, command_id, workflow_id, accountable_role_id, manager_role_id,
      department_id, objective, requested_output, acceptance_criteria, closure_criteria,
      priority, due_at, authority_class, idempotency_key, state)
    values ('founder_command', 'CMD-' || v_cmd, v_cmd,
            nullif(btrim(split_part(c.workflow_ids, ';', 1)), ''), v_owner,
            coalesce(v_manager, ''), coalesce(v_dept, ''),
            left(coalesce(p_text, ''), 2000),
            'Evidence-backed outcome for the founder instruction, with the decision and its basis recorded.',
            'Requested outcome delivered with evidence, within policy, authority and gates.',
            'Independent review passed where required and the closure criteria of the bound workflow are met.',
            c.priority, v_due, v_action,
            'cmd:' || v_cmd || ':primary', 'queued')
    returning task_id into v_task;
    if v_task is null then
      raise exception 'command %: primary task insert produced no row', v_cmd using errcode = '23502';
    end if;
    insert into public.founder_command_task_link (command_id, task_id) values (v_cmd, v_task);
    v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
  end if;

  -- Child tasks: one per named contributing role, each with its own exact owner.
  for v_child in select btrim(x) from unnest(string_to_array(c.child_role_ids, ';')) x where btrim(x) <> '' loop
    select role_id into v_owner from public.fn_phase_c_resolve_actor(v_child);
    continue when v_owner is null;
    select r.manager_role_id, r.primary_department_id into v_manager, v_dept
      from public.org_role r where r.role_id = v_owner;
    insert into public.phase_c_task (
      source_kind, source_ref, command_id, workflow_id, accountable_role_id, manager_role_id,
      department_id, objective, requested_output, acceptance_criteria, closure_criteria,
      priority, due_at, authority_class, idempotency_key, state)
    values ('founder_command', 'CMD-' || v_cmd, v_cmd,
            nullif(btrim(split_part(c.workflow_ids, ';', 1)), ''), v_owner,
            coalesce(v_manager, ''), coalesce(v_dept, ''),
            left(coalesce(p_text, ''), 2000),
            'Contribution required by the command plan for ' || v_child,
            'Contribution delivered with evidence to the command owner.',
            'Accepted by the primary owner or returned with a specific reason.',
            c.priority, v_due, 'routine_operational_decision',
            'cmd:' || v_cmd || ':child:' || v_owner, 'queued')
    on conflict (idempotency_key) do nothing
    returning task_id into v_task;
    if v_task is not null then
      insert into public.founder_command_task_link (command_id, task_id) values (v_cmd, v_task);
      v_tasks := v_tasks || v_task; v_owners := v_owners || v_owner;
    end if;
  end loop;

  insert into public.founder_command_plan (command_id, summary, child_task_count, departments)
  values (v_cmd,
          format('%s: %s. Command owner chief_of_staff; %s task(s) created against %s.',
                 c.intent_id, c.outcome, cardinality(v_tasks), coalesce(nullif(c.workflow_ids,''), 'no workflow')),
          cardinality(v_tasks),
          coalesce((select string_agg(distinct t.department_id, '; ')
                    from public.phase_c_task t where t.command_id = v_cmd and t.department_id <> ''), ''))
  returning plan_id into v_plan_id;

  -- The refund path.  Only here, and only for a specific case, may a founder approval exist.
  if c.outcome = 'REFUND_APPROVAL' then
    insert into public.founder_approval_request
      (command_id, action_class, subject_ref, prepared_by_role_id, amount_note, evidence, state)
    values (v_cmd, 'refund_decision',
            coalesce((regexp_match(p_text, '(TX-[A-Za-z0-9_-]+)'))[1], 'UNIDENTIFIED_TRANSACTION'),
            'payments_and_billing_manager',
            'amount, reason, customer/supplier impact and fraud checks required before decision',
            jsonb_build_object('raw_command', left(coalesce(p_text,''), 500)), 'pending');
  end if;

  -- The event, written in the SAME transaction as the work it describes.
  perform public.fn_phase_c_outbox_emit(
    'EV-W01-STARTED', 'system.command_router',
    jsonb_build_object('command_id', v_cmd, 'intent', c.intent_id, 'tasks', to_jsonb(v_tasks)),
    'founder_command:' || v_cmd)
  where exists (select 1 from public.phase_b_event where event_id = 'EV-W01-STARTED');

  update public.founder_command set state = 'tasks_created', due_at = v_due where command_id = v_cmd;

  return jsonb_build_object(
    'ok', true, 'command_id', v_cmd, 'status', 'tasks_created', 'intent', c.intent_id,
    'outcome', c.outcome, 'interpretation', c.reason,
    'workflow_ids', coalesce((select jsonb_agg(workflow_id order by workflow_id)
                              from public.founder_command_workflow_link where command_id = v_cmd), '[]'::jsonb),
    'task_ids', to_jsonb(v_tasks),
    'owner', 'chief_of_staff', 'primary_owner', coalesce(v_owners[1], 'founder'),
    'child_owners', to_jsonb(v_owners[2:]),
    'tasks_created', cardinality(v_tasks),
    'priority', c.priority, 'due_at', v_due,
    'founder_approval_required', (c.outcome = 'REFUND_APPROVAL'),
    'founder_initiated_only', (c.outcome in ('FOUNDER_INITIATED_POLICY_CHANGE','FOUNDER_INITIATED_PHASE_A_CHANGE')),
    'plan_id', v_plan_id, 'trace_id', v_trace);
end $$;
revoke all on function public.fn_founder_command_submit(text, text, text, jsonb) from public;
grant execute on function public.fn_founder_command_submit(text, text, text, jsonb) to service_role;

-- ============================================================ 5. status, cancel, explain
create or replace function public.fn_founder_command_status(p_ref text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare v_id bigint; r jsonb;
begin
  v_id := nullif(regexp_replace(coalesce(p_ref,''), '\D', '', 'g'), '')::bigint;
  if v_id is null then
    return jsonb_build_object('ok', false, 'error','identifier_required',
      'message','Give me a command id or a task id and I will read its current state.');
  end if;
  select jsonb_build_object(
    'ok', true, 'command_id', c.command_id, 'status', c.state, 'intent', c.intent_id,
    'outcome', c.outcome, 'owner', c.command_owner_role_id, 'priority', c.priority,
    'due_at', c.due_at, 'raw_text', m.raw_text,
    'workflow_ids', coalesce((select jsonb_agg(l.workflow_id order by l.workflow_id)
                              from public.founder_command_workflow_link l where l.command_id = c.command_id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
                          'task_id', t.task_id, 'owner', t.accountable_role_id,
                          'department', t.department_id, 'state', t.state,
                          'blocker', t.blocker, 'due_at', t.due_at) order by t.task_id)
                       from public.phase_c_task t where t.command_id = c.command_id), '[]'::jsonb),
    'clarification', (select cl.question from public.founder_command_clarification cl
                      where cl.command_id = c.command_id order by cl.clarification_id desc limit 1),
    'trace_id', c.trace_id)
  into r
  from public.founder_command c join public.founder_command_message m on m.message_id = c.message_id
  where c.command_id = v_id;
  return coalesce(r, jsonb_build_object('ok', false, 'error','not_found', 'ref', p_ref));
end $$;
revoke all on function public.fn_founder_command_status(text) from public;
grant execute on function public.fn_founder_command_status(text) to service_role;

create or replace function public.fn_founder_command_control(
  p_command_id bigint, p_op text, p_target text, p_value text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_target bigint; v_state text; v_n bigint;
begin
  v_target := nullif(regexp_replace(coalesce(p_target,''), '\D', '', 'g'), '')::bigint;
  if v_target is null then
    return jsonb_build_object('ok', false, 'error','identifier_required');
  end if;
  select state into v_state from public.founder_command where command_id = v_target;
  if v_state is null then return jsonb_build_object('ok', false, 'error','not_found'); end if;

  if p_op = 'cancel' then
    if not exists (select 1 from public.phase_c_command_transition
                   where from_state = v_state and to_state = 'cancelled') then
      return jsonb_build_object('ok', false, 'error','transition_not_permitted',
        'from', v_state, 'to','cancelled',
        'message', format('A command in %L cannot be cancelled; the state model does not allow it.', v_state));
    end if;
    update public.founder_command set state = 'cancelled', closed_at = now() where command_id = v_target;
    update public.phase_c_task set state = 'cancelled', closed_at = now()
      where command_id = v_target and state in ('queued','assigned','accepted','in_progress','blocked');
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'command_id', v_target, 'status','cancelled',
                              'child_tasks_cancelled', v_n);
  elsif p_op = 'reprioritize' then
    if coalesce(p_value,'') !~ '^P[0-3]$' then
      return jsonb_build_object('ok', false, 'error','priority_required', 'allowed','P0..P3');
    end if;
    update public.founder_command set priority = p_value where command_id = v_target;
    update public.phase_c_task set priority = p_value where command_id = v_target and closed_at is null;
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'command_id', v_target, 'priority', p_value, 'tasks_updated', v_n);
  elsif p_op = 'supersede' then
    if not exists (select 1 from public.phase_c_command_transition
                   where from_state = v_state and to_state = 'superseded') then
      return jsonb_build_object('ok', false, 'error','transition_not_permitted', 'from', v_state);
    end if;
    update public.founder_command set state = 'superseded', superseded_by = p_command_id,
                                      closed_at = now() where command_id = v_target;
    update public.phase_c_task set state = 'superseded', closed_at = now()
      where command_id = v_target and state in ('queued','assigned','accepted','in_progress','blocked');
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'command_id', v_target, 'status','superseded',
                              'superseded_by', p_command_id, 'child_tasks_superseded', v_n);
  elsif p_op = 'explain' then
    return jsonb_build_object('ok', true, 'command_id', v_target,
      'explanation', coalesce((select i.reason from public.founder_command_interpretation i
                               where i.command_id = v_target order by i.version desc limit 1),
                              'no interpretation recorded'),
      'traces', coalesce((select jsonb_agg(jsonb_build_object(
                              'trace_id', tr.trace_id, 'policy', tr.trace_policy_id,
                              'subject', tr.subject_kind, 'status', tr.status) order by tr.trace_id)
                          from public.phase_c_trace tr where tr.command_id = v_target), '[]'::jsonb),
      'plan', (select p.summary from public.founder_command_plan p where p.command_id = v_target));
  end if;
  return jsonb_build_object('ok', false, 'error','unknown_control_operation', 'op', p_op);
end $$;
revoke all on function public.fn_founder_command_control(bigint, text, text, text) from public;
grant execute on function public.fn_founder_command_control(bigint, text, text, text) to service_role;
