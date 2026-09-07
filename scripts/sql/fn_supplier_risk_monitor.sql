-- ROW #5 §17 — THE SUPPLIER RISK MONITOR, ON A SCHEDULE.
--
-- §17's three open requirements all failed the same way: "0 active cron(s), N routine(s) reference
-- it". The estate could compute these signals and nothing ever asked it to. A routine with no
-- schedule is not a monitor — it is a query somebody could run.
--
-- ── ONE ROUTINE, THREE SCHEDULES ────────────────────────────────────────────────────────────────
-- The three signals want different cadences and must fail independently: a complaint needs looking
-- at today, a response-time drift is a weekly shape. So the body is shared and the schedules are
-- separate, each cron naming the concern it watches.
--
-- ── EVERY RUN RECORDS ITS SNAPSHOT, WHICH IS WHAT MAKES A "DROP" COMPUTABLE ─────────────────────
-- supplier_score holds only the CURRENT value; there is no history table, so "performance dropped"
-- cannot be computed from it at all. Rather than add a table, each run writes its finding to
-- agent_actions — which already exists, is already the telemetry sink, and gives the history for
-- free. A drop is therefore undetectable on the FIRST run and detectable from the second, and the
-- first run says so rather than reporting "no drops" as though it had looked.
create or replace function public.fn_supplier_risk_monitor(p_signal text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_kind text := 'supplier_risk_' || p_signal;
  v_prev jsonb;
  v_now  jsonb;
  v_findings jsonb;
  v_first boolean;
begin
  if p_signal not in ('complaints', 'response_delays', 'performance_drops') then
    raise exception 'unknown risk signal %', p_signal;
  end if;

  -- The previous snapshot for this signal, if any. Its absence is the "first run" condition.
  select detail into v_prev from public.agent_actions
   where kind = v_kind order by id desc limit 1;
  v_first := v_prev is null;

  if p_signal = 'complaints' then
    -- A complaint, as the estate can actually see one: a refund the customer asked for, and a
    -- message a human or a filter flagged. There is no complaints table; inventing a count from
    -- nothing would be worse than reporting the two proxies by name.
    v_now := jsonb_build_object(
      'refunds_requested', (select count(*) from public.transactions where refund_requested_at is not null),
      'messages_flagged',  (select count(*) from public.messages where flagged is true));
    v_findings := (select coalesce(jsonb_agg(jsonb_build_object(
        'supplier_id', t.supplier_id, 'why', 'a refund was requested against this supplier')), '[]'::jsonb)
      from public.transactions t where t.refund_requested_at is not null and t.refund_resolved_at is null);

  elsif p_signal = 'response_delays' then
    -- Slow is relative to the estate, not to a number somebody picked: a supplier is flagged when
    -- their average response time is worse than the median of suppliers who have one at all.
    v_now := jsonb_build_object(
      'measured', (select count(*) from public.supplier_score where avg_response_hours is not null),
      'median_hours', (select percentile_cont(0.5) within group (order by avg_response_hours)
                         from public.supplier_score where avg_response_hours is not null));
    v_findings := (select coalesce(jsonb_agg(jsonb_build_object(
        'supplier_id', s.lead_id, 'avg_response_hours', s.avg_response_hours,
        'why', 'slower to respond than the median supplier')), '[]'::jsonb)
      from public.supplier_score s
      where s.avg_response_hours is not null
        and s.avg_response_hours > (select percentile_cont(0.5) within group (order by avg_response_hours)
                                      from public.supplier_score where avg_response_hours is not null));

  else -- performance_drops
    v_now := jsonb_build_object(
      'scored', (select count(*) from public.supplier_score where reliability is not null),
      'avg_reliability', (select avg(reliability) from public.supplier_score where reliability is not null));
    -- THE HONEST PART. With no earlier snapshot there is nothing to compare against, so the run
    -- reports that it could not look rather than reporting that it looked and found nothing.
    v_findings := case
      when v_first then '[]'::jsonb
      when (v_now->>'avg_reliability')::numeric < (v_prev->'snapshot'->>'avg_reliability')::numeric
        then jsonb_build_array(jsonb_build_object(
          'why', 'average supplier reliability fell since the previous run',
          'from', v_prev->'snapshot'->>'avg_reliability', 'to', v_now->>'avg_reliability'))
      else '[]'::jsonb end;
  end if;

  -- agent_actions requires `agent`, and has no `actor` column. Worth stating because the same
  -- mistake sat in supplier_onboard's telemetry inside a try/catch, where it failed silently for a
  -- day: a swallowed write looks exactly like a feature nobody used.
  insert into public.agent_actions (agent, kind, status, risk, title, detail)
  values ('supplier_risk_monitor', v_kind, 'logged',
    case when jsonb_array_length(v_findings) > 0 then 'medium' else 'low' end,
    'Supplier risk scan: ' || p_signal,
    jsonb_build_object('signal', p_signal, 'snapshot', v_now, 'findings', v_findings,
      'comparable', not v_first,
      'note', case when v_first and p_signal = 'performance_drops'
                   then 'first run — a drop needs a previous snapshot, so nothing was compared'
                   else null end));

  return jsonb_build_object('signal', p_signal, 'snapshot', v_now,
    'findings', v_findings, 'comparable', not v_first);
end
$function$;

-- THE SCHEDULES. Each command names the concern it watches, so `cron.job` is readable as a list of
-- what this platform actually monitors rather than a list of function calls.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
