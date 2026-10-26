-- A SEAT IS ALIVE WHEN IT ACTS, NOT WHEN IT LOGS A RUN.
--
-- Assigned: it_engineer. 22 Sep 2026.
--
-- MEASURED (production, 22 Sep 2026 ~11:40Z), 24 hours:
--   agent_runs agent='customer_support'  4 rows, last 21 Sep 15:32Z   agent='ceo'  2 rows, last 22 Sep 00:00Z
--   Every one of those rows is an org_task closed by fn_org_task_consume_tick -- nothing else writes them.
--   agent_actions kind='handoff' decided_by='customer_support'  826 (799 of them delivery.request), last
--   11:20Z;  decided_by='ceo'  74 (it.finding, delivery.result, marketing.report ...), last 11:30Z.
--   fn_seat_liveness below, run in a rolled-back transaction at 11:50Z: all six seats 'acting', 0 overdue.
--   So both seats were working all day. agent_runs is a cron log, not an employee log (memory
--   agent-runs-is-a-cron-log-not-an-employee-log): a seat's work is the handoffs it answers.
--
-- WHAT IS WRONG: nothing in the estate answered "is this seat alive?" from the signal that carries it, so
--   the question was answered from agent_runs and read "stopped" for two seats that were not.
--
-- WHAT CHANGES: public.fn_seat_liveness() -- read-only, one row per active org_agents seat:
--   last_act / acts_24h   handoffs the seat decided (agent_actions.decided_by, decided_at)
--   last_run / runs_24h   agent_runs under the seat's name or 'fn:<seat>' (kept, labelled for what it is)
--   overdue / oldest_overdue  handoffs addressed to the seat with no reply past their window -- read
--                             from fn_it_handoff_sla_items, the handoff_sla duty's own rule
--   verdict  'stopped'  work is waiting past its window and the seat has not acted since it arrived
--            'behind'   work is past its window but the seat has acted since (late, not dead)
--            'acting'   it acted or ran in the last 24 hours
--            'idle'     nothing addressed to it and nothing done in 24 hours -- zero is not proof of life,
--                       and the row says so rather than reading as health.
--   The ALARM for a stopped seat already exists: fn_it_duties' handoff_sla duty (PR #832) raises any
--   handoff unanswered past its window. This is the measurement behind it, readable in one call.
--
-- WHAT DOES NOT CHANGE: no table, no trigger, no finding, no duty. Nothing is written.
--
-- PREVENTED BY: scripts/checks/a_seat_is_alive_when_it_acts.test.mjs -- every active seat has a row, the
--   verdict is derived from handoffs (a rolled-back probe gives a ZZ DEMO seat an overdue handoff and no act:
--   'stopped'; then an act: 'behind'), and the source never reads liveness from agent_runs alone.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_seat_is_alive_when_it_acts_not_when_it_logs_a_run.sql --apply

create or replace function public.fn_seat_liveness(p_include_demo boolean default false)
 returns table (seat text, verdict text, last_act timestamptz, acts_24h int, last_run timestamptz, runs_24h int,
                overdue int, oldest_overdue timestamptz)
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with s as (select o.agent_key seat from public.org_agents o where o.active),
  x as (
    select s.seat,
           a.last_act, coalesce(a.n24, 0) acts_24h,
           r.last_run, coalesce(r.n24, 0) runs_24h,
           coalesce(d.n, 0) overdue, d.oldest oldest_overdue
      from s
      left join lateral (select max(h.decided_at) last_act,
                                count(*) filter (where h.decided_at > now() - interval '24 hours')::int n24
                           from public.agent_actions h
                          where h.kind = 'handoff' and h.decided_by = s.seat) a on true
      left join lateral (select max(ar.started_at) last_run,
                                count(*) filter (where ar.started_at > now() - interval '24 hours')::int n24
                           from public.agent_runs ar
                          where ar.agent in (s.seat, 'fn:' || s.seat)
                            and ar.started_at > now() - interval '7 days') r on true
      -- The overdue count is the handoff_sla duty's own reading, not a second copy of its rule: only
      -- handoffs the seat has not REPLIED to past their window (an it.finding it answered and the IT
      -- engineer has not yet closed is not the seat's delay), and founder-bound delivery requests are
      -- left to the delivery duty, which waits out the 19:00 Dubai digest hold.
      left join (select e->'evidence'->>'seat' seat, sum((e->>'affected')::int)::int n,
                        min((e->'evidence'->>'oldest_at')::timestamptz) oldest
                   from jsonb_array_elements(public.fn_it_handoff_sla_items(p_include_demo)) e
                  where e->'evidence'->>'state' = 'unanswered'
                  group by 1) d on d.seat = s.seat)
  select x.seat,
         case when x.overdue > 0 and (x.last_act is null or x.last_act < x.oldest_overdue) then 'stopped'
              when x.overdue > 0 then 'behind'
              when x.acts_24h + x.runs_24h > 0 then 'acting'
              else 'idle' end,
         x.last_act, x.acts_24h, x.last_run, x.runs_24h, x.overdue, x.oldest_overdue
    from x order by x.seat
$function$;

revoke execute on function public.fn_seat_liveness(boolean) from public, anon, authenticated;
grant execute on function public.fn_seat_liveness(boolean) to service_role;

select case when (select count(*) from public.fn_seat_liveness()) = (select count(*) from public.org_agents where active)
             and exists (select 1 from public.fn_seat_liveness() l where l.seat = 'customer_support')
            then 'PROBE OK: fn_seat_liveness answers for every active seat: '
                 || (select string_agg(l.seat || '=' || l.verdict || ' (' || l.acts_24h || ' acts/24h)', ', ') from public.fn_seat_liveness() l)
            else 'PROBE FAILED: fn_seat_liveness does not answer for every active seat' end verdict;
