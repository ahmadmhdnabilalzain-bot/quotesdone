-- THE EYES, PART TWO: make the recorded latency COMPARABLE.
-- Agent: ceo.  9 September 2026.
--
-- supabase/functions/_shared/observe.ts now writes one agent_runs row per edge-function run under
-- `fn:<slug>`, carrying counts->>'ms'. That is a duration. A duration nobody compares to anything
-- cannot show "the generated comparison report is lagging" — the founder's own example — because
-- nothing says what the usual is. This file supplies the comparison and the index that makes it
-- cheap, and stops one existing watcher misreading the new rows.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO: no thresholds, no alerting, no notification. Another
-- agent owns detection. This is the seam it reads.

-- 1. THE INDEX. Every reader below asks the same question — one agent, a time window — and
-- agent_runs had exactly one index (its primary key). 319 rows today makes that free and 3 million
-- rows makes it a sequential scan inside a watcher that runs on a schedule.
create index if not exists idx_agent_runs_agent_started on public.agent_runs (agent, started_at desc);

-- 2. THE COMPARISON. One row per instrumented edge function.
--
-- WHY THE BASELINE EXCLUDES THE LAST HOUR. A "usual" computed over a window that contains the
-- incident moves toward the incident, so a slowdown that lasts long enough stops looking like one.
-- The baseline here is the 7 days ENDING one hour ago; the reading is the last hour. They never
-- overlap, so lag_ratio measures a change rather than diluting it.
--
-- WHY 4xx IS NOT AN ERROR. observe.ts records a rejected password as 'warn' and a 5xx or a thrown
-- exception as 'error'. This view keeps them apart for the same reason: a wrong password is the
-- system working. Counting it as a failure is how a real signal gets buried.
--
-- security_invoker: the view is read by service-role callers, which bypass RLS on their own. With
-- invoker rights it can never become a way for a lesser role to read agent_runs past its RLS.
create or replace view public.v_edge_function_health with (security_invoker = true) as
with runs as (
  select substring(agent from 4) as fn,
         started_at,
         status,
         nullif((counts ->> 'ms'), '')::numeric as ms,
         nullif((counts ->> 'http'), '')::int   as http,
         note
    from public.agent_runs
   where agent like 'fn:%'
     and started_at > now() - interval '8 days'
), recent as (
  select fn,
         count(*)                                                    as runs_1h,
         count(*) filter (where status = 'error')                    as errors_1h,
         count(*) filter (where status = 'warn')                     as warns_1h,
         percentile_cont(0.5)  within group (order by ms) filter (where status <> 'error') as p50_ms_1h,
         percentile_cont(0.95) within group (order by ms) filter (where status <> 'error') as p95_ms_1h,
         max(ms)                                                     as max_ms_1h
    from runs where started_at > now() - interval '1 hour' group by fn
), baseline as (
  -- the 7 days ENDING one hour ago: what "usual" means for this function, uncontaminated by now
  select fn,
         count(*)                                                    as runs_7d,
         percentile_cont(0.5)  within group (order by ms) filter (where status <> 'error') as p50_ms_7d,
         percentile_cont(0.95) within group (order by ms) filter (where status <> 'error') as p95_ms_7d
    from runs
   where started_at between now() - interval '7 days' - interval '1 hour' and now() - interval '1 hour'
   group by fn
), day as (
  select fn,
         count(*)                                 as runs_24h,
         count(*) filter (where status = 'error') as errors_24h,
         count(*) filter (where status = 'warn')  as warns_24h,
         max(started_at)                          as last_run_at,
         max(started_at) filter (where status = 'error') as last_error_at,
         (array_agg(note order by started_at desc) filter (where status = 'error'))[1] as last_error_note,
         (array_agg(http order by started_at desc) filter (where status = 'error'))[1] as last_error_http
    from runs where started_at > now() - interval '24 hours' group by fn
)
select coalesce(d.fn, r.fn, b.fn)                   as fn,
       coalesce(d.runs_24h, 0)                      as runs_24h,
       coalesce(d.errors_24h, 0)                    as errors_24h,
       coalesce(d.warns_24h, 0)                     as warns_24h,
       coalesce(r.runs_1h, 0)                       as runs_1h,
       coalesce(r.errors_1h, 0)                     as errors_1h,
       coalesce(r.warns_1h, 0)                      as warns_1h,
       round(r.p50_ms_1h)                           as p50_ms_1h,
       round(r.p95_ms_1h)                           as p95_ms_1h,
       r.max_ms_1h                                  as max_ms_1h,
       coalesce(b.runs_7d, 0)                       as baseline_runs_7d,
       round(b.p50_ms_7d)                           as baseline_p50_ms,
       round(b.p95_ms_7d)                           as baseline_p95_ms,
       -- THE ONE NUMBER. > 1 means slower than usual; 2.0 means twice its own p95. NULL when there
       -- is nothing to compare against yet — a null here is "not enough history", never "healthy",
       -- and a reader that treats the two the same has the zero-cannot-tell-a-dead-guard defect.
       case when b.p95_ms_7d is not null and b.p95_ms_7d > 0 and r.p95_ms_1h is not null
            then round((r.p95_ms_1h / b.p95_ms_7d)::numeric, 2) end as lag_ratio,
       -- the sample sizes behind lag_ratio, so a reader can refuse to act on two data points
       coalesce(r.runs_1h, 0)                       as lag_sample_n,
       coalesce(b.runs_7d, 0)                       as lag_baseline_n,
       d.last_run_at,
       d.last_error_at,
       d.last_error_http,
       d.last_error_note
  from day d
  full join recent   r on r.fn = d.fn
  full join baseline b on b.fn = coalesce(d.fn, r.fn);

