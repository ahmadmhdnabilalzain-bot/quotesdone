CREATE OR REPLACE FUNCTION public.fn_phase_c_event_binding_status(p_event_id text)
 RETURNS TABLE(status text, evidence text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e public.phase_b_event%rowtype;
  v_has_producer boolean; v_has_consumer boolean; v_step text; v_consumer_ok boolean;
begin
  select * into e from public.phase_b_event where event_id = p_event_id;
  if not found then
    return query select 'BROKEN'::text,
      'no row in the frozen Phase B event registry for this binding'::text; return;
  end if;

  -- the consumer role must resolve, or nothing downstream can own the result
  select (select kind from public.fn_phase_c_resolve_actor(e.primary_consumer_role_id)) is not null
    into v_consumer_ok;
  if not coalesce(v_consumer_ok, false) then
    return query select 'BROKEN'::text,
      format('primary consumer %L does not resolve to a canonical actor', e.primary_consumer_role_id);
    return;
  end if;

  -- the emitting leg
  if e.event_name like '%.started' then
    v_has_producer := true; v_has_consumer := true;
    return query select 'CONNECTED'::text, format(
      'producer fn_phase_c_event_ingress / fn_founder_command_submit via fn_phase_c_lifecycle_event(%L,''started''); '
      'durable row phase_c_event_outbox; claim fn_phase_c_outbox_claim (FOR UPDATE SKIP LOCKED); '
      'worker fn_phase_c_outbox_deliver (cron phase_c_outbox_deliver_1min); '
      'consumer fn_phase_c_event_consume -> fn_phase_c_event_ingress creates run, step run and task; '
      'evidence phase_c_event_delivery_attempt', e.workflow_id);
    return;
  end if;

  select s.step_id into v_step
    from public.phase_b_workflow_step s
   where s.workflow_id = e.workflow_id
     and public.fn_phase_c_step_event(s.step_id, 'completed') = p_event_id
   limit 1;
  if v_step is not null then
    return query select 'CONNECTED'::text, format(
      'producer fn_phase_c_step_advance via fn_phase_c_step_event(%L,''completed''); '
      'durable row phase_c_event_outbox; claim fn_phase_c_outbox_claim; '
      'worker fn_phase_c_outbox_deliver; consumer fn_phase_c_event_consume hands the successor '
      'step to its accountable owner through phase_b_handoff; evidence phase_c_event_delivery_attempt',
      v_step);
    return;
  end if;

  -- everything else: the registry describes it, nothing emits it, nothing consumes it
  return query select 'DEFERRED_RUNTIME_IMPLEMENTATION'::text, format(
    'no deployed producer emits %L and fn_phase_c_event_consume has no branch for it; '
    'Phase D must add the emitter at the state change this event names and a consumer branch',
    p_event_id);
end $function$
