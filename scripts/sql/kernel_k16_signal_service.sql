-- K16 — a signal about a run that already exists must not start a second one.
--
-- K10 built the request door: fn_kernel_trigger_submit takes a NEW work request, normalizes it to
-- a registered trigger type, resolves one canonical Phase B workflow and one business object,
-- writes kernel_trigger_inbox, and starts work ONLY through fn_kernel_workflow_start. That door is
-- correct and this file does not touch it.
--
-- It is also the only door. Which means everything that is NOT a new request — a clarification
-- answered, a supplier revising a quote inside a live RFQ, a document arriving for an inquiry that
-- is already being worked, an internal review verdict, a follow-up, a deadline, an SLA breach, a
-- retry falling due, a provider calling back about a payment already in flight — has, today, only
-- two options: pretend to be a new request, or bypass the kernel. The first creates a duplicate
-- workflow. The second is what the whole rebuild exists to end.
--
-- So this file builds the second door.
--
--   fn_kernel_signal_submit(p_input jsonb)
--     source_type, source_id, workflow_run_id, signal_type, payload, idempotency_key
--
-- It refuses to create a workflow run. Not "does not"; CANNOT — it never calls
-- fn_kernel_workflow_start, and fn_kernel_signal_state asserts that its body does not name it.
--
-- WHAT A SIGNAL MAY DO, and nothing else. Every signal type declares one disposition, in
-- kernel_signal_type, and the disposition is what the kernel is allowed to do about it:
--
--   ATTACH_ONLY     record the signal against the run and its trace. No state moves. This is the
--                   honest default for a signal that is evidence rather than a decision.
--   COMPLETE_STEP   drive fn_kernel_step_complete for the run's currently active step — and only
--                   if the payload carries a real `output` object. A signal that cannot supply an
--                   output does not get one invented; it is refused.
--   REVIEW_VERDICT  drive fn_kernel_review_decide with the verdict in the payload.
--   CANCEL          drive fn_kernel_cancel.
--
-- There is no disposition that creates a task out of nothing. §4 asks for "a corrective/internal
-- task only when the frozen workflow requires it" — and the frozen workflow requires it through
-- fn_kernel_step_complete, which opens the successor the registry declares. Adding a second way to
-- mint a task would be exactly the parallel path this rebuild is retiring.
--
-- WHAT IT REFUSES, with the refusal RECORDED rather than raised wherever a row can hold it:
--   * a workflow_run_id that does not exist
--   * a run that is not active (terminal runs do not accept signals)
--   * a signal_type that is not registered, or registered inactive
--   * a signal_type whose declared workflow does not match the run's workflow
--   * COMPLETE_STEP with no active step, or with no usable output in the payload
--   * a repeated idempotency key — the first decision is returned, and nothing happens twice
--
-- Rollback: scripts/sql/rollback/kernel_k16_signal_service.rollback.sql

begin;

-- ------------------------------------------------------------------ 1. the signal vocabulary
create table if not exists public.kernel_signal_type (
  signal_type      text primary key,
  disposition      text not null,
  workflow_id      text references public.phase_b_workflow(workflow_id),
  meaning          text not null,
  allowed_source_systems text[] not null default '{}',
  system_actor_id  text not null,
  activation_state text not null default 'inactive',
  registered_at    timestamptz not null default now(),
  constraint kernel_signal_disposition_known
    check (disposition in ('ATTACH_ONLY','COMPLETE_STEP','REVIEW_VERDICT','CANCEL')),
  constraint kernel_signal_activation_known
    check (activation_state in ('active','inactive'))
);

comment on table public.kernel_signal_type is
  'K16. The registered vocabulary of signals about a workflow run that ALREADY EXISTS. Every row '
  'declares one disposition — the only thing the kernel may do when that signal arrives. A signal '
  'type is not a trigger type: a trigger starts a workflow, a signal may never start one.';

-- ------------------------------------------------------------------ 2. the signal ledger
create table if not exists public.kernel_signal_inbox (
  signal_id        bigserial primary key,
  source_type      text not null,
  source_id        text not null,
  workflow_run_id  bigint,
  signal_type      text not null,
  payload          jsonb not null default '{}'::jsonb,
  idempotency_key  text not null unique,
  correlation_id   text,
  causation_id     text,
  received_at      timestamptz not null default now(),
  status           text not null default 'received',
  refusal_reason   text,
  step_run_id      bigint,
  trace_id         bigint,
  result           jsonb,
  processed_at     timestamptz,
  requested_by     text not null,
  constraint kernel_signal_status_known
    check (status in ('received','attached','applied','refused')),
  constraint kernel_signal_refusal_has_a_reason
    check (status <> 'refused' or coalesce(btrim(refusal_reason),'') <> '')
);

create index if not exists kernel_signal_inbox_run on public.kernel_signal_inbox (workflow_run_id);

