-- ============================================================================================
-- KERNEL S3 — SYSTEM-EXECUTION TRACE COVERAGE
--
-- "Every scheduled, webhook, queue, storage and provider-adapter execution that may mutate or
--  deliver state carries a trace." TRACE-SYSTEM-EXECUTION says trace_required = YES and
--  completed_without_trace_allowed = NO.
--
-- MEASURED ON THE ONE PROJECT, 2026-08-17, AND REPRODUCED BY THE FUNCTIONS BELOW
--
--   656 components are scoped to TRACE-SYSTEM-EXECUTION. 609 of them are recorded as
--   state-changing. The number of traces ever written under that policy is ZERO:
--
--     select count(*) from public.phase_c_trace where trace_policy_id = 'TRACE-SYSTEM-EXECUTION';
--     -> 0        (80 traces exist in total: 49 TASK, 10 WORKFLOW, 9 STEP, 9 FOUNDER-COMMAND,
--                  3 HANDOFF)
--
--   The estate has therefore been executing scheduled work for a month with no record that the
--   policy governing it says is mandatory. cron.job_run_details holds 191,129 completed runs
--   between 2026-07-19 and 2026-08-16 and not one of them produced a trace.
--
-- WHAT THIS FILE DOES NOT DO, DELIBERATELY
--
--   It does NOT backfill history. Writing 191,129 trace rows now, dated now, would assert that
--   those executions were traced when they ran. They were not. Every historical execution stays
--   untraced and is REPORTED as historical by fn_kernel_system_trace_state, on its own line, with
--   its own number. A ledger that fabricates its own past is worse than an empty one.
--
--   It does NOT activate anything. Every cron job that is switched off stays switched off. The
--   only cron mutation here is a command rewrite on jobs that are already active = true.
--
--   It does NOT change phase_c_component.mutates_state. Section 5 records nine components whose
--   recorded mutates_state = false disagrees with their own source; they are left ON
--   TRACE-SYSTEM-EXECUTION (the safe side) and disclosed, because flipping the flag would move
--   K11's exposure invariant, which is a different increment's subject.
--
-- THE FOUR THINGS IT BUILDS
--
--   A. fn_kernel_system_execution_trace(jsonb) — the complete writer. It REFUSES, 23514, with a
--      message naming the field, a trace that cannot say who executed, under whose accountability,
--      in what scope, on whose trigger, with what authority, from what state to what state, with
--      what result, correlated to what, between which two instants. A record missing any of those
--      is not a system-execution trace and this function will not pretend it is one.
--
--   B. The exemption AND its limit. Read-only infrastructure may sit on TRACE-MONITORING or
--      TRACE-INFRASTRUCTURE with a documented exemption recorded against the component in
--      phase_c_component_trace_exemption. fn_phase_c_readonly_exemption_guard refuses two things:
--      a state-changing component moved to a read-only policy, and any component moved to a
--      read-only policy without a recorded exemption. 23 of the 656 move; 633 stay; all 609
--      state-changing components stay. See section 5 for the evidence, one row at a time.
--
--   C. The wiring. fn_kernel_cron_exec is ONE shared wrapper, not 22 copies. Every cron job that
--      is active AND state-changing AND on TRACE-SYSTEM-EXECUTION has its command replaced by
--      `select public.fn_kernel_cron_exec(<jobid>)`; the original command is stored verbatim in
--      phase_c_system_execution_wrapper and executed by the wrapper. From the first firing after
--      apply, every one of those executions writes a complete trace.
--
--   D. fn_kernel_system_trace_state — numerator and denominator on every line, NEW split from
--      HISTORICAL by phase_c_kernel_epoch.started_at, a stored instant that no DML can move. Never
--      by max(): an anchor that follows the newest row goes green over whatever it just stepped
--      past.
--
-- ONE THING MOVES OUT OF K6, AND WHY (section 8)
--   fn_kernel_trace_integrity maps a trace's subject_kind through a CASE whose else-branch is
--   'unmapped', and asserts that no trace is unmapped. The first system-execution trace written
--   would have turned that check red — truthfully, because K6's integrity function does not know
--   the kind. The fix is one CASE branch and one orphan line. Rather than leave a second copy of
--   the routine in a second file (`sql_files_match_live` resolves a tie by commit time and would
--   then certify whichever body happened to be newest), the DEFINITION MOVES HERE and
--   kernel_k6_trace_ledger.sql keeps a pointer where it used to be. One routine, one file.
-- ============================================================================================

begin;

-- ------------------------------------------------------------------ 1. the kernel epoch
--
-- NEW versus HISTORICAL has to be decided by an instant that is fixed when this file applies and
-- cannot be moved afterwards. `max(created_at)` and `min(updated_at)` have both been used as
-- anchors in this repository and both had the same failure: writing a row moved the window, so the
-- check went green over exactly the period it had just stepped across. This row is written once
-- and a trigger refuses every UPDATE and every DELETE against it.
create table if not exists public.phase_c_kernel_epoch (
  epoch_id   text primary key,
  started_at timestamptz not null default now(),
  reason     text not null,
  constraint phase_c_kernel_epoch_reason_ck check (length(reason) >= 20)
);

comment on table public.phase_c_kernel_epoch is
  'S3. Fixed instants that split NEW from HISTORICAL. Written once, never moved: '
  'z10_phase_c_kernel_epoch_immutable refuses UPDATE and DELETE. A check anchored to max() or '
  'min() of a live table is anchored to nothing.';

alter table public.phase_c_kernel_epoch enable row level security;
revoke all on public.phase_c_kernel_epoch from public;
grant select, insert on public.phase_c_kernel_epoch to service_role;

create or replace function public.fn_phase_c_kernel_epoch_immutable()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $s3_epoch$
begin
  raise exception
    'phase_c_kernel_epoch is append-only: % on epoch % refused. The instant that separates new '
    'work from historical work is not allowed to move — a window that follows its own newest row '
    'reports green over the period it just stepped across.',
    tg_op, coalesce(old.epoch_id, new.epoch_id)
    using errcode = '23514';
end
$s3_epoch$;

revoke all on function public.fn_phase_c_kernel_epoch_immutable() from public;
grant execute on function public.fn_phase_c_kernel_epoch_immutable() to service_role;

drop trigger if exists z10_phase_c_kernel_epoch_immutable on public.phase_c_kernel_epoch;
create trigger z10_phase_c_kernel_epoch_immutable
  before update or delete on public.phase_c_kernel_epoch
  for each row execute function public.fn_phase_c_kernel_epoch_immutable();

insert into public.phase_c_kernel_epoch (epoch_id, reason) values
  ('S3_SYSTEM_EXECUTION_TRACING',
   'The instant fn_kernel_cron_exec became the command of every active state-changing cron job. '
   'Executions at or after it are NEW and must carry a complete system-execution trace; '
   'executions before it are HISTORICAL, were never traced, and are reported as historical.')
on conflict (epoch_id) do nothing;

