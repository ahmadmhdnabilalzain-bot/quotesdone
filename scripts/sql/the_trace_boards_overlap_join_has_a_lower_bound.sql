-- THE TRACE BOARD'S OVERLAP JOIN HAS A LOWER BOUND (4 Sep 2026).
--
-- After the join was limited to judged runs the board still took 71-83 s under load and timed out
-- the kernel gate on every PR. Measured: the overlap lookup for the 18,097 judged runs alone took
-- 36 s, because the predicate on phase_c_system_execution had no lower bound on started_at — for a
-- one-minute job every execution of the component was scanned per run. A trace OF a run starts
-- within the same five-second window, so started_at >= start_time - 5 s is the same relationship
-- stated with a bound the (component_id, started_at) index can use. No verdict changes.
--
--   node scripts/apply_sql.mjs scripts/sql/the_trace_boards_overlap_join_has_a_lower_bound.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_kernel_system_trace_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'cron', 'pg_temp'
AS $function$
with epoch as (
  select started_at from public.phase_c_kernel_epoch where epoch_id = 'S3_SYSTEM_EXECUTION_TRACING'
),
runs as (   -- every firing of a wrapped state-changing cron job, split by the epoch
  select r.runid, r.jobid, w.component_id, r.start_time,
         coalesce(r.end_time, now()) as end_time,
         (r.start_time >= greatest((select started_at from epoch), w.wrapped_at)) as is_new
    from cron.job_run_details r
    join public.phase_c_system_execution_wrapper w on w.jobid = r.jobid
),
traced as (
  select runs.*,
         -- K24. Was: se.started_at between runs.start_time and runs.end_time. That is not the
         -- relationship; it is an approximation of it, and a three-millisecond clock difference
         -- broke it. cron:autonomy_dispose_hourly run 333732 was reported as an untraced NEW
         -- state-changing execution while its trace sat in phase_c_system_execution — the wrapper
         -- stamped started_at 2026-08-17 00:45:00.115196 and cron.job_run_details recorded
         -- start_time 00:45:00.118297, three milliseconds LATER. The trace legitimately begins
         -- before the scheduler notices the run has begun.
         --
         -- The real relationship is OVERLAP: the execution and the cron run cover the same
         -- instant. That is what "this run produced this trace" means, and it does not depend on
         -- two clocks agreeing to the millisecond.
         --
         -- The job identity is checked as well as the component, so overlap alone cannot match a
         -- different job that happened to run at the same moment. This is narrower than the old
         -- predicate in that respect and wider only in the one that was wrong.
         -- F26. OVERLAP IS STILL TWO CLOCKS, AND A FAST ENOUGH JOB SLIPS BETWEEN THEM.
         --
         -- K24 replaced `se.started_at between runs.start_time and runs.end_time` with an overlap
         -- test, because the wrapper's clock and the scheduler's clock differ by milliseconds and
         -- the trace legitimately begins before the scheduler notices the run has begun. That was
         -- right and it is not enough. Measured 2026-08-21:
         --
         --   cron:dropbox_backup_scan  trace   05:30:00.310247 -> 05:30:00.347993
         --                             cron    05:30:00.357660 -> 05:30:00.436349
         --
         -- The trace opened AND CLOSED 10ms before cron.job_run_details recorded start_time, so the
         -- two windows are disjoint and the run was reported as an untraced state-changing
         -- execution -- 1 of 3667 -- while its trace sat in the table. cron.job_run_details.start_time
         -- is stamped by the scheduler after the command is dispatched; a job that finishes in 40ms
         -- can be entirely over before that write lands. Requiring the windows to touch is still a
         -- claim about two clocks agreeing.
         --
         -- The relationship is PROXIMITY, not contact: the same component, the same job id, and the
         -- trace within five seconds of the run. Five seconds is far larger than any clock skew
         -- observed here (10ms) and far smaller than the tightest schedule in the estate (one
         -- minute), so it cannot match a DIFFERENT firing of the same job -- which is the only way
         -- widening this could hide a real gap. A run with no trace for its component and job within
         -- five seconds is still reported, which is what makes the check able to fail.
         -- 4 SEP 2026: the overlap join is computed ONLY for the runs this board judges (is_new). The
         -- 27,000 pre-wrap firings need no trace lookup — check 8 counts them by is_new alone — and
         -- looking one up for each of them is what took this board to 83 s and a statement timeout
         -- under load. Same rows, same verdicts, a fraction of the work.
         case when runs.is_new
              then exists (select 1 from public.phase_c_system_execution se
                  where se.component_id = runs.component_id
                    and se.trigger_source like 'cron.job/' || runs.jobid::text || '%'
                    and se.started_at >= runs.start_time - interval '5 seconds'  -- 4 SEP 2026: a trace OF this run starts within the same five seconds; the lower bound lets the (component_id, started_at) index answer in a tight range instead of scanning every execution of a one-minute job
                    and se.started_at <= runs.end_time + interval '5 seconds'
                    and coalesce(se.finished_at, se.started_at) >= runs.start_time - interval '5 seconds')
              else false end as has_trace
    from runs
),
scope as (   -- everything still governed by TRACE-SYSTEM-EXECUTION
  select * from public.phase_c_component where trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
),
wrappable as (   -- active, state-changing, registered cron components: the ones C had to wire
  select c.component_id, j.jobid
    from cron.job j
    join public.phase_c_component c
      on c.component_type = 'cron_job'
     and c.source_path_or_db_object = 'cron.job/' || j.jobid
   where j.active and c.mutates_state and c.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'
)

