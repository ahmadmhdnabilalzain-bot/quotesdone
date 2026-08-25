-- Q01 DOWN. RE-APPLY THE SECURITY INVOKER BODY OF fn_kernel_system_execution_pair_guard.
--
-- NO TRANSACTION CONTROL. One statement.
--
-- This restores the body read out of production with pg_get_functiondef BEFORE Q01 ran, whose
-- sha256 over that definition text was
-- fce3010b3fcafd705e3dd938a3f16d3eecd9753951cea51fd635af80b6c2bf88. Not one predicate differs from
-- the up script; the only difference in either direction is the SECURITY clause.
--
-- APPLYING THIS RESTORES THE DEFECT. The deferred constraint trigger fires at COMMIT with the
-- transaction's role, and every founder governance decision that reaches the database through the
-- caller's own bearer token — fn_founder_command_clarify, fn_founder_command_control — will again
-- fail with 42501 permission denied for table phase_c_trace, returned to the browser as a 403 with
-- nothing written. It exists so Q01 is reversible, not because reverting is advisable.

create or replace function public.fn_kernel_system_execution_pair_guard()
returns trigger
language plpgsql
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