-- ------------------------------------------------------------------ 2. the execution record
--
-- phase_c_trace already carries component_id, system_actor_id, actor_role_id, authority_result,
-- state_before, state_after, input_hash, output_hash and status. It does not carry the other eight
-- fields a system execution has to state, and widening a table five other policies share to serve
-- one of them is the wrong shape. One narrow child row per trace holds them, and the NOT NULLs and
-- CHECKs here are the second line of defence behind the named refusals in section 3.
create table if not exists public.phase_c_system_execution (
  trace_id           bigint primary key references public.phase_c_trace(trace_id) on delete cascade,
  component_id       text        not null references public.phase_c_component(component_id),
  system_actor       text        not null references public.phase_c_system_actor(system_actor_id),
  accountable_role_id text       not null references public.org_role(role_id),
  workflow_id        text        null,
  step_id            text        null,
  technical_scope    text        null,
  trigger_source     text        not null,
  authority_result   text        not null,
  state_before       text        not null,
  state_after        text        not null,
  result             text        not null,
  failure            text        null,
  correlation_id     text        not null,
  causation_id       text        not null,
  started_at         timestamptz not null,
  finished_at        timestamptz not null,
  recorded_at        timestamptz not null default now(),
  constraint phase_c_system_execution_result_ck
    check (result = any (array['succeeded','failed','refused','no_op'])),
  -- workflow/step OR a justified technical scope. Never neither: three of the twenty-two active
  -- cron components carry workflow_id OUT_OF_SCOPE or SYSTEM_SCOPE and no step, and "no scope" is
  -- not an answer a trace may give.
  constraint phase_c_system_execution_scope_ck
    check ((coalesce(workflow_id,'') <> '') or (length(coalesce(technical_scope,'')) >= 20)),
  -- a failed execution must say why; a succeeded one must not carry a failure string
  constraint phase_c_system_execution_failure_ck
    check ((result = 'failed') = (coalesce(failure,'') <> '')),
  constraint phase_c_system_execution_window_ck check (finished_at >= started_at),
  constraint phase_c_system_execution_nonempty_ck
    check (trigger_source <> '' and authority_result <> '' and state_before <> ''
           and state_after <> '' and correlation_id <> '' and causation_id <> '')
);

create index if not exists phase_c_system_execution_component_started_idx
  on public.phase_c_system_execution (component_id, started_at);

comment on table public.phase_c_system_execution is
  'S3. The eight fields a system execution must state that phase_c_trace has no column for, plus '
  'the resolved identities. One row per TRACE-SYSTEM-EXECUTION trace. Append-only.';

alter table public.phase_c_system_execution enable row level security;
revoke all on public.phase_c_system_execution from public;
grant select, insert on public.phase_c_system_execution to service_role;

create or replace function public.fn_phase_c_system_execution_append_only()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $s3_append$
begin
  raise exception
    'phase_c_system_execution is append-only: % on trace % refused. An execution record that can '
    'be edited after the fact records the editor, not the execution.',
    tg_op, coalesce(old.trace_id, new.trace_id)
    using errcode = '23514';
end
$s3_append$;

revoke all on function public.fn_phase_c_system_execution_append_only() from public;
grant execute on function public.fn_phase_c_system_execution_append_only() to service_role;

drop trigger if exists z10_phase_c_system_execution_append_only on public.phase_c_system_execution;
create trigger z10_phase_c_system_execution_append_only
  before update or delete on public.phase_c_system_execution
  for each row execute function public.fn_phase_c_system_execution_append_only();