-- ---- 1. NEW executions that carry the required trace ----------------------------------------
-- ok requires a NON-EMPTY population. 0 of 0 is not 100%: it is a scorer with no input, and a
-- scorer with no input that prints a pass is the defect this whole increment is about.
select 'new_state_changing_system_executions_with_required_trace'::text,
       'every one, and at least one'::text,
       (select count(*) filter (where is_new and has_trace)::text || ' of '
             || count(*) filter (where is_new)::text from traced)
         || ' wrapped cron executions since the epoch',
       (select count(*) filter (where is_new) > 0
           and count(*) filter (where is_new and has_trace) = count(*) filter (where is_new)
          from traced)

union all
-- ---- 2. NEW executions missing a trace --------------------------------------------------------
select 'new_state_changing_system_executions_missing_a_trace',
       '0 of the executions since the epoch',
       (select count(*) filter (where is_new and not has_trace)::text || ' of '
             || count(*) filter (where is_new)::text from traced),
       (select count(*) filter (where is_new and not has_trace) = 0 from traced)

union all
-- ---- 3. business-state-changing components incorrectly exempted -------------------------------
-- Structurally impossible while a00_phase_c_readonly_exemption_guard exists, and measured anyway:
-- a guard that is never checked is a guard that can be dropped without anyone noticing.
select 'state_changing_components_on_a_read_only_policy',
       '0 of the components on a read-only policy',
       (select count(*) filter (where mutates_state)::text || ' of ' || count(*)::text
          from public.phase_c_component
         where trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE'])),
       (select count(*) filter (where mutates_state) = 0
          from public.phase_c_component
         where trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE']))

union all
-- ---- 4. read-only exemptions without a recorded document --------------------------------------
select 'read_only_components_without_a_recorded_exemption',
       '0 of the components on a read-only policy',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_component_trace_exemption e
                  where e.component_id = c.component_id and e.exempt_to_policy = c.trace_policy_id))::text
             || ' of ' || count(*)::text
          from public.phase_c_component c
         where c.trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE'])),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_component_trace_exemption e
                  where e.component_id = c.component_id and e.exempt_to_policy = c.trace_policy_id)) = 0
          from public.phase_c_component c
         where c.trace_policy_id = any (array['TRACE-MONITORING','TRACE-INFRASTRUCTURE']))