comment on view public.v_edge_function_health is
  'One row per instrumented edge function (agent_runs rows named fn:<slug>, written by '
  '_shared/observe.ts). errors_* count 5xx and thrown exceptions; warns_* count 4xx, which are the '
  'caller''s fault and never an outage. lag_ratio = last hour''s p95 over the p95 of the 7 days '
  'ending an hour ago: >1 is slower than usual, NULL means not enough history to say. THIS VIEW '
  'SETS NO THRESHOLD AND RAISES NO ALERT — the detection agent decides what is bad.';

revoke all on public.v_edge_function_health from public;
grant select on public.v_edge_function_health to service_role;

-- 3. AN HTTP ENDPOINT HAS NO CADENCE, SO ITS SILENCE IS NOT A FAULT.
--
-- fn_runner_silence_watch learns each runner's cadence from agent_runs and pages when a runner goes
-- past three times its own median gap. That is right for a scheduled runner and wrong for an HTTP
-- endpoint: customer_portal answering on five separate days with a median gap over half an hour
-- would be learned as a cadence, and the first quiet weekend would be reported as "an employee has
-- stopped working". Nobody called it. That is the whole fault.
--
-- One predicate, in the CTE that feeds the learner, so `fn:` rows never enter agent_expectations at
-- all. Everything else in this routine is byte-for-byte the definition read back from production on
-- 9 Sep 2026. Their failures and their latency are watched by v_edge_function_health above; their
-- SILENCE is watched by nothing, on purpose, because it means nothing.
CREATE OR REPLACE FUNCTION public.fn_runner_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_run bigint; n_alert int := 0; n_watched int := 0; v_email text;
begin
  insert into agent_runs(agent, started_at) values ('runner_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  -- RE-DERIVE, NEVER SEED. One pass over 30 days of runs gives every runner its own observed
  -- cadence. A runner seen fewer than 5 times has no cadence worth calling regular and is recorded
  -- as on-demand rather than alerted on — which is what stops this becoming the noise generator the
  -- 18 July snapshot would have been if anything had ever read it.
  with runs as (
    select agent, started_at, counts,
           started_at - lag(started_at) over (partition by agent order by started_at) gap
      from agent_runs
     where started_at > now() - interval '30 days'
       -- 9 SEP 2026: `fn:<slug>` rows are edge-function REQUESTS, written by _shared/observe.ts.
       -- An HTTP endpoint has no cadence — its gaps measure how often somebody called it, not
       -- whether it is working — so learning one here would page about a quiet weekend.
       and agent not like 'fn:%'),
  agg as (
    select agent,
           count(*) as n,
           -- A CADENCE IS NOT A BURST. Measured on the first run: doc_extract, match, quote_compare,
           -- inquiry_intake and stripe_webhook all showed a "median gap" of 0.00-0.08 hours, because
           -- they are EVENT-DRIVEN and fire in clusters when work arrives. Treating a cluster as a
           -- schedule makes every quiet day an alert. A real cadence shows up on separate DAYS, so
           -- that is what is counted.
           count(distinct started_at::date) as active_days,
           -- A RUNNER LOGGED ONLY ON EXCEPTIONS HAS NO CADENCE EITHER. cos_execute writes an
           -- agent_runs row under its own name ONLY when it has a throttled signal to report (a
           -- refused task start); its ordinary hourly work is logged under 'ceo'. So its
           -- rows stop the moment it stops having a PROBLEM, and the first version of this watch
           -- read that as the runner going silent -- alerting daily on a loop that was working.
           count(*) filter (where coalesce(counts ? 'signal', false)) as signal_rows,
           max(started_at) as last_seen,
           percentile_cont(0.5) within group (order by extract(epoch from gap)/3600.0) as median_gap_h
      from runs group by agent)
  insert into agent_expectations (agent, kind, max_silence_hours, on_demand, median_gap_hours,
                                  runs_observed, last_seen, note, updated_at)
  select a.agent,
         case when exists (select 1 from org_agents o where o.agent_key = a.agent) then 'employee' else 'code' end,
         -- Three times its own median, floored at 6 hours and capped at two weeks. Derived from the
         -- runner rather than from its schedule, because the schedule is what fn_agent_silence_watch
         -- already checks and is exactly what stayed green while the work stopped.
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then least(336, greatest(6, ceil(a.median_gap_h * 3)))
              else 999999 end,
         not (a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows),
         round(a.median_gap_h::numeric, 2),
         a.n,
         a.last_seen,
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then 'cadence learned from '||a.n||' run(s) across '||a.active_days||' day(s) in 30d, median gap '||round(a.median_gap_h::numeric,2)||'h'
              else 'no steady cadence ('||a.n||' run(s) across '||a.active_days||' day(s), median gap '
                   ||coalesce(round(a.median_gap_h::numeric,2)::text,'n/a')||'h) — event-driven or on-demand, not watched' end,
         now()
    from agg a
  on conflict (agent) do update set
    kind = excluded.kind, max_silence_hours = excluded.max_silence_hours,
    on_demand = excluded.on_demand, median_gap_hours = excluded.median_gap_hours,
    runs_observed = excluded.runs_observed, last_seen = excluded.last_seen,
    note = excluded.note, updated_at = now();

  select count(*) into n_watched from agent_expectations where not on_demand;

  -- EVERY row, not just the watched ones. Scoping this to `not on_demand` left a stale silent=true
  -- on any runner that moved INTO on_demand — measured on the first run: five event-driven runners
  -- kept a silent flag they could no longer clear.
  update agent_expectations e
     set silent = (not e.on_demand
                   and e.last_seen is not null
                   and e.last_seen < now() - (e.max_silence_hours || ' hours')::interval);

  -- ONCE PER SILENCE EPISODE, ONE EMAIL PER RUN (3 Sep 2026). This loop paged the founder once per
  -- silent employee per DAY — 21 "Employee has stopped working" emails in the 24 hours measured on
  -- 3 Sep, 59 all-time — for runners whose schedules were switched off by his own 16 Aug stand-down
  -- and re-enabled on 2-3 Sep. A silence is one fact, not a daily one: an episode is (runner,
  -- last_seen); it is paged the first time it is seen and never again until the runner has run
  -- (a new last_seen is a new episode). And the employees newly silent in one pass go into ONE
  -- email, never one email each. Nothing is hidden: every silent runner is still in
  -- agent_expectations.silent and in the company snapshot.
  declare v_new text := ''; v_new_n int := 0;
  begin
  for r in select agent, kind, last_seen, max_silence_hours, median_gap_hours
             from agent_expectations where silent and not on_demand order by agent
  loop
    if not exists (select 1 from founder_alerts
                    where event='runner_silent'
                      and detail like '%"runner": "'||r.agent||'"%'
                      and detail like '%"last_run": "'||coalesce(r.last_seen::text,'')||'"%') then
      insert into founder_alerts(level, event, detail, channel)
      values (case when r.kind='employee' then 'high' else 'warn' end, 'runner_silent',
        jsonb_build_object('runner', r.agent, 'kind', r.kind,
          'last_run', r.last_seen::text,
          'silent_hours', round(extract(epoch from (now()-r.last_seen))/3600),
          'own_median_gap_hours', r.median_gap_hours,
          'expected_within_hours', r.max_silence_hours)::text, 'email');
      if r.kind = 'employee' then
        v_new_n := v_new_n + 1;
        v_new := v_new || '- ' || r.agent || ': last did anything at ' || coalesce(r.last_seen::text,'unknown')
              || ' (own cadence one run every ' || coalesce(r.median_gap_hours::text,'?') || ' hours)' || E'\n';
      end if;
      n_alert := n_alert + 1;
    end if;
  end loop;
  if v_new_n > 0 then
    -- 6 SEP 2026: routed to the COO as one org_task per condition, never emailed
    -- (founder_mail_policy.runner_silence); this watcher's own founder_alerts rows are its ledger.
    perform public.fn_founder_mail_route('runner_silence',
      v_new_n || ' employee(s) have stopped working',
      'These runners went past their own observed cadence for the first time since they last ran:' || E'\n' || v_new ||
      E'\n' || 'Each is reported once per silence; it will be reported again only after it runs and stops again. ' ||
      'A scheduled job may still be succeeding — this watch looks at what the runner DID, not at whether its schedule fired.',
      'high');
  end if;
  end;

  update agent_runs set finished_at=clock_timestamp(), status='ok',
      counts=jsonb_build_object('runners', (select count(*) from agent_expectations),
                                'watched', n_watched, 'silent', (select count(*) from agent_expectations where silent),
                                'alerts', n_alert,
                                'employees', (select count(*) from agent_expectations where kind='employee'))
   where id=v_run;

  return jsonb_build_object('runners',(select count(*) from agent_expectations),
                            'watched',n_watched,'alerts',n_alert);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;