-- ------------------------------------------------------------------ 3. (A) the writer
--
-- Compact but COMPLETE. Fourteen field classes, each with its own refusal and its own message. The
-- point is not validation for its own sake: a trace that cannot say which role is accountable, or
-- what the authority result was, or what changed, is indistinguishable from a log line, and a log
-- line is what TRACE-SYSTEM-EXECUTION exists to stop being the answer.
--
-- 'failure' is nullable but must be PRESENT as a key. A caller that omits it has not told us the
-- execution did not fail; it has told us nothing, and those are different.
create or replace function public.fn_kernel_system_execution_trace(p_input jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $s3_write$
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
  foreach k in array array['component_id','system_actor','accountable_role_id','trigger_source',
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

  -- ---- class 5: the accountable role must be a canonical role ------------------------------
  if not exists (select 1 from public.org_role
                  where role_id = p_input->>'accountable_role_id') then
    raise exception
      'TRACE-SYSTEM-EXECUTION incomplete: accountable role "%" does not resolve in org_role. '
      'A system execution with no accountable human-or-agent role is an action nobody owns.',
      p_input->>'accountable_role_id'
      using errcode = '23514';
  end if;

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
$s3_write$;

revoke all on function public.fn_kernel_system_execution_trace(jsonb) from public;
grant execute on function public.fn_kernel_system_execution_trace(jsonb) to service_role;

comment on function public.fn_kernel_system_execution_trace(jsonb) is
  'S3 (A). The only writer of TRACE-SYSTEM-EXECUTION. Refuses, 23514, with the field named, a '
  'trace missing component, system actor, accountable canonical role, workflow/step or a '
  'justified technical scope, trigger source, authority result, state_before, state_after, '
  'result, the failure field, correlation_id, causation_id, started_at or finished_at.';

-- ------------------------------------------------------------------ 4. (B) the exemption + limit
--
-- TRACE-INFRASTRUCTURE says in its own scope column: "Infrastructure-only execution that changes
-- no business state and produces no official output", minimum fields "component_id;
-- reason_for_exemption", completed_without_trace_allowed "YES_WITH_DOCUMENTED_REASON". The
-- document has always been required. There was nowhere to put it. This is the somewhere.
create table if not exists public.phase_c_component_trace_exemption (
  component_id       text primary key references public.phase_c_component(component_id) on delete cascade,
  exempt_to_policy   text        not null references public.phase_c_trace_policy(trace_policy_id),
  reason             text        not null,
  source_measurement text        not null,
  k11_derivation     text        not null,
  recorded_at        timestamptz not null default now(),
  recorded_by        text        not null default 'kernel:s3',
  constraint phase_c_component_trace_exemption_policy_ck
    check (exempt_to_policy = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE'])),
  constraint phase_c_component_trace_exemption_reason_ck check (length(reason) >= 30),
  constraint phase_c_component_trace_exemption_evidence_ck
    check (source_measurement <> '' and k11_derivation <> '')
);

comment on table public.phase_c_component_trace_exemption is
  'S3 (B). The documented reason a component was moved off TRACE-SYSTEM-EXECUTION onto a '
  'read-only policy, with the source measurement that decided it and the K11 derivation verbatim '
  '— including where the derivation had no measurement to offer. No exemption row, no move: '
  'a00_phase_c_readonly_exemption_guard refuses it.';

alter table public.phase_c_component_trace_exemption enable row level security;
revoke all on public.phase_c_component_trace_exemption from public;
grant select, insert, update, delete on public.phase_c_component_trace_exemption to service_role;

-- THE LIMIT. Two refusals, both of which can fire and both of which are proved in the rehearsal:
--   * a component that changes business state may never sit on a read-only policy, exemption or
--     no exemption. There is no documented reason that makes an untraced state change acceptable.
--   * a component may not sit on a read-only policy without a recorded exemption at all.
-- Firing on UPDATE OF mutates_state as well as trace_policy_id closes the back door: a component
-- cannot be moved to TRACE-INFRASTRUCTURE while read-only and then quietly become state-changing.
create or replace function public.fn_phase_c_readonly_exemption_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $s3_guard$
begin
  if new.trace_policy_id <> all (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE']) then
    return new;
  end if;

  if new.mutates_state then
    raise exception
      'phase_c_component %: mutates_state is true and trace_policy_id is "%". A component that '
      'changes business state may not use the read-only exemption. TRACE-INFRASTRUCTURE is scoped '
      'to "execution that changes no business state and produces no official output" and '
      'TRACE-MONITORING to "read-only health probes". Trace the execution, or record honestly '
      'that it mutates and leave it on TRACE-SYSTEM-EXECUTION.',
      new.component_id, new.trace_policy_id
      using errcode = '23514';
  end if;

  if not exists (select 1 from public.phase_c_component_trace_exemption e
                  where e.component_id = new.component_id
                    and e.exempt_to_policy = new.trace_policy_id) then
    raise exception
      'phase_c_component %: no exemption recorded for policy "%". The policy allows completion '
      'without a trace only YES_WITH_DOCUMENTED_REASON, so the document is the precondition, not '
      'the paperwork. Insert the reason, the source measurement and the derivation into '
      'phase_c_component_trace_exemption first.',
      new.component_id, new.trace_policy_id
      using errcode = '23514';
  end if;

  return new;
end
$s3_guard$;

revoke all on function public.fn_phase_c_readonly_exemption_guard() from public;
grant execute on function public.fn_phase_c_readonly_exemption_guard() to service_role;

drop trigger if exists a00_phase_c_readonly_exemption_guard on public.phase_c_component;
create trigger a00_phase_c_readonly_exemption_guard
  before insert or update of trace_policy_id, mutates_state on public.phase_c_component
  for each row execute function public.fn_phase_c_readonly_exemption_guard();

-- ------------------------------------------------------------------ 5. (B) the honest re-scope
--
-- HOW THE 656 WERE SPLIT, AND ON WHAT EVIDENCE
--
-- Two independent measurements, and a component moves only when BOTH say read-only:
--
--   (i)  phase_c_component.mutates_state. 609 of the 656 are recorded as state-changing. Every one
--        of those 609 stays on TRACE-SYSTEM-EXECUTION. Nothing that mutates moves, so the
--        denominator of K6's system_execution_components_with_no_trace numerator is untouched:
--        it reads 609 before this file and 609 after.
--
--   (ii) a sweep of the component's own source on branch rebuild/phase-c-execution-kernel,
--        2026-08-17, for any mutation verb (insert / upsert / update / delete / rpc / a POST, PUT,
--        PATCH or DELETE request / storage .upload( / auth admin user creation) and for artefact
--        production (PDF, XLSX, image, CSV rendered and returned or uploaded). The exact hit list
--        for each component is stored in source_measurement below.
--
-- The sweep DISAGREED with the registry on nine of the forty-seven components the registry calls
-- non-mutating: asset_delete (deletes storage objects), doc_render, make_xlsx, marketing_image and
-- pdf_native (upsert plus storage .upload), qa_mint (auth admin createUser), qa_suite (insert,
-- delete and rpc), social_stage (POST and PATCH) and voice_otp (upsert). All nine are LEFT ON
-- TRACE-SYSTEM-EXECUTION — the safe side — and none of them is exempted. mutates_state is not
-- corrected here because K11's exposure invariant reads that column and correcting it is that
-- increment's subject, not this one's. It is disclosed, not silently trusted and not silently
-- fixed. (Also disclosed: the sweep read the repository file. edge:voice_otp's repository file
-- contains an upsert while K11's platform probe records the DEPLOYED body as a 410 stub. Two
-- different objects; neither is exempted, so nothing here depends on resolving it.)
--
-- Fourteen more of the forty-seven make an outbound POST to a provider or another function, or
-- render an artefact, and are likewise left in place: attach_photos, cad_convert, drawing_boq,
-- extract_text, kb_research_test, license_extract, make_pdf, profile_ai, quote_pdf, quote_review,
-- site_deploy, stripe_setup_page, supplier_review, transcribe, translate_html. quote_pdf is the
-- clearest of them: it renders the customer-facing quote document, which is an official output,
-- and the TRACE-INFRASTRUCTURE scope excludes official outputs by name.
--
-- That leaves 23. 22 go to TRACE-INFRASTRUCTURE and 1 — vercel_status, a read-only deployment
-- health probe — goes to TRACE-MONITORING. 633 of the 656 stay, including all 609 that mutate.
--
-- WHAT THE K11 DERIVATION COULD AND COULD NOT SAY. fn_kernel_component_reachability is recorded
-- verbatim for every exempted component. For the cron components it is decisive
-- (ACTIVE_CRON, reachable, with the schedule and the run count). For edge functions it is NOT: the
-- derivation only holds platform probes for the fifteen components K11 measured, so for the rest
-- it returns "no reachability vector" — which is the absence of a measurement, not a finding of
-- unreachability, and is recorded as exactly that. Stating it plainly is the point; a derivation
-- with nothing to say must not be quoted as though it agreed.
insert into public.phase_c_component_trace_exemption
  (component_id, exempt_to_policy, reason, source_measurement, k11_derivation)
select v.component_id, v.policy, v.reason, v.measurement,
       'fn_kernel_component_reachability 2026-08-17: derived_classification='
         || coalesce(public.fn_kernel_component_reachability(v.component_id)->>'derived_classification','(none)')
         || '; reachable='
         || coalesce(public.fn_kernel_component_reachability(v.component_id)->>'reachable','(no measurement)')
         || '; decided_by=' || coalesce(public.fn_kernel_component_reachability(v.component_id)->>'decided_by','(no measurement)')
  from (values
  ('edge:about','TRACE-INFRASTRUCTURE',
   'Read-only content reader: selects pages.html for slug "about" and returns it. Changes no business state and produces no official output.',
   'supabase/functions/about/index.ts, 5 lines, 2026-08-17: one .from(pages).select(). No insert/upsert/update/delete/rpc, no outbound POST, no storage upload, no artefact.'),
  ('edge:home','TRACE-INFRASTRUCTURE',
   'Read-only content reader: selects pages.html for slug "home" and returns it. Changes no business state and produces no official output.',
   'supabase/functions/home/index.ts, 5 lines, 2026-08-17: one .from(pages).select(). No mutation verb, no outbound POST, no artefact.'),
  ('edge:home-ar','TRACE-INFRASTRUCTURE',
   'Read-only content reader: selects pages.html for slug "home-ar" and returns it. Changes no business state and produces no official output.',
   'supabase/functions/home-ar/index.ts, 5 lines, 2026-08-17: one .from(pages).select(). No mutation verb, no outbound POST, no artefact.'),
  ('edge:portal','TRACE-INFRASTRUCTURE',
   'Read-only content reader: selects pages.html for slug "portal" and returns it. Changes no business state and produces no official output.',
   'supabase/functions/portal/index.ts, 5 lines, 2026-08-17: one .from(pages).select(). No mutation verb, no outbound POST, no artefact.'),
  ('edge:faq','TRACE-INFRASTRUCTURE',
   'Read-only FAQ reader. Returns stored answers; changes no business state and produces no official output.',
   'supabase/functions/faq/index.ts, 109 lines, 2026-08-17: reads only. No insert/upsert/update/delete/rpc, no outbound POST, no storage upload, no artefact.'),
  ('edge:legal','TRACE-INFRASTRUCTURE',
   'Read-only legal-page reader. Returns stored text; changes no business state and produces no official output.',
   'supabase/functions/legal/index.ts, 100 lines, 2026-08-17: reads only. No mutation verb, no outbound POST, no storage upload. The only "image/" hit is a content-type header on a static asset.'),
  ('edge:i18n_get','TRACE-INFRASTRUCTURE',
   'Read-only translation reader behind requireInternal. Selects qd_i18n rows; changes no business state and produces no official output.',
   'supabase/functions/i18n_get/index.ts, 20 lines, 2026-08-17: requireInternal then .from(qd_i18n).select(). No mutation verb, no outbound POST, no artefact.'),
  ('edge:public_stats','TRACE-INFRASTRUCTURE',
   'Read-only counter: two PostgREST count-only reads over leads, returned as a public statistic. Changes no business state and produces no official output.',
   'supabase/functions/public_stats/index.ts, 20 lines, 2026-08-17: two GET fetches with Prefer count=exact, Range 0-0. No mutation verb, no artefact.'),
  ('edge:report_body','TRACE-INFRASTRUCTURE',
   'Read-only reader of an already-produced board report, admin-gated. It returns a report that another component created; it creates nothing.',
   'supabase/functions/report_body/index.ts, 35 lines, 2026-08-17: getUser + admin_emails gate, then .from(board_reports).select(). No mutation verb, no outbound POST, no artefact.'),
  ('edge:quote_quality','TRACE-INFRASTRUCTURE',
   'Read-only badge lookup: returns the completeness score already stored on the customer own quotes. Computes nothing new and writes nothing.',
   'supabase/functions/quote_quality/index.ts, 30 lines, 2026-08-17: getUser, customers lookup, .from(quotes).select(id,quality,inquiry_id), ownership filter. No mutation verb, no outbound POST, no artefact.'),
  ('edge:export_all_knowledge','TRACE-INFRASTRUCTURE',
   'Read-only export, named in the TRACE-INFRASTRUCTURE scope column as an exempt kind. Reads knowledge rows and returns them.',
   'supabase/functions/export_all_knowledge/index.ts, 45 lines, 2026-08-17: selects only. No mutation verb, no outbound POST, no storage upload.'),
  ('edge:export_cat_knowledge','TRACE-INFRASTRUCTURE',
   'Read-only export, named in the TRACE-INFRASTRUCTURE scope column as an exempt kind. Reads category knowledge and returns it.',
   'supabase/functions/export_cat_knowledge/index.ts, 33 lines, 2026-08-17: selects only. No mutation verb, no outbound POST, no storage upload.'),
  ('edge:export_leads_csv','TRACE-INFRASTRUCTURE',
   'Read-only export of existing lead rows as text/csv. It serialises what is already recorded; it originates no record and writes nothing.',
   'supabase/functions/export_leads_csv/index.ts, 42 lines, 2026-08-17: selects only, text/csv response. No insert/upsert/update/delete/rpc, no storage upload.'),
  ('edge:src_io','TRACE-INFRASTRUCTURE',
   'Retired 410 responder. It answers HTTP and executes nothing at all, so there is no execution to trace.',
   'supabase/functions/src_io/index.ts, 8 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. No database client, no fetch, no mutation verb.'),
  ('edge:dev_login','TRACE-INFRASTRUCTURE',
   'Retired 410 responder. It answers HTTP and executes nothing at all, so there is no execution to trace.',
   'supabase/functions/dev_login/index.ts, 8 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. No database client, no fetch, no mutation verb.'),
  ('edge:qa_login','TRACE-INFRASTRUCTURE',
   'Retired 410 responder. It answers HTTP and executes nothing at all, so there is no execution to trace.',
   'supabase/functions/qa_login/index.ts, 8 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. No database client, no fetch, no mutation verb.'),
  ('edge:auth_api','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, permanently withdrawn 27 Jul 2026 after an account-squatting defect. It executes nothing at all.',
   'supabase/functions/auth_api/index.ts, 16 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. The signup path is gone from the file, not merely gated.'),
  ('edge:brand_upload','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, decommissioned one-time uploader. It executes nothing at all.',
   'supabase/functions/brand_upload/index.ts, 2 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. Confirmed against the DEPLOYED body by K11 probe edge:brand_upload/retired_stub.'),
  ('edge:kb_retrieve','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, superseded by kb_search 22 Jul 2026. It executes nothing at all.',
   'supabase/functions/kb_retrieve/index.ts, 4 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. Confirmed against the DEPLOYED body by K11 probe edge:kb_retrieve/retired_stub.'),
  ('edge:licence_reminder','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, superseded by doc_reminder 22 Jul 2026. It executes nothing at all.',
   'supabase/functions/licence_reminder/index.ts, 4 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. Confirmed against the DEPLOYED body by K11 probe edge:licence_reminder/retired_stub.'),
  ('edge:orchestrate','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, neutralised 22 Jul 2026 because it paid per step against a broken contract. It executes nothing at all.',
   'supabase/functions/orchestrate/index.ts, 9 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. Confirmed against the DEPLOYED body by K11 probe edge:orchestrate/retired_stub.'),
  ('edge:support_ai','TRACE-INFRASTRUCTURE',
   'Retired 410 responder, superseded by site_assistant 22 Jul 2026. It executes nothing at all.',
   'supabase/functions/support_ai/index.ts, 4 lines, 2026-08-17: Deno.serve returns status 410 unconditionally. Confirmed against the DEPLOYED body by K11 probe edge:support_ai/retired_stub.'),
  ('edge:vercel_status','TRACE-MONITORING',
   'Read-only deployment health probe behind requireInternal: reads Vercel deployment state and log lines and returns them. This is the literal scope of TRACE-MONITORING, "read-only health probes".',
   'supabase/functions/vercel_status/index.ts, 29 lines, 2026-08-17: requireInternal gate, then GET fetches to api.vercel.com deployments and events. No insert/upsert/update/delete/rpc against QuotesDone data, no storage upload, no artefact, and no POST to Vercel.')
  ) as v(component_id, policy, reason, measurement)
 where exists (select 1 from public.phase_c_component c
                where c.component_id = v.component_id
                  and c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
                  and not c.mutates_state)
on conflict (component_id) do update
  set exempt_to_policy   = excluded.exempt_to_policy,
      reason             = excluded.reason,
      source_measurement = excluded.source_measurement,
      k11_derivation     = excluded.k11_derivation,
      recorded_at        = now();

-- The move itself. It is driven off the exemption table, so the guard created above validates
-- every row this statement writes: if any of the 23 were state-changing, or if any exemption row
-- were missing, this UPDATE would raise and the migration would not apply.
update public.phase_c_component c
   set trace_policy_id = e.exempt_to_policy,
       measured_at     = now()
  from public.phase_c_component_trace_exemption e
 where e.component_id = c.component_id
   and c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION';

-- ------------------------------------------------------------------ 6. (C) the wiring
--
-- ONE wrapper, not twenty-two copies. The original command is stored verbatim and executed by the
-- wrapper, rather than embedded in the cron command, because four of the twenty-two commands
-- contain their own dollar quotes and comment blocks and re-quoting them into a cron command is
-- how a job silently stops running.
create table if not exists public.phase_c_system_execution_wrapper (
  jobid            bigint primary key,
  component_id     text not null references public.phase_c_component(component_id),
  original_command text not null,
  wrapped_at       timestamptz not null default now(),
  note             text not null default '',
  constraint phase_c_system_execution_wrapper_cmd_ck check (original_command <> ''),
  -- the stored original must never itself be the wrapper, or a re-apply would nest the wrapper
  -- inside itself and the real work would stop happening
  constraint phase_c_system_execution_wrapper_not_self_ck
    check (original_command !~ 'fn_kernel_cron_exec')
);

comment on table public.phase_c_system_execution_wrapper is
  'S3 (C). The cron command each wrapped job used to carry, stored verbatim. '
  'fn_kernel_cron_exec executes it and writes the system-execution trace around it. This table is '
  'also the rollback: restoring these commands returns every job to its pre-S3 behaviour exactly.';

alter table public.phase_c_system_execution_wrapper enable row level security;
revoke all on public.phase_c_system_execution_wrapper from public;
grant select, insert, update, delete on public.phase_c_system_execution_wrapper to service_role;

-- SECURITY INVOKER on purpose. cron already runs these jobs as postgres, so the wrapper needs no
-- privileges of its own, and a SECURITY DEFINER function that EXECUTEs stored SQL would be an
-- escalation surface for no benefit. The trace writer it calls is the SECURITY DEFINER half.
create or replace function public.fn_kernel_cron_exec(p_jobid bigint)
returns bigint
language plpgsql
set search_path to 'public', 'cron', 'pg_temp'
as $s3_cron$
declare
  w          public.phase_c_system_execution_wrapper%rowtype;
  c          public.phase_c_component%rowtype;
  a          public.phase_c_action_class%rowtype;
  v_sched    text;
  v_started  timestamptz := clock_timestamp();
  v_finished timestamptz;
  v_result   text := 'succeeded';
  v_failure  text := null;
  v_scope    text := null;
begin
  select * into w from public.phase_c_system_execution_wrapper where jobid = p_jobid;
  if not found then
    raise exception
      'fn_kernel_cron_exec: no wrapper row for cron job %. The job command was rewritten to call '
      'this wrapper and the row holding its original command is gone, so there is nothing to run. '
      'Restore the row or restore the command; do not leave the job pointing at nothing.', p_jobid
      using errcode = '23503';
  end if;

  select * into c from public.phase_c_component where component_id = w.component_id;
  if not found then
    raise exception 'fn_kernel_cron_exec: component % has no registry row', w.component_id
      using errcode = '23503';
  end if;

  select schedule into v_sched from cron.job where jobid = p_jobid;
  select * into a from public.phase_c_action_class where action_class = c.authority_class;

  -- Run the original work. The sub-transaction means a failure rolls the work back and still
  -- leaves the trace writable, which is the whole point of recording the failure.
  --
  -- ponytail: the failure is recorded and NOT re-raised, so cron.job_run_details will read
  -- "succeeded" for a run whose work failed. Re-raising would roll back the trace as well and we
  -- would be back to an untraced failure, which is worse. The trace carries result='failed' with
  -- the sqlstate and message, and fn_kernel_system_trace_state reports failures on their own line.
  -- Upgrade path if cron-level failure signalling is ever needed: write the trace through a
  -- dblink/pg_background autonomous connection, then re-raise.
  begin
    execute w.original_command;
  exception when others then
    v_result  := 'failed';
    v_failure := sqlstate || ' ' || sqlerrm;
  end;
  v_finished := clock_timestamp();

  -- A cron component with no Phase B workflow says so, in words, rather than borrowing the
  -- authority of a workflow id it does not have.
  if coalesce(c.workflow_id,'') = ''
     or not exists (select 1 from public.phase_b_workflow where workflow_id = c.workflow_id) then
    v_scope := format('technical scope: scheduled infrastructure execution registered as %L in '
                   || 'phase_c_component.workflow_id, which is not one of the thirty Phase B '
                   || 'workflows. Accountability is carried by the role, not by a workflow.',
                      coalesce(nullif(c.workflow_id,''), '(none)'));
  end if;

  return public.fn_kernel_system_execution_trace(jsonb_build_object(
    'component_id',       c.component_id,
    'system_actor',       c.canonical_system_actor,
    'accountable_role_id',c.accountable_role_id,
    'workflow_id',        case when v_scope is null then c.workflow_id else null end,
    'step_id',            case when v_scope is null then nullif(c.step_id,'') else null end,
    'technical_scope',    v_scope,
    'trigger_source',     format('cron.job/%s %L schedule %L', p_jobid, c.component_id,
                                 coalesce(v_sched,'(unreadable)')),
    -- Derived from the action class, not asserted. If a class ever requires founder approval this
    -- string says so and fn_kernel_system_trace_state counts it on its own line.
    'authority_result',   case
                            when a.action_class is null then 'unknown_action_class:' || coalesce(c.authority_class,'(none)')
                            when a.founder_approval_required then 'requires_founder_approval:' || a.action_class
                            else 'allowed_autonomous:' || a.action_class || ':' || a.execution_mode
                          end,
    -- For a scheduled execution the honest state pair is the execution's own lifecycle: the
    -- wrapper cannot know which business object the payload touched. Where the payload routes
    -- through the kernel, the business transition is traced separately under TRACE-WORKFLOW and
    -- TRACE-STEP; this trace records that the scheduled execution happened and how it ended.
    'state_before',       'scheduled_due',
    'state_after',        v_result,
    'result',             v_result,
    'failure',            to_jsonb(v_failure),
    'correlation_id',     gen_random_uuid()::text,
    'causation_id',       format('cron.job/%s@%s', p_jobid,
                                 to_char(v_started at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MSZ')),
    'input_hash',         md5(w.original_command),
    'started_at',         v_started,
    'finished_at',        v_finished));
end
$s3_cron$;

revoke all on function public.fn_kernel_cron_exec(bigint) from public;
grant execute on function public.fn_kernel_cron_exec(bigint) to service_role;

comment on function public.fn_kernel_cron_exec(bigint) is
  'S3 (C). The single trace-emitting wrapper for scheduled executions. Runs the original command '
  'stored in phase_c_system_execution_wrapper and writes one complete TRACE-SYSTEM-EXECUTION '
  'trace per firing, whether the work succeeded or failed.';

-- Which jobs get wrapped: active AND state-changing AND on TRACE-SYSTEM-EXECUTION. Nothing that is
-- switched off is touched, and nothing is switched on. Measured 2026-08-17: 23 of the 206 cron
-- jobs are active; 22 of the 23 have a registry row (jobid 278, the K5 outbox deliverer, has none
-- and is left alone rather than given an invented one); all 22 are mutates_state = true and all 22
-- are on TRACE-SYSTEM-EXECUTION. The registry labels 187 cron components "active"; 165 of those
-- have no active cron.job row, so they cannot execute and are not wrapped.
insert into public.phase_c_system_execution_wrapper (jobid, component_id, original_command, note)
select j.jobid, c.component_id, j.command,
       'S3 2026-08-17: cron.job active=true, phase_c_component.mutates_state=true, '
       || 'trace_policy_id=TRACE-SYSTEM-EXECUTION'
  from cron.job j
  join public.phase_c_component c
    on c.component_type = 'cron_job'
   and c.source_path_or_db_object = 'cron.job/' || j.jobid
 where j.active
   and c.mutates_state
   and c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
   and j.command !~ 'fn_kernel_cron_exec'
on conflict (jobid) do nothing;

do $s3_wrap$
declare r record;
begin
  for r in select jobid from public.phase_c_system_execution_wrapper order by jobid loop
    perform cron.alter_job(r.jobid,
      command => format('select public.fn_kernel_cron_exec(%s);', r.jobid));
  end loop;
end
$s3_wrap$;

-- ------------------------------------------------------------------ 7. (D) the state function
--
-- Numerator AND denominator on every line. NEW is "at or after phase_c_kernel_epoch.started_at",
-- an instant no DML can move.
--
-- WHAT IS AND IS NOT OBSERVABLE. cron.job_run_details is a real execution log, so cron executions
-- can be counted one by one and matched to traces. Edge-function invocations, database-trigger
-- firings and event-subscription deliveries have NO execution log in this database, so they cannot
-- be scored — and a scorer whose input is absent must not print 100%. They are reported on their
-- own line as unobservable, with their size, and they are excluded from the coverage denominator
-- rather than silently counted as satisfied.
create or replace function public.fn_kernel_system_trace_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'cron', 'pg_temp'
as $s3_state$
with epoch as (
  select started_at from public.phase_c_kernel_epoch where epoch_id = 'S3_SYSTEM_EXECUTION_TRACING'
),
runs as (   -- every firing of a wrapped state-changing cron job, split by the epoch
  select r.runid, r.jobid, w.component_id, r.start_time,
         coalesce(r.end_time, now()) as end_time,
         (r.start_time >= (select started_at from epoch)) as is_new
    from cron.job_run_details r
    join public.phase_c_system_execution_wrapper w on w.jobid = r.jobid
),
traced as (
  select runs.*,
         exists (select 1 from public.phase_c_system_execution se
                  where se.component_id = runs.component_id
                    and se.started_at >= runs.start_time
                    and se.started_at <= runs.end_time) as has_trace
    from runs
),
scope as (   -- everything still governed by TRACE-SYSTEM-EXECUTION
  select * from public.phase_c_component where trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
),
wrappable as (   -- active, state-changing, registered cron components: the ones C had to wire
  select c.component_id, j.jobid
    from cron.job j
    join public.phase_c_component c
      on c.component_type = 'cron_job'
     and c.source_path_or_db_object = 'cron.job/' || j.jobid
   where j.active and c.mutates_state and c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
)

-- ---- 1. NEW executions that carry the required trace ----------------------------------------
-- ok requires a NON-EMPTY population. 0 of 0 is not 100%: it is a scorer with no input, and a
-- scorer with no input that prints a pass is the defect this whole increment is about.
select 'new_state_changing_system_executions_with_required_trace'::text,
       'every one, and at least one'::text,
       (select count(*) filter (where is_new and has_trace)::text || ' of '
             || count(*) filter (where is_new)::text from traced)
         || ' wrapped cron executions since the epoch',
       (select count(*) filter (where is_new) > 0
           and count(*) filter (where is_new and has_trace) = count(*) filter (where is_new)
          from traced)

union all
-- ---- 2. NEW executions missing a trace --------------------------------------------------------
select 'new_state_changing_system_executions_missing_a_trace',
       '0 of the executions since the epoch',
       (select count(*) filter (where is_new and not has_trace)::text || ' of '
             || count(*) filter (where is_new)::text from traced),
       (select count(*) filter (where is_new and not has_trace) = 0 from traced)

union all
-- ---- 3. business-state-changing components incorrectly exempted -------------------------------
-- Structurally impossible while a00_phase_c_readonly_exemption_guard exists, and measured anyway:
-- a guard that is never checked is a guard that can be dropped without anyone noticing.
select 'state_changing_components_on_a_read_only_policy',
       '0 of the components on a read-only policy',
       (select count(*) filter (where mutates_state)::text || ' of ' || count(*)::text
          from public.phase_c_component
         where trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE'])),
       (select count(*) filter (where mutates_state) = 0
          from public.phase_c_component
         where trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE']))

union all
-- ---- 4. read-only exemptions without a recorded document --------------------------------------
select 'read_only_components_without_a_recorded_exemption',
       '0 of the components on a read-only policy',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_component_trace_exemption e
                  where e.component_id = c.component_id and e.exempt_to_policy = c.trace_policy_id))::text
             || ' of ' || count(*)::text
          from public.phase_c_component c
         where c.trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE'])),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_component_trace_exemption e
                  where e.component_id = c.component_id and e.exempt_to_policy = c.trace_policy_id)) = 0
          from public.phase_c_component c
         where c.trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE']))

union all
-- ---- 5. every wirable cron component is actually wired ----------------------------------------
select 'active_state_changing_cron_components_not_wrapped',
       '0 of the active state-changing cron components',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution_wrapper w where w.jobid = x.jobid))::text
             || ' of ' || count(*)::text from wrappable x),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution_wrapper w where w.jobid = x.jobid)) = 0
          from wrappable x)

