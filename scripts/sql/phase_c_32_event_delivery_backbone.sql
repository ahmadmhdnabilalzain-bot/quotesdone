-- Phase C correction 4 — the delivery backbone that 347 CONNECTED event bindings were describing.
--
-- Measured by the audit: phase_c_event_delivery_attempt had never held a row; nothing anywhere
-- called fn_phase_c_outbox_claim; no cron job named any phase_c object; and the claim function
-- itself only marked rows `claimed` and returned them — it dispatched to nothing. The queue had a
-- producer and a lock, and no consumer and no clock.
--
-- Two workers must never take the same row, a failure must never look like a success, and a null
-- must never be read as "fine". Each of those is a defect this estate has already paid for once.

-- ================================================================ 1. evidence the attempt needs
alter table public.phase_c_event_delivery_attempt
  add column if not exists result_hash text,
  add column if not exists worker_id    text,
  add column if not exists retryable    boolean;

comment on column public.phase_c_event_delivery_attempt.result_hash is
  'SHA-256 of the consumer''s structured result. Empty means the consumer returned nothing, which '
  'is a failure, not a success.';

-- ================================================================ 2. the canonical consumer
-- What a delivered event is supposed to CAUSE. Returns a row rather than a bare boolean so that
-- "handled" and "why not" cannot collapse into the same value.
create or replace function public.fn_phase_c_event_consume(p_outbox_id bigint)
returns table (handled boolean, downstream_ref text, result jsonb, reason text)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  o public.phase_c_event_outbox%rowtype;
  e public.phase_b_event%rowtype;
  v_ing jsonb; v_next record; v_tasks bigint[] := '{}'; v_task bigint;
  v_owner text; v_run bigint; v_step text;
begin
  select * into o from public.phase_c_event_outbox where outbox_id = p_outbox_id;
  if not found then
    return query select false, null::text, null::jsonb, 'unknown_outbox_row'; return;
  end if;
  select * into e from public.phase_b_event where event_id = o.event_id;
  if not found then
    return query select false, null::text, null::jsonb,
      format('%s is not in the frozen Phase B event registry', o.event_id); return;
  end if;

  -- ---- a workflow started: make sure the run, the step run and the owner's task all exist -------
  if e.event_name like '%.started' then
    v_ing := public.fn_phase_c_event_ingress(
      o.event_id,
      coalesce(o.payload->>'business_object_id',
               'outbox:' || o.outbox_id::text),
      jsonb_build_object('source','outbox_delivery', 'producer', o.producer,
                         'command_id', o.payload->>'command_id'));
    if v_ing is null or coalesce((v_ing->>'ok')::boolean, false) is not true then
      return query select false, null::text, v_ing, 'ingress_did_not_confirm'; return;
    end if;
    return query select true, 'task:' || (v_ing->>'task_id'), v_ing, null::text; return;
  end if;

  -- ---- a step completed: hand the next step to its accountable owner ----------------------------
  if e.event_name like '%.completed' and o.payload ? 'step_id' then
    v_run  := (o.payload->>'run_id')::bigint;
    v_step := o.payload->>'step_id';
    if v_run is null then
      return query select false, null::text, null::jsonb, 'completed event carries no run_id'; return;
    end if;
    for v_next in
      select h.to_step_id, s.accountable_role_id, s.independent_reviewer_role_id, s.idempotency_scope
        from public.phase_b_handoff h
        join public.phase_b_workflow_step s on s.step_id = h.to_step_id
       where h.from_step_id = v_step
       order by h.to_step_id
    loop
      select role_id into v_owner from public.fn_phase_c_resolve_actor(v_next.accountable_role_id);
      continue when v_owner is null or not public.fn_phase_c_actor_may_own(v_owner);
      v_task := public.fn_phase_c_task_create(jsonb_build_object(
        'source_kind','workflow_event', 'source_ref', o.event_id || ':' || v_next.to_step_id,
        'run_id', v_run, 'workflow_id', e.workflow_id, 'step_id', v_next.to_step_id,
        'accountable_role_id', v_owner,
        'objective', format('%s completed; %s is now yours for run %s.',
                            v_step, v_next.to_step_id, v_run),
        'requested_output','The step output required by the frozen Phase B contract, with evidence.',
        'reviewer_required', (coalesce(v_next.independent_reviewer_role_id,'') <> ''),
        'reviewer_role_id', coalesce(v_next.independent_reviewer_role_id,''),
        'idempotency_key', 'run:' || v_run || ':step:' || v_next.to_step_id));
      v_tasks := v_tasks || v_task;
    end loop;
    if cardinality(v_tasks) = 0 then
      -- A terminal step legitimately has no successor. That IS handled, and saying so is not the
      -- same as saying nothing happened.
      return query select true, 'terminal_step:' || v_step,
        jsonb_build_object('successors', 0, 'run_id', v_run), null::text; return;
    end if;
    return query select true, 'tasks:' || array_to_string(v_tasks, ','),
      jsonb_build_object('tasks', to_jsonb(v_tasks), 'run_id', v_run), null::text; return;
  end if;

  -- Absence of a consumer is a refusal, not a delivery.
  return query select false, null::text, null::jsonb,
    format('no canonical consumer for %s (%s)', o.event_id, e.event_name);
