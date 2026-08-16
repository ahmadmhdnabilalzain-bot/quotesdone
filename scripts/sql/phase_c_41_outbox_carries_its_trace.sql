-- Phase C correction 4c — every durable event record carries the trace of the thing that caused it.
--
-- `outbox_rows_without_trace` found 3 of 12 after the backbone went live: the step-completed events
-- emitted by fn_phase_c_step_advance had no trace_id, because each emitting caller was expected to
-- attach one afterwards and one of them did not. Attaching it in the EMITTER instead means no
-- future producer can forget: the identity is resolved from the payload the producer already
-- supplies (step_run_id, run_id, command_id), in that order of specificity.
create or replace function public.fn_phase_c_outbox_emit(
  p_event_id text, p_producer text, p_payload jsonb, p_dedupe text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare e public.phase_b_event%rowtype; v_id bigint; v_trace bigint;
begin
  select * into e from public.phase_b_event where event_id = p_event_id;
  if not found then
    raise exception 'unknown canonical event % — fail closed', p_event_id using errcode = '23503';
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

  -- The causing trace, most specific first. TRACE-SYSTEM-EXECUTION requires it and an untraced
  -- queue row is an execution nobody can account for.
  select coalesce(
    (select sr.trace_id from public.phase_c_workflow_step_run sr
      where sr.step_run_id = (p_payload->>'step_run_id')::bigint),
    (select r.trace_id from public.phase_c_workflow_run r
      where r.run_id = (p_payload->>'run_id')::bigint),
    (select c.trace_id from public.founder_command c
      where c.command_id = (p_payload->>'command_id')::bigint))
  into v_trace;
  if v_trace is not null then
    update public.phase_c_event_outbox set trace_id = v_trace
     where outbox_id = v_id and trace_id is null;
  end if;
  return v_id;
end $$;
revoke all on function public.fn_phase_c_outbox_emit(text, text, jsonb, text) from public;
grant execute on function public.fn_phase_c_outbox_emit(text, text, jsonb, text) to service_role;

-- and the rows already written without one
update public.phase_c_event_outbox o
   set trace_id = coalesce(
     (select sr.trace_id from public.phase_c_workflow_step_run sr
       where sr.step_run_id = (o.payload->>'step_run_id')::bigint),
     (select r.trace_id from public.phase_c_workflow_run r
       where r.run_id = (o.payload->>'run_id')::bigint),
     (select c.trace_id from public.founder_command c
       where c.command_id = (o.payload->>'command_id')::bigint))
 where o.trace_id is null;
