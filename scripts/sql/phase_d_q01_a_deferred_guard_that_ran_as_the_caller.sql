-- Q01. A DEFERRED GUARD THAT RAN AS THE CALLER, AND REFUSED EVERY AUTHENTICATED FOUNDER DECISION.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- WHAT HAPPENED, MEASURED RATHER THAN INFERRED.
--
-- On 2026-08-24 the founder submitted two governance decisions through the Command Center. The
-- first (`founder_command`) landed: command 36607, message 37730, trace 3981202. The second — his
-- PCCR-006 approval, submitted as the clarification answer on that same command at 22:47:32.503481Z
-- — was authenticated by os_api, written to public.os_audit_log (id 18826), and then LOST. The
-- clarification row it answered still reads answer_text = NULL.
--
-- The edge log for that second:
--
--   22:47:32.485Z  POST | 201 | /rest/v1/os_audit_log                     <- the receipt
--   22:47:32.504Z  POST | 200 | /rest/v1/rpc/fn_control_mode_require      <- the gate said allowed
--   22:47:32.526Z  POST | 403 | /rest/v1/rpc/fn_founder_command_clarify   <- the decision, refused
--
-- and the ONLY postgres_logs entry in the surrounding half hour:
--
--   22:47:32.749Z  permission denied for table phase_c_trace
--
-- 42501, which PostgREST returns as 403.
--
-- WHY IT IS THIS TRIGGER, AND NOT fn_founder_command_clarify.
--
-- fn_founder_command_clarify is SECURITY DEFINER, owner postgres, and it works. Executed on
-- production 24 Aug inside an aborted transaction with `set local role authenticated` and the
-- founder's own request.jwt.claims, it returned
--
--   {"ok": true, "answer_recorded": true, "tasks_created": 0, "task_ids": [],
--    "status": "clarification_required", "clarification_id": 679}
--
-- The SAME probe with one line added — `set constraints all immediate`, which fires the DEFERRED
-- constraint triggers exactly as COMMIT would while the transaction is still abortable — returned
--
--   FAILED AT -> 42501 permission denied for table phase_c_trace
--
-- That one line is the whole defect. z90_system_execution_pair_guard is a DEFERRABLE INITIALLY
-- DEFERRED constraint trigger on public.phase_c_trace. A deferred trigger fires at COMMIT, by which
-- time the SECURITY DEFINER context that opened the transaction is long gone, so its function runs
-- as the TRANSACTION's role. PostgREST sets that role from the JWT: `authenticated`. And
-- `authenticated` has no SELECT on public.phase_c_trace — measured:
--
--   authenticated  phase_c_trace SELECT = false   phase_c_system_execution SELECT = false
--   service_role   phase_c_trace SELECT = true    phase_c_system_execution SELECT = true
--
-- The guard's FIRST statement is `select * into t from public.phase_c_trace where trace_id = ...`.
-- It denies before it has read a single thing it exists to check.
--
-- THE BLAST RADIUS IS EVERY FOUNDER PATH PCCR-003 MOVED ONTO THE CALLER'S OWN TOKEN.
-- os_api reaches fn_founder_command_submit through `admin` (service_role, which has the grant), and
-- fn_founder_command_clarify and fn_founder_command_control through asCaller(authHeader) — the
-- founder's own bearer token, which is the entire point of PCCR-003: auth.uid() must resolve inside
-- the database so a caller-supplied identity is not what decides. Both of those write
-- phase_c_trace through the state guard, so both queue this deferred trigger, so both have been
-- failing at COMMIT with a 403 since PCCR-003 was applied. This is the third shape of the guard
-- family already recorded here: a guard that fires when the system works.
--
-- THE FIX IS ONE WORD, AND IT IS THE ONE ITS TWO SIBLINGS ALREADY CARRY.
-- The other two deferred constraint triggers in this schema —
-- z95_phase_c_task_trace_committed and z95_phase_c_step_run_trace_committed — are both
-- prosecdef = true for exactly this reason. This one was not. It is now.
--
-- WHAT IS NOT CHANGED: not one predicate. Rules 1, 2, 3, 4 and 6 are byte-identical to the body
-- read out of production before this file ran (digest
-- fce3010b3fcafd705e3dd938a3f16d3eecd9753951cea51fd635af80b6c2bf88). The guard refuses everything
-- it refused yesterday. It simply reads the rows it judges with the owner's rights instead of the
-- caller's, so it can reach a verdict at all.
--
-- ACL: CREATE OR REPLACE preserves the ACL, which is already
-- {postgres=X/postgres,service_role=X/postgres} — no anon, no authenticated, no PUBLIC. Nothing is
-- granted here and nothing needs revoking. (Trigger functions are invoked by the executor and
-- EXECUTE is not checked at fire time, which is why the trigger fired at all before failing on the
-- table read.)
--
-- ROLLBACK: scripts/sql/down/phase_d_q01_a_deferred_guard_that_ran_as_the_caller_down.sql re-applies the
-- SECURITY INVOKER body verbatim. One statement, no data change. Applying the down script restores
-- the defect; it exists so the change is reversible, not because reverting is advisable.

create or replace function public.fn_kernel_system_execution_pair_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
$function$;