end $$;
revoke all on function public.fn_phase_c_event_consume(bigint) from public;
grant execute on function public.fn_phase_c_event_consume(bigint) to service_role;

-- ================================================================ 3. the worker
-- Claims with FOR UPDATE SKIP LOCKED (in fn_phase_c_outbox_claim), records an attempt for every
-- try, keeps the first failure, and only writes `delivered` after a consumer has confirmed.
create or replace function public.fn_phase_c_outbox_deliver(
  p_limit integer default 20, p_worker text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  c record; r record; v_attempt bigint; v_worker text;
  v_ok int := 0; v_retry int := 0; v_dead int := 0; v_claimed int := 0;
  v_started timestamptz; v_err text; v_state text; v_retryable boolean;
begin
  v_worker := coalesce(p_worker, 'pid:' || pg_backend_pid()::text);

  for c in select * from public.fn_phase_c_outbox_claim(p_limit) loop
    v_claimed := v_claimed + 1;
    v_started := clock_timestamp();
    insert into public.phase_c_event_delivery_attempt
      (outbox_id, attempt_no, started_at, ok, worker_id)
    values (c.outbox_id, c.attempts, v_started, false, v_worker)
    returning attempt_id into v_attempt;

    begin
      select * into r from public.fn_phase_c_event_consume(c.outbox_id);

      -- NULL IS NOT SUCCESS. A consumer that returned no row at all is a failure with a name.
      if r is null or r.handled is null then
        v_err := 'consumer returned no verdict'; v_retryable := false;
      elsif r.handled then
        v_err := null; v_retryable := null;
      else
        v_err := coalesce(r.reason, 'consumer declined without a reason'); v_retryable := false;
      end if;

    exception when others then
      v_err := SQLSTATE || ' ' || SQLERRM;
      -- Only infrastructure faults are worth trying again: serialization, deadlock, lock timeout,
      -- statement cancel, out of memory/disk, connection loss. A constraint violation or a bad
      -- payload will fail identically forever, and retrying it just hides it.
      v_retryable := SQLSTATE in ('40001','40P01','55P03','57014','53100','53200','53300','08000','08003','08006');
      r := null;
    end;

    if v_err is null then
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = true, downstream_ref = r.downstream_ref,
        result_hash = encode(sha256(convert_to(coalesce(r.result::text,''), 'UTF8')), 'hex'),
        retryable = null
      where attempt_id = v_attempt;
      update public.phase_c_event_outbox set
        status = 'delivered', delivered_at = now(), last_error = ''
      where outbox_id = c.outbox_id;
      v_ok := v_ok + 1;

    else
      v_state := case when v_retryable and c.attempts < 5 then 'retry_wait' else 'dead_letter' end;
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = false, error = left(v_err, 500),
        result_hash = '', retryable = v_retryable
      where attempt_id = v_attempt;
      update public.phase_c_event_outbox set
        status = v_state,
        last_error = left(v_err, 500),
        -- the FIRST failure is the diagnosis; a retry must not overwrite it
        first_failure = coalesce(first_failure, now()),
        next_attempt_at = case when v_state = 'retry_wait'
                               then now() + (interval '1 minute' * power(2, c.attempts)) else null end
      where outbox_id = c.outbox_id;
      if v_state = 'retry_wait' then v_retry := v_retry + 1; else v_dead := v_dead + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('worker', v_worker, 'claimed', v_claimed, 'delivered', v_ok,
                            'retry_wait', v_retry, 'dead_letter', v_dead, 'at', now());
end $$;
revoke all on function public.fn_phase_c_outbox_deliver(integer, text) from public;
grant execute on function public.fn_phase_c_outbox_deliver(integer, text) to service_role;
comment on function public.fn_phase_c_outbox_deliver(integer, text) is
  'The canonical Phase C outbox delivery worker. Claims with SKIP LOCKED, records every attempt, '
  'keeps the first failure, retries only infrastructure faults, dead-letters everything else, and '
  'marks delivered only after a consumer confirms. A null verdict is a failure, never a success.';

-- ================================================================ 4. the clock
-- One new job, doing one thing, in-database. No disabled business automation is reactivated: this
-- job did not exist before, and it touches only the Phase C outbox.
do $sched$
begin
  perform 1 from cron.job where jobname = 'phase_c_outbox_deliver_1min';
  if not found then
    perform cron.schedule('phase_c_outbox_deliver_1min', '* * * * *',
      $job$select public.fn_phase_c_outbox_deliver(25, 'cron:phase_c_outbox_deliver_1min');$job$);
  else
    perform cron.alter_job((select jobid from cron.job where jobname = 'phase_c_outbox_deliver_1min'),
      schedule := '* * * * *',
      command  := $job$select public.fn_phase_c_outbox_deliver(25, 'cron:phase_c_outbox_deliver_1min');$job$,
      active   := true);
  end if;
end $sched$;