union all
-- ---- 6. no trace under this policy may be missing its execution record ------------------------
select 'system_execution_traces_without_a_complete_record',
       '0 of the traces under TRACE-SYSTEM-EXECUTION',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id))::text
             || ' of ' || count(*)::text
          from public.phase_c_trace t where t.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id)) = 0
          from public.phase_c_trace t where t.trace_policy_id = 'TRACE-SYSTEM-EXECUTION')

union all
-- ---- 7. nothing autonomous may claim an authority it does not have ----------------------------
select 'new_system_executions_claiming_founder_authority',
       '0 of the executions recorded since the epoch',
       (select count(*) filter (where authority_result like 'requires\_founder\_approval%'
                                   or authority_result like 'unknown\_action\_class%')::text
             || ' of ' || count(*)::text
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch)),
       (select count(*) filter (where authority_result like 'requires\_founder\_approval%'
                                   or authority_result like 'unknown\_action\_class%') = 0
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch))

union all
-- ---- 8. HISTORICAL, reported as historical and never backfilled -------------------------------
select 'historical_untraced_system_executions',
       'informational — historical, never traced, deliberately not backfilled',
       (select count(*) filter (where not is_new)::text || ' of ' || count(*)::text
          from traced)
         || ' wrapped-cron firings predate the kernel epoch and have no trace, by design',
       true