comment on table public.kernel_signal_inbox is
  'K16. Every signal about an existing run, including the ones refused. A refused signal is a row '
  'with a reason, not a silence: "the run was already closed" and "nothing ever arrived" must never '
  'look the same. The source record is preserved verbatim in payload.';

alter table public.kernel_signal_type  enable row level security;
alter table public.kernel_signal_inbox enable row level security;
revoke all on public.kernel_signal_type  from public, anon, authenticated;
revoke all on public.kernel_signal_inbox from public, anon, authenticated;
grant select on public.kernel_signal_type  to service_role;
grant select on public.kernel_signal_inbox to service_role;

-- ------------------------------------------------------------------ 3. the service
create or replace function public.fn_kernel_signal_submit(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $k16_signal$
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
  v_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
    'subject_kind','system_execution', 'subject_ref', 'signal:' || v_id::text, 'run_id', v_run,
    'actor_role_id', null, 'system_actor_id', v_sig_sys,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'signal_id', v_id, 'signal_type', v_sig, 'disposition', v_disp,
      'source_type', v_src_type, 'source_id', v_src_id, 'idempotency_key', v_idem)),
    'state_before', v_run_state, 'state_after', v_run_state, 'status','complete'));
  update public.kernel_signal_inbox set trace_id = v_trace where signal_id = v_id;
  if v_run_trace is not null then
    update public.phase_c_trace set parent_trace_id = v_run_trace where trace_id = v_trace;
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
$k16_signal$;

revoke all on function public.fn_kernel_signal_submit(jsonb) from public, anon, authenticated;
grant execute on function public.fn_kernel_signal_submit(jsonb) to service_role;

comment on function public.fn_kernel_signal_submit(jsonb) is
  'K16. The canonical door for a signal about a workflow run that ALREADY EXISTS: clarification '
  'answered, quote revised, document arrived, review returned, follow-up, deadline, SLA breach, '
  'retry due, provider callback. It attaches the signal to the named run and applies exactly the '
  'disposition its signal type declares. It never calls fn_kernel_workflow_start and therefore '
  'cannot create a second workflow. Refusals are recorded as rows with reasons, never as silence.';

-- ------------------------------------------------------------------ 4. the invariant board
create or replace function public.fn_kernel_signal_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $k16_state$
with
-- The predicate is live: it reads the deployed body, comments stripped, so this check cannot be
-- satisfied by a promise in a comment. Comments are stripped because the body says in prose that
-- it must never call fn_kernel_workflow_start.
body as (
  select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g') src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_kernel_signal_submit'
),
sig as (select * from public.kernel_signal_inbox),
runs_from_signals as (
  -- A workflow run whose dedupe_key or trace descends from a signal would be the defect this file
  -- exists to prevent. Measured against the ledger, not against intent.
  select count(*) n from public.phase_c_workflow_run r
   where exists (select 1 from sig s where s.correlation_id = 'signal:' || s.idempotency_key
                   and r.dedupe_key like '%' || s.source_id || '%'
                   and r.opened_at >= s.received_at)
)
select 'signal_service_can_create_a_workflow'::text,
       '0 — the body must not name fn_kernel_workflow_start',
       (select case when src ~ '\yfn_kernel_workflow_start\s*\(' then '1 — IT DOES' else '0' end
          from body),
       (select src !~ '\yfn_kernel_workflow_start\s*\(' from body)
union all
select 'signal_types_registered',
       'reported, not asserted',
       (select count(*)::text || ' registered, '
            || count(*) filter (where activation_state = 'active')::text || ' active, dispositions: '
            || coalesce(string_agg(distinct disposition, ', '), '(none)')
          from public.kernel_signal_type),
       true
union all
select 'signals_that_created_a_workflow_run',
       '0',
       (select n::text from runs_from_signals),
       (select n = 0 from runs_from_signals)
union all
select 'refused_signals_with_no_stated_reason',
       '0 of ' || (select count(*)::text from sig where status = 'refused'),
       (select count(*)::text from sig
         where status = 'refused' and coalesce(btrim(refusal_reason),'') = '')
         || ' of ' || (select count(*)::text from sig where status = 'refused'),
       (select count(*) = 0 from sig where status = 'refused' and coalesce(btrim(refusal_reason),'') = '')
union all
select 'signals_attached_to_a_run_that_does_not_exist',
       '0 of ' || (select count(*)::text from sig where status <> 'refused'),
       (select count(*)::text from sig s where s.status <> 'refused'
          and not exists (select 1 from public.phase_c_workflow_run r where r.run_id = s.workflow_run_id))
         || ' of ' || (select count(*)::text from sig where status <> 'refused'),
       (select count(*) = 0 from sig s where s.status <> 'refused'
          and not exists (select 1 from public.phase_c_workflow_run r where r.run_id = s.workflow_run_id))
union all
select 'signals_processed_without_a_trace',
       '0 of ' || (select count(*)::text from sig where status in ('attached','applied')),
       (select count(*)::text from sig where status in ('attached','applied') and trace_id is null)
         || ' of ' || (select count(*)::text from sig where status in ('attached','applied')),
       (select count(*) = 0 from sig where status in ('attached','applied') and trace_id is null)
