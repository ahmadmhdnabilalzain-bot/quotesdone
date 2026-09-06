CREATE OR REPLACE FUNCTION public.fn_kernel_outbox_deliver(p_limit integer DEFAULT 25, p_worker text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c record; r record; v_attempt bigint; v_worker text;
  v_ok int := 0; v_retry int := 0; v_dead int := 0; v_claimed int := 0;
  v_err text; v_state text; v_retryable boolean;
begin
  v_worker := coalesce(nullif(btrim(p_worker),''), 'pid:' || pg_backend_pid()::text);

  -- Claim: FOR UPDATE SKIP LOCKED, one statement, attempts incremented at claim so a crash cannot
  -- lose the count. coalesce on next_attempt_at because the column is now nullable and a NULL
  -- there would silently make a row unclaimable forever. The 15-minute lease is the fix for the
  -- other half of the old defect: the raise aborted the pass and left every claimed row in
  -- 'claimed', which fn_phase_c_outbox_claim never looks at again.
  for c in
    update public.phase_c_event_outbox o set
      status = 'claimed', claimed_at = now(), attempts = o.attempts + 1
    where o.outbox_id in (
      select s.outbox_id from public.phase_c_event_outbox s
       where (s.status in ('pending','retry_wait') and coalesce(s.next_attempt_at, now()) <= now())
          or (s.status = 'claimed' and s.claimed_at < now() - interval '15 minutes')
       order by s.outbox_id
       for update skip locked
       limit greatest(1, coalesce(p_limit, 25)))
    returning o.*
  loop
    v_claimed := v_claimed + 1;

    -- BEFORE the consumer runs. This insert is outside the handler below on purpose: when the
    -- consumer raises, its subtransaction rolls back and this row is the only surviving evidence
    -- that the attempt happened at all.
    insert into public.phase_c_event_delivery_attempt
      (outbox_id, attempt_no, started_at, ok, worker_id)
    values (c.outbox_id, c.attempts, clock_timestamp(), false, v_worker)
    returning attempt_id into v_attempt;

    -- THE MARK GOES HERE, NOT ONLY IN THE CONSUMER. The first rehearsal of this file proved why:
    -- with the mark set only inside fn_kernel_event_consume, a consumer swapped for another body
    -- carried no mark, called fn_kernel_workflow_start, and CREATED A RUN FROM DELIVERY — status
    -- delivered, runs_created=1. Delivery is the thing that is delivery; whichever consumer runs
    -- inside it is inside it.
    perform set_config('kernel.in_delivery', '1', true);
    begin
      select * into r from public.fn_kernel_event_consume(c.outbox_id);
      if r is null or r.handled is null then
        v_err := 'consumer returned no verdict'; v_retryable := false;   -- null is not success
      elsif r.handled then
        v_err := null; v_retryable := null;
      else
        v_err := coalesce(r.reason, 'consumer declined without a reason'); v_retryable := false;
      end if;
    exception when others then
      v_err := SQLSTATE || ' ' || SQLERRM;
      -- Only infrastructure faults are worth trying again. A constraint violation or a bad payload
      -- fails identically forever, and retrying it hides it.
      v_retryable := SQLSTATE in ('40001','40P01','55P03','57014','53100','53200','53300',
                                  '08000','08003','08006');
      r := null;
    end;
    -- Reset outside the block so it happens on the exception path too. (A subtransaction abort
    -- would restore a GUC set inside the block, but not one set before it.)
    perform set_config('kernel.in_delivery', '0', true);

    if v_err is null then
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = true, downstream_ref = coalesce(r.downstream_ref,''),
        result_hash = encode(sha256(convert_to(coalesce(r.result::text,''), 'UTF8')), 'hex'),
        retryable = null
      where attempt_id = v_attempt;
      -- delivered is written in the success branch and nowhere else
      update public.phase_c_event_outbox set
        status = 'delivered', delivered_at = now(), last_error = '', next_attempt_at = null
      where outbox_id = c.outbox_id;
      v_ok := v_ok + 1;

    else
      v_state := case when v_retryable and c.attempts < c.max_attempts then 'retry_wait'
                      else 'dead_letter' end;
      update public.phase_c_event_delivery_attempt set
        finished_at = clock_timestamp(), ok = false, error = left(v_err, 500),
        result_hash = '', retryable = v_retryable
      where attempt_id = v_attempt;
      update public.phase_c_event_outbox set
        status = v_state,
        last_error = left(v_err, 500),
        last_sqlstate = left(coalesce(substring(v_err from '^[0-9A-Z]{5}'), ''), 5),
        -- the FIRST failure is the diagnosis; a retry must not overwrite it. Both sides are
        -- timestamptz now, and the column is nullable, so this coalesce can finally do its job.
        first_failure = coalesce(first_failure, now()),
        first_failure_reason = coalesce(first_failure_reason, left(v_err, 500)),
        next_attempt_at = case when v_state = 'retry_wait'
                               then now() + (interval '1 minute' * power(2, least(c.attempts, 6)))
                               else null end
      where outbox_id = c.outbox_id;
      if v_state = 'retry_wait' then v_retry := v_retry + 1; else v_dead := v_dead + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('worker', v_worker, 'claimed', v_claimed, 'delivered', v_ok,
                            'retry_wait', v_retry, 'dead_letter', v_dead, 'at', now());
end $function$