union all
-- ---- 5. every wirable cron component is actually wired ----------------------------------------
select 'active_state_changing_cron_components_not_wrapped',
       '0 of the active state-changing cron components',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution_wrapper w where w.jobid = x.jobid))::text
             || ' of ' || count(*)::text from wrappable x),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution_wrapper w where w.jobid = x.jobid)) = 0
          from wrappable x)

union all
-- ---- 6. no trace under this policy may be missing its execution record ------------------------
select 'system_execution_traces_without_a_complete_record',
       '0 of the traces under TRACE-SYSTEM-EXECUTION',
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id))::text
             || ' of ' || count(*)::text
          from public.phase_c_trace t where t.trace_policy_id = 'TRACE-SYSTEM-EXECUTION'),
       (select count(*) filter (where not exists (
                 select 1 from public.phase_c_system_execution se where se.trace_id = t.trace_id)) = 0
          from public.phase_c_trace t where t.trace_policy_id = 'TRACE-SYSTEM-EXECUTION')

union all
-- ---- 7. nothing autonomous may claim an authority it does not have ----------------------------
select 'new_system_executions_claiming_founder_authority',
       '0 of the executions recorded since the epoch',
       (select count(*) filter (where authority_result like 'requires\_founder\_approval%'
                                   or authority_result like 'unknown\_action\_class%')::text
             || ' of ' || count(*)::text
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch)),
       (select count(*) filter (where authority_result like 'requires\_founder\_approval%'
                                   or authority_result like 'unknown\_action\_class%') = 0
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch))

union all
-- ---- 8. HISTORICAL, reported as historical and never backfilled -------------------------------
select 'historical_untraced_system_executions',
       'informational — historical, never traced, deliberately not backfilled',
       (select count(*) filter (where not is_new)::text || ' of ' || count(*)::text
          from traced)
         || ' wrapped-cron firings predate the kernel epoch and have no trace, by design',
       true

union all
select 'historical_untraced_cron_executions_all_jobs',
       'informational — the whole pre-epoch execution log',
       (select count(*)::text from cron.job_run_details
         where start_time < (select started_at from epoch))
         || ' of ' || (select count(*)::text from cron.job_run_details)
         || ' cron firings on record predate the epoch',
       true

union all
-- ---- 9. what cannot be measured, named rather than scored -------------------------------------
select 'system_execution_components_with_no_observable_execution_log',
       'informational — cannot be scored from this database, so not scored',
       (select count(*) filter (where component_type <> 'cron_job')::text
             || ' of ' || count(*)::text from scope)
         || ' components on TRACE-SYSTEM-EXECUTION are edge functions, database triggers or event '
         || 'subscriptions; this database holds no invocation log for them, so their coverage is '
         || 'unknown, not 100%',
       true

union all
select 'components_moved_to_a_read_only_policy',
       'informational',
       (select count(*)::text from public.phase_c_component_trace_exemption)
         || ' of 656 moved off TRACE-SYSTEM-EXECUTION with a recorded exemption; '
         || (select count(*)::text from scope) || ' remain, including all '
         || (select count(*) filter (where mutates_state)::text from scope)
         || ' state-changing components',
       true

union all
select 'new_system_executions_recorded_as_failed',
       'informational — a failure recorded is louder than a failure lost',
       (select count(*) filter (where result = 'failed')::text || ' of ' || count(*)::text
          from public.phase_c_system_execution
         where started_at >= (select started_at from epoch)),
       true

union all
select 'traces_written_under_trace_system_execution',
       'informational',
       (select count(*)::text from public.phase_c_trace
         where trace_policy_id = 'TRACE-SYSTEM-EXECUTION')
         || ' of ' || (select count(*)::text from public.phase_c_trace),
       true;
$function$
