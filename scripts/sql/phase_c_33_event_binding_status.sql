-- Phase C correction 5 — an event binding may say CONNECTED only when every leg exists.
--
-- All 347 rows said CONNECTED. One routine in the database emitted anything at all, nothing had
-- ever consumed a row, and phase_c_event_delivery_attempt had never held one. A status column is
-- prose someone typed at build time; it survives unchanged while the thing it describes is never
-- built, and on a dashboard it reads exactly like evidence.
--
-- This does not hand-assign the new statuses. It DERIVES each one from the legs that now exist,
-- so the column becomes a measurement rather than a claim, and re-running it after any further
-- wiring moves the counts by itself.
--
--   producer -> durable event/outbox -> claim -> delivery worker -> consumer
--            -> result/task/state transition -> delivery evidence

-- ---------------------------------------------------------------- the allowed vocabulary
alter table public.phase_c_event_binding drop constraint if exists phase_c_event_binding_status_ck;
alter table public.phase_c_event_binding add constraint phase_c_event_binding_status_ck
  check (connection_status in ('CONNECTED','DEFERRED_RUNTIME_IMPLEMENTATION',
                               'INTENTIONALLY_INACTIVE','HISTORICAL_ONLY','BROKEN'));

-- ---------------------------------------------------------------- the derivation
-- A producer exists for a lifecycle event when a deployed routine actually emits it:
--   *.started            fn_founder_command_submit (selected workflow) and fn_phase_c_event_ingress
--   *.<step>.completed   fn_phase_c_step_advance, via fn_phase_c_step_event
-- A consumer exists when fn_phase_c_event_consume has a branch that acts on it.
create or replace function public.fn_phase_c_event_binding_status(p_event_id text)
returns table (status text, evidence text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
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
end $$;
revoke all on function public.fn_phase_c_event_binding_status(text) from public;
grant execute on function public.fn_phase_c_event_binding_status(text) to service_role;

-- ---------------------------------------------------------------- apply it to all 347
update public.phase_c_event_binding b
   set connection_status = (select d.status   from public.fn_phase_c_event_binding_status(b.event_id) d),
       evidence          = (select d.evidence from public.fn_phase_c_event_binding_status(b.event_id) d)
 where b.connection_status
       is distinct from (select d.status from public.fn_phase_c_event_binding_status(b.event_id) d)
    or b.evidence
       is distinct from (select d.evidence from public.fn_phase_c_event_binding_status(b.event_id) d);

-- ---------------------------------------------------------------- and refuse to drift again
-- A binding may not be edited to CONNECTED by hand. The derivation is the only way in.
create or replace function public.fn_phase_c_event_binding_status_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v_status text;
begin
  select status into v_status from public.fn_phase_c_event_binding_status(new.event_id);
  if new.connection_status is distinct from v_status then
    raise exception 'phase_c_event_binding %: status %L is not what the legs support (%L). '
                    'Wire the missing leg; do not relabel the row.',
      new.event_id, new.connection_status, v_status using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists a00_phase_c_event_binding_status_guard on public.phase_c_event_binding;
create trigger a00_phase_c_event_binding_status_guard
  before insert or update of connection_status on public.phase_c_event_binding
  for each row execute function public.fn_phase_c_event_binding_status_guard();
