-- THE DEAD-GUARD BLIND SPOT: A CRON THAT NEVER FIRES LOOKS EXACTLY LIKE ONE WITH NOTHING TO DO (3 Sep 2026).
--
-- v_cron_failing reads runs that FAILED. Nothing read the runs that never happened: an active job the
-- scheduler stopped firing produces no failure, no error row, no alert — "0 failures" and "everyone
-- ran" are indistinguishable. This view is the second half of that sentence.
--
-- A job is STALE when it is active, has been active long enough to have fired at least twice, and has
-- no run row of any status inside twice its schedule interval. "Active long enough" is measured from
-- the kernel wrapper's wrapped_at (every re-enabled job has one) or, for an unwrapped job, its first
-- recorded run; a job with neither is stale on sight — active with no evidence it ever ran.
--
-- MEASURED BEFORE WRITING: the naive rule (last success older than 2x the interval) flagged 8 jobs
-- today, every one a false positive — weekly reviews re-enabled on 2-3 Sep that have not met their
-- first Monday, and two crons created this morning. With activation respected the same rule flags 0,
-- and a job inserted active with no runs and no wrapper is flagged (probed under an aborted
-- transaction). The interval is read from the cron expression: */N minutes, hourly (fixed minute),
-- */N hours, weekly (a day-of-week), else daily. Anything stranger is treated as daily.
--
-- fn_watch_failed_runs reads this view every hour and pages once per stale job per 24h, on the same
-- signature ledger as failed runs (signature cron_stale:<jobname>).

create or replace view public.v_cron_stale as
with j as (
  select jobid, jobname, schedule,
         split_part(schedule, ' ', 1) m, split_part(schedule, ' ', 2) h, split_part(schedule, ' ', 5) dow
  from cron.job
  where active
),
iv as (
  select j.*,
         case
           when m like '*/%' and m ~ '^\*/[0-9]+$' then (substr(m, 3)::int) * interval '1 minute'
           when m ~ '^[0-9]+$' and h = '*'          then interval '60 minutes'
           when h like '*/%' and h ~ '^\*/[0-9]+$' then (substr(h, 3)::int) * interval '1 hour'
           when dow ~ '^[0-6]$'                     then interval '7 days'
           else interval '1 day'
         end as every
  from j
),
runs as (
  select jobid, max(start_time) last_any, min(start_time) first_any
  from cron.job_run_details
  group by jobid
),
act as (
  select iv.*, runs.last_any, coalesce(w.wrapped_at, runs.first_any) activated_at
  from iv
  left join runs on runs.jobid = iv.jobid
  left join public.phase_c_system_execution_wrapper w on w.jobid = iv.jobid
)
select jobid, jobname, schedule, every, activated_at, last_any,
       case when activated_at is null then 'active with no wrapper and no run ever recorded'
            else format('no run of any status since %s; schedule %s means one was due every %s',
                        coalesce(last_any::text, 'never'), schedule, every) end as why
from act
where (activated_at is null or activated_at < now() - 2 * every)
  and (last_any is null or last_any < now() - 2 * every);

comment on view public.v_cron_stale is
  'Active cron jobs that have not fired (no run row of any status) inside twice their schedule interval, measured from activation. Read hourly by fn_watch_failed_runs, which pages once per job per 24h.';