union all
select 'historical_untraced_cron_executions_all_jobs',
       'informational — the whole pre-epoch execution log',
       (select count(*)::text from cron.job_run_details
         where start_time < (select started_at from epoch))
         || ' of ' || (select count(*)::text from cron.job_run_details)
         || ' cron firings on record predate the epoch',
       true

union all
-- ---- 9. what cannot be measured, named rather than scored -------------------------------------
select 'system_execution_components_with_no_observable_execution_log',
       'informational — cannot be scored from this database, so not scored',
       (select count(*) filter (where component_type <> 'cron_job')::text
             || ' of ' || count(*)::text from scope)
         || ' components on TRACE-SYSTEM-EXECUTION are edge functions, database triggers or event '
         || 'subscriptions; this database holds no invocation log for them, so their coverage is '
         || 'unknown, not 100%',
       true

union all
select 'components_moved_to_a_read_only_policy',
       'informational',
       (select count(*)::text from public.phase_c_component_trace_exemption)
         || ' of 656 moved off TRACE-SYSTEM-EXECUTION with a recorded exemption; '
         || (select count(*)::text from scope) || ' remain, including all '
         || (select count(*) filter (where mutates_state)::text from scope)
         || ' state-changing components',
       true

union all
select 'new_system_executions_recorded_as_failed',
       'informational — a failure recorded is louder than a failure lost',
       (select count(*) filter (where result = 'failed')::text || ' of ' || count(*)::text
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch)),
       true

