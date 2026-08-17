-- K24 — a trace that begins three milliseconds before the scheduler admits the run began.
--
-- fn_kernel_system_trace_state went red while §10's instrumentation CSV was being generated:
--
--   new_state_changing_system_executions_missing_a_trace :: 1 of 49
--
-- One post-epoch execution of a wrapped, state-changing cron job with no system-execution trace.
-- That is exactly the check's job, and the first move is to believe it. The row:
--
--   cron:autonomy_dispose_hourly, job 64, run 333732, start_time 2026-08-17 00:45:00.118297
--
-- The trace exists.
--
--   phase_c_system_execution: component_id cron:autonomy_dispose_hourly,
--                             started_at 2026-08-17 00:45:00.115196,
--                             finished_at 00:45:00.127750, result succeeded
--
-- It starts 00:45:00.115196 and cron records the run as starting 00:45:00.118297 — three
-- milliseconds LATER. fn_kernel_cron_exec stamps started_at when it begins; cron.job_run_details
-- records start_time when the scheduler gets round to writing the row. The trace legitimately
-- begins before the scheduler admits the run has begun, and the predicate
--
--   se.started_at >= runs.start_time and se.started_at <= runs.end_time
--
-- reads that as "no trace".
--
-- The predicate was never the relationship; it was an approximation of it that happened to hold
-- for 48 of 49 executions. What "this run produced this trace" actually means is that the two
-- OVERLAP — they cover the same instant — and that does not require two clocks to agree to the
-- millisecond.
--
-- It is not simply loosened. The job identity is now checked as well as the component, through
-- se.trigger_source, so overlap alone cannot match a different job that happened to fire at the
-- same moment. The predicate is NARROWER in that respect and wider only in the one that was wrong.
--
-- A note on what this is not: the check is not being relaxed to turn a red line green. The
-- execution was traced. The instrument was reporting on the wrong subject — a timestamp window
-- rather than the identity of the execution — which is the most productive lens in this estate and
-- the reason this file exists rather than an exemption for job 64.
--
-- Generated from the LIVE definition by scripts/phase_c/gen_k24.mjs, which refuses to emit unless
-- the old predicate is found verbatim. Nothing else in the function moved.
--
-- Rollback: re-apply scripts/sql/kernel_s3_system_execution_traces.sql, which carries the
-- start_time-window predicate — and will report job 64 untraced again whenever the wrapper wins
-- the race, which is most of the time.

begin;

create or replace function public.fn_kernel_system_trace_state()
returns table (check_name text, expected text, actual text, ok boolean)
language sql
stable
security definer
set search_path to 'public', 'cron', 'pg_temp'
as $k24_state$
with epoch as (
  select started_at from public.phase_c_kernel_epoch where epoch_id = 'S3_SYSTEM_EXECUTION_TRACING'
),
runs as (   -- every firing of a wrapped state-changing cron job, split by the epoch
  select r.runid, r.jobid, w.component_id, r.start_time,
         coalesce(r.end_time, now()) as end_time,
         (r.start_time >= (select started_at from epoch)) as is_new
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
         exists (select 1 from public.phase_c_system_execution se
                  where se.component_id = runs.component_id
                    and se.trigger_source like 'cron.job/' || runs.jobid::text || '%'
                    and se.started_at <= runs.end_time
                    and coalesce(se.finished_at, se.started_at) >= runs.start_time) as has_trace
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
$k24_state$;

commit;
