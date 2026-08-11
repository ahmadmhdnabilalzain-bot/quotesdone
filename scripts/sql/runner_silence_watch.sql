-- agent_expectations HAD 36 ROWS, ZERO READERS, AND HAD NOT BEEN TOUCHED SINCE 18 JULY.
--
-- MEASURED 11 Aug 2026:
--   agent_expectations rows ............................ 36, all updated_at 2026-07-18
--   readers in the database (functions, views) ......... 0
--   distinct agent_runs.agent values in the last 30d ... 120
--   of those, WATCHED by agent_expectations ............ 36
--   of those, NOT watched .............................. 84, including cos_execute
--
-- The brief called this a MERGE needing judgement, because resolving the alias chief_of_staff ->
-- brief collides on the primary key (23505). The judgement is that it is not a merge. The table is
-- keyed on agent_runs.agent, which is a RUNNER name — a mixture of cron jobs (uptime, smoke,
-- ai_health), edge functions (copilot, postiz_publish), exec officers (exec:strategy) and seven
-- actual employees. chief_of_staff and brief are two different RUNNERS that happen to be one
-- EMPLOYEE, so resolving the alias is not a merge, it is a category error. Nothing is merged; a
-- `kind` column records which of the two things each row is, and the founder's own rule applies:
-- health runs live in code and are not agents he should be chasing.
--
-- AND IT NOW HAS A READER THAT EARNS ITS KEEP. fn_agent_silence_watch watches cron.job — whether a
-- SCHEDULE fired. It cannot see the failure the founder actually noticed on 9 August: cos_execute's
-- cron kept succeeding hourly while what it did inside changed. A job that returns "1 row" is a
-- successful job whatever happened inside it.
--
-- fn_runner_silence_watch watches the RUNNERS instead: it learns each runner's own observed cadence
-- from agent_runs and alerts when a runner that has been regular goes quiet, whatever its cron says.
-- The expectation is re-derived on every pass, so it can never go stale the way a hand-seeded
-- snapshot did.

begin;

alter table public.agent_expectations
  add column if not exists kind      text,
  add column if not exists last_seen timestamptz,
  add column if not exists silent    boolean not null default false;

comment on table public.agent_expectations is
  'What each RUNNER in agent_runs.agent is expected to do, re-derived from observed behaviour by fn_runner_silence_watch. Keyed on the runner name, NOT on an employee key: chief_of_staff and brief are two runners belonging to one employee, so alias resolution here is a category error, not a merge. kind distinguishes an employee from code.';
comment on column public.agent_expectations.kind is
  'employee = the runner name is an org_agents key, so silence is a person not working. code = a cron job or edge function, so silence is an outage. The founder does not chase code for being idle.';

create or replace function public.fn_runner_silence_watch()
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
    select agent, started_at,
           started_at - lag(started_at) over (partition by agent order by started_at) gap
      from agent_runs where started_at > now() - interval '30 days'),
  agg as (
    select agent,
           count(*) as n,
           -- A CADENCE IS NOT A BURST. Measured on the first run: doc_extract, match, quote_compare,
           -- inquiry_intake and stripe_webhook all showed a "median gap" of 0.00-0.08 hours, because
           -- they are EVENT-DRIVEN and fire in clusters when work arrives. Treating a cluster as a
           -- schedule makes every quiet day an alert. A real cadence shows up on separate DAYS, so
           -- that is what is counted.
           count(distinct started_at::date) as active_days,
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
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5
              then least(336, greatest(6, ceil(a.median_gap_h * 3)))
              else 999999 end,
         not (a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5),
         round(a.median_gap_h::numeric, 2),
         a.n,
         a.last_seen,
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5
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

  for r in select agent, kind, last_seen, max_silence_hours, median_gap_hours
             from agent_expectations where silent and not on_demand order by agent
  loop
    if not exists (select 1 from founder_alerts
                    where event='runner_silent' and detail like '%"'||r.agent||'"%'
                      and created_at > now() - interval '24 hours') then
      insert into founder_alerts(level, event, detail, channel)
      values (case when r.kind='employee' then 'high' else 'warn' end, 'runner_silent',
        jsonb_build_object('runner', r.agent, 'kind', r.kind,
          'last_run', r.last_seen::text,
          'silent_hours', round(extract(epoch from (now()-r.last_seen))/3600),
          'own_median_gap_hours', r.median_gap_hours,
          'expected_within_hours', r.max_silence_hours)::text, 'email');
      if v_email is not null and r.kind = 'employee' then
        insert into notifications(type,to_email,subject,body,status)
        values ('agent_silence', v_email,
          'Employee has stopped working: '||r.agent,
          'The runner "'||r.agent||'" last did anything at '||coalesce(r.last_seen::text,'unknown')||
          '. Its own observed cadence over the last 30 days is one run every '||
          coalesce(r.median_gap_hours::text,'?')||' hours, so it is now well past due. Its scheduled '||
          'job may still be succeeding — this watch looks at what the runner DID, not at whether its '||
          'schedule fired.','pending');
      end if;
      n_alert := n_alert + 1;
    end if;
  end loop;

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

revoke all on function public.fn_runner_silence_watch() from public;
revoke all on function public.fn_runner_silence_watch() from anon;
grant execute on function public.fn_runner_silence_watch() to service_role;

commit;