union all
select 'traces_written_under_trace_system_execution',
       'informational',
       (select count(*)::text from public.phase_c_trace
         where trace_policy_id = 'TRACE-SYSTEM-EXECUTION')
         || ' of ' || (select count(*)::text from public.phase_c_trace),
       true;
$s3_state$;

revoke all on function public.fn_kernel_system_trace_state() from public;
grant execute on function public.fn_kernel_system_trace_state() to service_role;

comment on function public.fn_kernel_system_trace_state() is
  'S3 (D). System-execution trace coverage, numerator and denominator on every line, NEW split '
  'from HISTORICAL by phase_c_kernel_epoch.started_at. Coverage is scored only over cron '
  'executions, because cron.job_run_details is the only execution log this database holds; edge '
  'functions, triggers and event subscriptions are reported as unobservable, not as satisfied.';

-- ------------------------------------------------------------------ 8. K6's integrity function
--
-- MOVED HERE FROM scripts/sql/kernel_k6_trace_ledger.sql. Unchanged except for two additions,
-- both of which exist because S3 writes a subject_kind K6 had never seen:
--
--   * the subject_kind map gains 'system_execution'. Without it every trace this increment writes
--     falls into the else-branch and traces_with_unmapped_subject_kind — a check that is supposed
--     to catch a trace whose kind nobody models — goes red on the traces that were the point.
--   * a new orphan line, orphan_traces_system_execution, which is the equivalent assertion for the
--     new kind: its subject is a component, so the test is that component_id resolves in
--     phase_c_component, exactly as the other kinds test their own id column.
--
-- system_execution_components_with_no_trace is left EXACTLY as K6 wrote it. It is expected to stay
-- red, and its denominator moves from 656 to 633 because 23 read-only components left the policy
-- with a recorded exemption; its numerator is unchanged at 609, because nothing state-changing
-- moved. It goes green only when every state-changing component under this policy has actually
-- been traced, which S3 starts and does not finish.
--
-- Every numerator is a `filter (where ...)` and every denominator is `count(*)` over the WHOLE
-- table for that kind. No check has a population filter in its FROM. The check that read "0 of 1"
-- did so because its FROM said `where state = 'completed'`; the seven rows it should have caught
-- were not in its population at all. A denominator that can only ever contain passing rows is not
-- a denominator.
create or replace function public.fn_kernel_trace_integrity()
returns table (check_name text, expected text, actual text, ok boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $q$
with obj as (
  select 'founder_command'::text as kind, c.command_id::text as ref, c.state as state, c.trace_id,
         (c.state in ('completed','failed','cancelled','refused','superseded')) as is_terminal
    from public.founder_command c
  union all
  select 'workflow_run', r.run_id::text, r.state, r.trace_id,
         (r.state in ('completed','cancelled','failed','superseded','expired','rejected'))
    from public.phase_c_workflow_run r
  union all
  select 'step_run', s.step_run_id::text, s.state, s.trace_id,
         (s.state in ('completed','cancelled','failed','superseded','skipped'))
    from public.phase_c_workflow_step_run s
  union all
  select 'task', t.task_id::text, t.state, t.trace_id,
         (t.state in ('completed','failed','cancelled','superseded'))
    from public.phase_c_task t
  union all
  select 'handoff_run', h.handoff_run_id::text, h.status, h.trace_id,
         (h.status in ('accepted','rejected','cancelled','superseded'))
    from public.phase_c_handoff_run h
),
j as (
  select o.*, tr.trace_id as found_trace, tr.sealed_at, tr.status as trace_status, tr.state_after
    from obj o left join public.phase_c_trace tr on tr.trace_id = o.trace_id
),
-- phase_c_trace records subject_kind in two vocabularies ('command'/'founder_command',
-- 'handoff'/'handoff_run'). Reading only one of them is how a check silently stops seeing half a
-- table, so both are normalised here rather than picked between.
tk as (
  select t.*,
         case t.subject_kind
           when 'command' then 'founder_command' when 'founder_command' then 'founder_command'
           when 'run' then 'workflow_run'        when 'workflow_run' then 'workflow_run'
           when 'step' then 'step_run'           when 'step_run' then 'step_run'
           when 'task' then 'task'
           when 'handoff' then 'handoff_run'     when 'handoff_run' then 'handoff_run'
           -- S3. The kind whose subject is a COMPONENT rather than one of the five kernel
           -- objects. Without this branch every trace S3 writes lands in `unmapped` and the check
           -- that exists to find a kind nobody models fires on the kind that was just modelled.
           when 'system_execution' then 'system_execution'
           else 'unmapped' end as nkind
    from public.phase_c_trace t
),
term as (
  select * from (values
    ('founder_command','completed'),('founder_command','failed'),('founder_command','cancelled'),
    ('founder_command','refused'),('founder_command','superseded'),
    ('workflow_run','completed'),('workflow_run','cancelled'),('workflow_run','failed'),
    ('workflow_run','superseded'),('workflow_run','expired'),('workflow_run','rejected'),
    ('step_run','completed'),('step_run','cancelled'),('step_run','failed'),
    ('step_run','superseded'),('step_run','skipped'),
    ('task','completed'),('task','failed'),('task','cancelled'),('task','superseded'),
    ('handoff_run','accepted'),('handoff_run','rejected'),('handoff_run','cancelled'),
    ('handoff_run','superseded')
  ) as v(kind, state)
)

-- ---- active (NON-terminal) objects with no usable trace, per kind --------------------------
select 'active_objects_without_trace_' || j.kind, '0',
       count(*) filter (where not j.is_terminal and j.found_trace is null)::text
         || ' of ' || count(*)::text,
       count(*) filter (where not j.is_terminal and j.found_trace is null) = 0
  from j group by j.kind

union all
-- ---- terminal objects whose trace is missing or still open ---------------------------------
select 'terminal_objects_with_open_trace_' || j.kind, '0',
       count(*) filter (where j.is_terminal and (j.found_trace is null or j.sealed_at is null))::text
         || ' of ' || count(*)::text,
       count(*) filter (where j.is_terminal and (j.found_trace is null or j.sealed_at is null)) = 0
  from j group by j.kind

union all
-- ---- the trace and its subject disagree about what state the subject is in -----------------
select 'trace_state_disagrees_with_subject_' || j.kind, '0',
       count(*) filter (where j.found_trace is not null and j.state_after is distinct from j.state)::text
         || ' of ' || count(*)::text,
       count(*) filter (where j.found_trace is not null and j.state_after is distinct from j.state) = 0
  from j group by j.kind

union all
-- ---- a trace that presents as sealed but is not protected -----------------------------------
select 'traces_sealed_with_no_sealed_at', '0',
       count(*) filter (where status = 'sealed' and sealed_at is null)::text || ' of ' || count(*)::text,
       count(*) filter (where status = 'sealed' and sealed_at is null) = 0
  from public.phase_c_trace

union all
select 'traces_sealed_at_set_but_status_open', '0',
       count(*) filter (where status <> 'sealed' and sealed_at is not null)::text || ' of ' || count(*)::text,
       count(*) filter (where status <> 'sealed' and sealed_at is not null) = 0
  from public.phase_c_trace

union all
-- ---- orphans: the subject_kind names an object kind and the id column is null ----------------
-- Counted BY KIND over the full trace table. The pre-K6 orphans are annotated, not deleted and not
-- filtered: they still appear in this numerator, which is the point of counting them by kind.
select 'orphan_traces_founder_command', '0',
       count(*) filter (where nkind = 'founder_command' and command_id is null)::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'founder_command' and command_id is null) = 0 from tk
