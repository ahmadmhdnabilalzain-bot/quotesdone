-- THE IT ALERT TICK FITS THE 8 S STATEMENT TIMEOUT, AND ESCALATION NEVER WAITS BEHIND THE OPEN STEP
-- (it_engineer, 18 Oct 2026). Assigned: it_engineer.
--
-- Found by scripts/checks/it_engineer_loop_is_closed.test.mjs: it.finding handoff 165782 (sales_engineer,
-- latency_slo, created 13 Oct 02:16 UTC, 4 h window) sat past its window unanswered and unescalated.
--
-- Measured 18 Oct 2026 17:18 UTC, in one aborted transaction, section by section:
--   fn_it_loop_open x 409 unopened findings   42.61 s  (about 104 ms each; playbook check 0.03 s total)
--   fn_it_ceo_silence_watch                    2.03 s
--   fn_it_loop_reverify (the escalation)       0.81 s  (28 closed, 5 escalated, 580 waiting)
--   ingest 0.13, digest 0.09, the rest         < 0.2 s
-- resilience_ping calls fn_it_engineer_alert_tick over PostgREST, whose authenticator role has
-- statement_timeout = 8s. So every tick was cancelled and ROLLED BACK. Nothing it opened or escalated
-- survived, the unopened backlog grew (170 on 13 Oct, 407 of 519 open on 18 Oct), every next tick was
-- slower, and it_engineer_scanner 'it_engineer_alert_tick' has not beaten since 13 Oct 05:16 UTC. The
-- monitor:alert_tick_blind finding could not fire either, because it is raised by the same tick.
--
-- The cause is that the open step was unbounded and ran BEFORE reverify. The fix:
--   1. reverify (the escalation) and every sweep run first, so a large backlog can never starve them;
--   2. the open step takes the oldest unopened findings until 3.5 s after the statement began, at most 50
--      per tick, and at least one while the tick is under 6 s, so the backlog drains a few a tick instead
--      of the whole tick dying. The fixed sections cost about 3.1 s (fn_it_ceo_silence_watch 2.1 s of it;
--      it re-asks the CEO decider for every overdue report on purpose), so the open step gets what is left;
--   3. the digest stays last, so everything this tick escalated or opened leaves in one message.
-- ponytail: a time budget, not a faster fn_it_loop_open. If the backlog ever outgrows ~1,500 findings a
-- day, make fn_it_loop_open cheaper (104 ms a call) rather than raising the budget.
--
-- CREATE OR REPLACE keeps the existing ACL; no revoke needed.
-- prevented by: scripts/checks/it_engineer_loop_is_closed.test.mjs ('the alert tick fits the 8 s statement
-- timeout ...'), which times fn_it_engineer_alert_tick in an aborted transaction under statement_timeout 8s.

create or replace function public.fn_it_loop_tick()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare f record; o jsonb := '{}'::jsonb; n_open int := 0; n_left int := 0; v_err jsonb := '[]'::jsonb; v_step text; x jsonb;
        v_deadline timestamptz := statement_timestamp() + interval '3.5 seconds';
        v_floor_until timestamptz := statement_timestamp() + interval '6 seconds';
begin
  -- 1. ESCALATION AND THE SWEEPS FIRST. Before 18 Oct 2026 the open step ran first and unbounded; with
  --    409 findings unopened it took 42 s, PostgREST cancelled the tick at 8 s, and nothing escalated.
  begin o := o || jsonb_build_object('reverify', public.fn_it_loop_reverify());
  exception when others then v_err := v_err || jsonb_build_object('step', 'reverify', 'error', sqlerrm); end;
  begin
    x := public.fn_originators_reverify_handoffs();
    o := o || jsonb_build_object('originators', x);
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'originators', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'originators', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_it_reports_sweep());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;
  begin
    x := public.fn_ceo_sales_engineer_reports_sweep();
    o := o || jsonb_build_object('ceo_sales', x, 'sales_engineer_completed', public.fn_sales_engineer_reports_complete());
    if jsonb_array_length(coalesce(x->'errors', '[]'::jsonb)) > 0 then
      v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', left((x->'errors')::text, 600));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_sales', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_accountant', public.fn_ceo_accountant_reports_sweep(),
                                     'accountant_completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_accountant', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('ceo_silence', public.fn_it_ceo_silence_watch());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo_silence', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('daily', public.fn_it_daily_line());
  exception when others then v_err := v_err || jsonb_build_object('step', 'daily', 'error', sqlerrm); end;

  -- 2. OPEN, OLDEST FIRST, WITHIN WHAT IS LEFT OF THE BUDGET. One definition of open, called, not copied
  --    (fn_it_open_findings, 22 Sep 2026). At least one per tick, so a slow day still drains the queue.
  for f in select q.issue_key, q.started_at from public.fn_it_open_findings() q
            where not exists (select 1 from public.agent_actions a
                               where a.kind = 'handoff' and a.detail->>'type' = 'it.finding'
                                 and a.detail->>'issue_key' = q.issue_key
                                 and (a.detail->>'occurrence_started_at')::timestamptz = q.started_at)
            order by q.started_at loop
    if n_open >= 50 or clock_timestamp() > v_floor_until or (n_open >= 1 and clock_timestamp() > v_deadline) then
      n_left := n_left + 1;
      continue;
    end if;
    begin
      continue when public.fn_it_playbook_first(f.issue_key, f.started_at);
      perform public.fn_it_loop_open(f.issue_key);
      n_open := n_open + 1;
    exception when others then
      v_err := v_err || jsonb_build_object('step', 'open', 'issue_key', f.issue_key, 'error', sqlerrm);
    end;
  end loop;
  o := o || jsonb_build_object('opened', n_open, 'left_for_next_tick', n_left);

  -- 3. Last, so everything this tick escalated or opened leaves in the one message.
  begin o := o || jsonb_build_object('digest', public.fn_customer_support_sends_the_it_digest());
  exception when others then v_err := v_err || jsonb_build_object('step', 'digest', 'error', sqlerrm); end;

  foreach v_step in array array['open', 'reverify', 'originators', 'ceo', 'ceo_sales', 'ceo_accountant', 'ceo_silence', 'daily', 'digest'] loop
    perform public.fn_it_loop_stage(v_step,
      (select string_agg(coalesce(e->>'issue_key' || ': ', '') || (e->>'error'), '; ')
         from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $function$;

select case when pg_get_functiondef('public.fn_it_loop_tick()'::regprocedure) like '%v_deadline%'
            then 'PROBE OK' else 'PROBE FAILED: fn_it_loop_tick does not carry the open budget' end as verdict;
