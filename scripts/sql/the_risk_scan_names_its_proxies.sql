-- fn_supplier_risk_monitor now states what each of its three scans took on trust (s36).
-- Definition otherwise byte-identical to production on 13 Aug 2026.

CREATE OR REPLACE FUNCTION public.fn_supplier_risk_monitor(p_signal text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  insert into public.agent_actions (agent, kind, status, risk, title, detail, assumptions, expected_impact, cost)
  values ('supplier_risk_monitor', v_kind, 'logged',
    case when jsonb_array_length(v_findings) > 0 then 'medium' else 'low' end,
    'Supplier risk scan: ' || p_signal,
    jsonb_build_object('signal', p_signal, 'snapshot', v_now, 'findings', v_findings,
      'comparable', not v_first,
      'note', case when v_first and p_signal = 'performance_drops'
                   then 'first run — a drop needs a previous snapshot, so nothing was compared'
                   else null end),
    -- s36 (13 Aug 2026): what this scan TOOK ON TRUST. The comments in each branch above already
    -- stated it; the row did not carry it, so a reader of the row could not know that
    -- "complaints" is two proxies rather than a complaints table.
    case p_signal
      when 'complaints' then jsonb_build_array(
        'There is no complaints table. This counts two proxies: refunds requested against a supplier, and messages a human or a filter flagged. A dissatisfied customer who neither asked for money back nor was flagged is invisible to it.',
        'A refund request is treated as a complaint about the supplier. Some are about the platform, the price or a change of mind, and this cannot tell them apart.',
        'Flagging is done by whatever set messages.flagged; its precision is not measured here.')
      when 'response_delays' then jsonb_build_array(
        'Slow means slower than the MEDIAN supplier with a measured response time, so half the measured population is flagged by construction and the count says more about the spread than about any threshold.',
        'Suppliers with no avg_response_hours are absent, not fast. A supplier who has never answered anything cannot be slow by this measure.',
        'It assumes avg_response_hours is current; it is whatever supplier_score last computed.')
      else jsonb_build_array(
        'A drop is measured against the PREVIOUS run of this scan, not against a baseline, so a slow decline over many runs never shows as a drop.',
        'avg_reliability averages over suppliers who have a reliability at all; a supplier scored for the first time moves the average without anything changing.',
        case when v_first then 'This is the first run: there was no earlier snapshot, so nothing was compared and no finding here means "could not look", not "looked and found nothing".'
             else 'A previous snapshot existed, so the comparison was genuinely made.' end)
    end,
    case p_signal
      when 'complaints' then 'Each finding is a supplier a customer has asked for money back from and nobody has resolved. Left alone it becomes a refund the platform pays for and a supplier the matcher keeps sending work to.'
      when 'response_delays' then 'A supplier slower than the median is one an RFQ waits on. On a marketplace whose promise is speed, that delay is the product failing quietly.'
      else 'A fall in average reliability is the marketplace getting worse at the one thing a buyer cannot verify themselves before paying.'
    end,
    'No spend. The scan is SQL over existing rows; acting on a finding costs the time to contact a supplier, and in the complaints case may cost a refund, which is the founder''s decision.');

  return jsonb_build_object('signal', p_signal, 'snapshot', v_now,
    'findings', v_findings, 'comparable', not v_first);
end
$function$
;