union all
select 'orphan_traces_workflow_run', '0',
       count(*) filter (where nkind = 'workflow_run' and run_id is null)::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'workflow_run' and run_id is null) = 0 from tk
union all
select 'orphan_traces_step_run', '0',
       count(*) filter (where nkind = 'step_run' and step_run_id is null)::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'step_run' and step_run_id is null) = 0 from tk
union all
select 'orphan_traces_task', '0',
       count(*) filter (where nkind = 'task' and task_id is null)::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'task' and task_id is null) = 0 from tk
union all
-- phase_c_trace has no handoff_run_id column, so a handoff trace can only be resolved through
-- subject_ref. Named for what it actually measures rather than borrowing the shape above.
-- ponytail: add phase_c_trace.handoff_run_id if handoff tracing ever gets a second writer.
select 'orphan_traces_handoff_unresolvable_subject_ref', '0',
       count(*) filter (where nkind = 'handoff_run'
                          and not exists (select 1 from public.phase_c_handoff_run h
                                           where h.handoff_run_id::text = tk.subject_ref))::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'handoff_run'
                          and not exists (select 1 from public.phase_c_handoff_run h
                                           where h.handoff_run_id::text = tk.subject_ref)) = 0 from tk
union all
-- S3. The system-execution equivalent of the orphan checks above: this kind's subject is a
-- component, so the id that has to resolve is component_id, and the record that has to exist is
-- the phase_c_system_execution row carrying the fields phase_c_trace has no column for.
select 'orphan_traces_system_execution', '0',
       count(*) filter (where nkind = 'system_execution'
                          and (component_id = ''
                               or not exists (select 1 from public.phase_c_component c
                                               where c.component_id = tk.component_id)
                               or not exists (select 1 from public.phase_c_system_execution se
                                               where se.trace_id = tk.trace_id)))::text
         || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'system_execution'
                          and (component_id = ''
                               or not exists (select 1 from public.phase_c_component c
                                               where c.component_id = tk.component_id)
                               or not exists (select 1 from public.phase_c_system_execution se
                                               where se.trace_id = tk.trace_id))) = 0 from tk
