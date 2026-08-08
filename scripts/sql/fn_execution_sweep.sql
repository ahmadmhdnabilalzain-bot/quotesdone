-- fn_execution_sweep — the consumer action_execution and decision_trace never had.
--
-- Measured on production 6 Aug 2026: fn_decide was the ONLY routine in the entire database whose
-- body named action_execution or decision_trace, and it is their writer. Both tables therefore
-- scored "built, populated, read by nothing but the thing that wrote them" — the exact defect the
-- OS blueprint spec file exists to produce a verdict on. Every action_execution row sat at
-- 'queued' from the microsecond it was written, and decision_trace.outcome_status sat at its
-- default 'pending' on all three rows: three columns (outcome_status, outcome, evaluated_at) added
-- for an evaluator that was never built.
--
-- This drains the queue and it does not pretend anything ran that did not:
--   * succeeded — only when the decision it came from actually reached status 'executed'
--   * cancelled — the decision was refused by the gate, rolled back off 'approved', or has since
--                 vanished; it is never going to run, so it does not belong in a queue
--   * stalled   — still queued past the stall window. This is the true statement about a queue
--                 nothing executes, and it is the one this system will keep producing until an
--                 executor exists. A row that is honestly 'stalled' is visible; a row that is
--                 permanently 'queued' is not, which is how three of them went unnoticed.
-- The observed status is then mirrored onto the decision_trace row sharing the correlation_id.
--
-- The sweep UPDATEs both tables and INSERTs into neither, which is deliberate: the reader test in
-- scripts/staging/os_blueprint/component_10.mjs disqualifies an object's PRODUCER from counting as
-- its reader, not everything that touches it. A queue drainer must mark what it drained.
create or replace function public.fn_execution_sweep(p_stall_minutes integer default 60)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_exec integer := 0; v_trace integer := 0; v_queue jsonb;
begin
  with seen as (
    select a.id,
           case
             when d.id is null                                        then 'cancelled'
             when d.status = 'executed'                               then 'succeeded'
             when d.gate_verdict = 'refused'
               or d.status not in ('approved','executed')             then 'cancelled'
             when a.created_at < now() - make_interval(mins => greatest(coalesce(p_stall_minutes,60), 1))
                                                                      then 'stalled'
             else a.status
           end as new_status,
           d.id as dr_id, d.status as dr_status, d.gate_verdict as dr_verdict
      from public.action_execution a
      left join public.decision_record d on d.id::text = a.request ->> 'decision_record_id'
     where a.status = 'queued')
  update public.action_execution a
     set status      = s.new_status,
         attempts    = coalesce(a.attempts, 0) + 1,
         started_at  = coalesce(a.started_at, now()),
         finished_at = case when s.new_status in ('succeeded','cancelled') then now() else a.finished_at end,
         response    = coalesce(a.response, '{}'::jsonb) || jsonb_build_object(
                         'swept_at', now(), 'observed', s.new_status,
                         'decision_record_id', s.dr_id,
                         'decision_status', s.dr_status, 'gate_verdict', s.dr_verdict)
    from seen s
   where s.id = a.id and s.new_status <> 'queued';
  get diagnostics v_exec = row_count;

  update public.decision_trace t
     set outcome_status = a.status,
         outcome        = jsonb_build_object('execution_id', a.id, 'status', a.status,
                            'action_class', a.action_class, 'attempts', a.attempts,
                            'finished_at', a.finished_at),
         evaluated_at   = now()
    from public.action_execution a
   where a.correlation_id = t.correlation_id
     and t.entity_type = 'decision_record'
     and coalesce(t.outcome_status,'') is distinct from a.status;
  get diagnostics v_trace = row_count;

  select jsonb_object_agg(status, n) into v_queue
    from (select status, count(*) n from public.action_execution group by 1) z;

  return jsonb_build_object('executions_settled', v_exec, 'traces_updated', v_trace,
                            'queue', coalesce(v_queue, '{}'::jsonb), 'swept_at', now());
end $function$;

-- A consumer that never runs is the same defect wearing a different hat.
select cron.schedule('execution_sweep_hourly', '20 * * * *', $$select public.fn_execution_sweep();$$);