union all
select 'duplicate_signal_delivery_applied_twice',
       '0',
       -- idempotency_key is UNIQUE, so this counts what the constraint already makes impossible.
       -- It stays because a future ALTER that drops the constraint must fail a check, not pass
       -- silently.
       (select count(*)::text from (
          select idempotency_key from sig group by idempotency_key having count(*) > 1) d),
       (select count(*) = 0 from (
          select idempotency_key from sig group by idempotency_key having count(*) > 1) d);
$k16_state$;

revoke all on function public.fn_kernel_signal_state() from public, anon, authenticated;
grant execute on function public.fn_kernel_signal_state() to service_role;

comment on function public.fn_kernel_signal_state() is
  'K16 invariants. The first line reads the DEPLOYED body of fn_kernel_signal_submit with comments '
  'stripped and fails if it names fn_kernel_workflow_start: "the signal service cannot start a '
  'workflow" is measured, not promised.';

commit;

-- ------------------------------------------------------------------ 5. the registered signals
--
-- One row per kind of thing the founder's §4 list names. Each declares the ONE disposition the
-- kernel may apply. `workflow_id` is left NULL where the signal is legitimately workflow-agnostic
-- (a deadline or an SLA breach can fall due on any run); where it is set, a signal addressed to a
-- run of a different workflow is refused rather than applied to the wrong contract.
--
-- Every row lands `inactive`. An adapter existing is not a reason to switch a source on — that is
-- the founder's rule, and the cutover increments activate each type as its source actually moves.
begin;

insert into public.kernel_signal_type
  (signal_type, disposition, workflow_id, meaning, system_actor_id, activation_state)
values
  ('clarification.response', 'COMPLETE_STEP', null,
   'A customer or supplier has answered a clarification the run was waiting on. It completes the '
   'waiting step when the payload carries the answer as an output; it is refused if it does not, '
   'because an empty answer is not an answer.',
   'system.webhook_receiver', 'inactive'),
  ('supplier.quote_revision', 'COMPLETE_STEP', 'W14',
   'A supplier has revised a quotation inside a live W14 run. This is NOT a new quotation: W14-S03 '
   'Receive quotation revision is the step that exists for it, and starting a second W14 for the '
   'same quote would double the evaluation.',
   'system.webhook_receiver', 'inactive'),
  ('document.arrived_for_run', 'ATTACH_ONLY', null,
   'A document has arrived for an inquiry that is already being worked. It is evidence on the run, '
   'not a new intake: W07 already owns the document workflow for a NEW document, and a second run '
   'for a file attached to live work is a duplicate.',
   'system.storage_trigger', 'inactive'),
  ('review.verdict', 'REVIEW_VERDICT', null,
   'An internal reviewer has returned a verdict on the task of the run''s active step. Recorded '
   'through fn_kernel_review_decide, which is where reviewer independence is enforced.',
   'system.task_engine', 'inactive'),
  ('followup.due', 'ATTACH_ONLY', null,
   'A scheduled follow-up on an existing run has fallen due. It records that the moment arrived. '
   'It does not complete a step: whether the follow-up produced anything is a separate fact, and '
   'inferring it from the clock is how a queue drains itself.',
   'system.scheduler', 'inactive'),
  ('deadline.due', 'ATTACH_ONLY', null,
   'A deadline on an existing run has been reached. Attached to the run so the breach is on its '
   'trace at the moment it happened.',
   'system.scheduler', 'inactive'),
  ('sla.breach', 'ATTACH_ONLY', null,
   'An SLA on an existing run has been breached. §4: an SLA signal belongs here, not in the '
   'new-work trigger inbox — a breach is a fact about work already in flight, and routing it to '
   'the trigger inbox would open a second run for the same object.',
   'system.health_monitor', 'inactive'),
  ('retry.due', 'ATTACH_ONLY', null,
   'A retry on an existing run has fallen due. The retry itself is executed by whatever owns the '
   'step; this records that it became eligible.',
   'system.scheduler', 'inactive'),
  ('provider.callback', 'ATTACH_ONLY', null,
   'A payment or messaging provider has called back about an object already inside a run — a '
   'confirmation, a receipt, a delivery status. The NEW payment event that opens W16 is a trigger '
   'type, not this; these two must not be confused, which is why they live in different tables.',
   'system.provider_adapter', 'inactive'),
  ('run.cancellation_requested', 'CANCEL', null,
   'A source has asked for a live run to be cancelled. Applied through fn_kernel_cancel so the '
   'cancellation propagates to every step run, task, handoff and queued outbox row beneath it.',
   'system.command_router', 'inactive')
on conflict (signal_type) do update set
  disposition = excluded.disposition, workflow_id = excluded.workflow_id,
  meaning = excluded.meaning, system_actor_id = excluded.system_actor_id;

commit;