union all
select 'traces_with_unmapped_subject_kind', '0',
       count(*) filter (where nkind = 'unmapped')::text || ' of ' || count(*)::text,
       count(*) filter (where nkind = 'unmapped') = 0 from tk

union all
-- ---- completed traces that are still mutable -------------------------------------------------
-- state_after has reached a terminal state for the subject's own kind, and sealed_at is null, so
-- fn_phase_c_trace_append_only will let it be rewritten in place.
select 'completed_traces_still_mutable', '0',
       count(*) filter (where sealed_at is null
                          and exists (select 1 from term
                                       where term.kind = tk.nkind and term.state = tk.state_after))::text
         || ' of ' || count(*)::text,
       count(*) filter (where sealed_at is null
                          and exists (select 1 from term
                                       where term.kind = tk.nkind and term.state = tk.state_after)) = 0
  from tk

union all
-- ---- TRACE-SYSTEM-EXECUTION: measured, not weakened ------------------------------------------
-- The policy says trace_required=YES, completed_without_trace_allowed=NO. Nothing has ever written
-- a trace under it. This check is expected to be RED and must stay red until scheduled, webhook,
-- queue, storage and provider-adapter execution actually writes traces. Turning it green by
-- narrowing the scope would be the defect the policy exists to prevent.
select 'system_execution_components_with_no_trace', '0',
       count(*) filter (where c.mutates_state
                          and not exists (select 1 from public.phase_c_trace t
                                           where t.component_id = c.component_id))::text
         || ' of ' || count(*)::text,
       count(*) filter (where c.mutates_state
                          and not exists (select 1 from public.phase_c_trace t
                                           where t.component_id = c.component_id)) = 0
  from public.phase_c_component c where c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'

union all
select 'traces_written_under_trace_system_execution', 'more than 0',
       count(*) filter (where trace_policy_id = 'TRACE-SYSTEM-EXECUTION')::text
         || ' of ' || count(*)::text,
       count(*) filter (where trace_policy_id = 'TRACE-SYSTEM-EXECUTION') > 0
  from public.phase_c_trace

union all
-- ---- disclosure rows: the denominators a reader needs to see move ----------------------------
select 'raw_total_traces', 'informational', count(*)::text || ' of ' || count(*)::text, true
  from public.phase_c_trace
union all
select 'raw_total_traced_objects', 'informational',
       count(*) filter (where found_trace is not null)::text || ' of ' || count(*)::text, true from j
union all
select 'raw_terminal_objects', 'informational',
       count(*) filter (where is_terminal)::text || ' of ' || count(*)::text, true from j
union all
select 'traces_superseded', 'informational',
       count(*) filter (where superseded_by is not null)::text || ' of ' || count(*)::text, true
  from public.phase_c_trace
union all
-- Every row K6 annotated or reconstructed, disclosed as its own number so no reader mistakes a
-- backfilled seal or a reconstructed step trace for a contemporaneous record.
select 'traces_carrying_a_k6_backfill_annotation', 'informational',
       count(*) filter (where exists (select 1 from jsonb_array_elements(evidence_refs) e
                                       where e ? 'k6_backfill'))::text || ' of ' || count(*)::text,
       true
  from public.phase_c_trace
$q$;

revoke all on function public.fn_kernel_trace_integrity() from public;
grant execute on function public.fn_kernel_trace_integrity() to service_role;

commit;
