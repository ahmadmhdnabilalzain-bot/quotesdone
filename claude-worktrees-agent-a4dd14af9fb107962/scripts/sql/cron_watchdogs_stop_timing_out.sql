-- THE TWO WATCHDOGS THAT WATCH THE CRONS HAD BOTH STOPPED RUNNING, AND NOTHING WATCHES THEM.
--
-- MEASURED on production 11 Aug 2026:
--   cron.job_run_details ......... 143,802 rows / 80 MB, oldest 19 Jul, ONE index (pkey on runid)
--   agent_silence_watch_daily .... FAILED 06:40 today, "canceling statement due to statement timeout"
--   exception_alerts_hourly ...... FAILED 07:35 today, same error, inside fn_os_health
--   cron_history_prune ........... INACTIVE, so the table only grows
--
-- Both failures are the same shape. cron.job_run_details is indexed only on its primary key, and
-- both routines ask it a per-job question:
--
--   fn_os_health          JOIN LATERAL (... WHERE d.jobid=j.jobid ORDER BY start_time DESC LIMIT 1)
--   fn_agent_silence_watch  three correlated subqueries per job, inside a FOR over cron.job
--
-- With 165 active jobs that is 165 (or 495) scans of an 80 MB heap per run. It worked at 20,000
-- rows and stopped working somewhere above 100,000, which is why nothing changed in the code on the
-- day it broke.
--
-- WORSE: fn_exception_alerts calls fn_os_health() TWICE — once to test whether failing_crons is
-- non-empty and again to build the message — so the hourly job paid for the whole thing twice.
--
-- The fix is one index and one aggregate. No history is deleted: cron_history_prune stays off,
-- because run history is the evidence an investigation reads and the founder's own note is that a
-- 24-hour window keeps showing failures that were fixed hours earlier. The right answer to a large
-- table is to read it properly, not to throw it away.

-- NO INDEX. The obvious fix — (jobid, start_time desc) on cron.job_run_details — is refused:
-- "must be owner of table job_run_details". The cron schema belongs to the extension, not to us.
-- So the queries have to be right on their own rather than propped up by an index, which is the
-- better outcome anyway: both rewrites below read the history ONCE and are fast with no index at
-- all, at any table size.

-- fn_agent_silence_watch: one pass over the history instead of three per job.
create or replace function public.fn_agent_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  -- Record successes BEFORE evaluating, so they survive the 14-day history prune.
  update cron_job_seen s
     set last_success = h.last_ok
    from (select jobid, max(start_time) as last_ok
            from cron.job_run_details where status='succeeded' group by jobid) h
   where h.jobid = s.jobid
     and (s.last_success is null or s.last_success < h.last_ok);

  for r in
    -- ONE AGGREGATE, NOT THREE CORRELATED SUBQUERIES PER JOB. This loop used to ask
    -- cron.job_run_details three separate questions for each of 165 active jobs against an 80 MB
    -- heap with no usable index, and on 11 Aug 2026 it began exceeding the statement timeout and
    -- stopped watching anything at all. A watchdog that dies silently is worse than no watchdog:
    -- fn_agent_silence_watch is the routine that would have reported its own absence.
    with h as (
      select jobid,
             count(*)                                                        as history_rows,
             max(start_time) filter (where status='succeeded')               as last_ok_live,
             count(*) filter (where status='failed'
                              and start_time > now() - interval '24 hours')  as fails_24h
        from cron.job_run_details
       group by jobid)
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           coalesce(h.history_rows, 0) as history_rows,
           greatest(h.last_ok_live, s.last_success) as last_ok,
           coalesce(h.fails_24h, 0) as fails_24h,
           s.first_seen,
           s.last_success as stored_ok
      from cron.job j
      left join h on h.jobid = j.jobid
      left join cron_job_seen s on s.jobid = j.jobid
     where j.active
  loop
    -- ACTIVATION IS THE FLOOR (3 Sep 2026). A job re-enabled today with a last success from before
    -- the 16 Aug stand-down is not silent — its clock starts when it was put back on (the kernel
    -- wrapper's wrapped_at). This watch paged the founder about 15 such jobs in one day.
    if exists (select 1 from public.phase_c_system_execution_wrapper w
                where w.jobid = r.jobid and w.wrapped_at > now() - (r.thresh_h||' hours')::interval) then
      continue;
    end if;
    -- Never-run: only when there is NO history AND we have never recorded a success.
    if r.history_rows = 0 and r.stored_ok is null then
      if r.first_seen is not null and r.first_seen < now() - (r.thresh_h||' hours')::interval then
        if not exists (select 1 from founder_alerts where event='cron_never_ran'
                        and detail like '%"'||r.jobname||'"%'
                        and created_at > now() - interval '24 hours') then
          insert into founder_alerts(level,event,detail,channel)
          values ('high','cron_never_ran', jsonb_build_object(
            'job', r.jobname,
            'first_seen', r.first_seen::text,
            'known_for_hours', round(extract(epoch from (now()-r.first_seen))/3600),
            'expected_within_hours', r.thresh_h)::text, 'email');
          if v_email is not null then
            insert into notifications(type,to_email,subject,body,status)
            values ('agent_silence', v_email, 'Scheduled job has never run: '||r.jobname,
              'Job "'||r.jobname||'" is active but has no run history at all. It has been registered since '||
              r.first_seen::text||' and should have run at least every '||r.thresh_h||' hours. It is likely misregistered.','pending');
          end if;
          nr := nr + 1;
        end if;
      else
        g := g + 1;
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      -- ONCE PER SILENCE EPISODE (3 Sep 2026): the episode is (job, last_success). It is paged the
      -- first time it is seen and never again until the job succeeds again — the 24-hour dedupe
      -- this replaced re-paged every silent job every day.
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"job": "'||r.jobname||'"%'
                      and detail like '%"last_success": "'||coalesce(r.last_ok::text,'no success on record')||'"%') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success on record'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        if v_email is not null then
          insert into notifications(type,to_email,subject,body,status)
          values ('agent_silence',v_email,'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.','pending');
        end if;
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        if v_email is not null then
          insert into notifications(type,to_email,subject,body,status)
          values ('agent_silence',v_email,'Scheduled job failing: '||r.jobname,
            'Job "'||r.jobname||'" has failed '||r.fails_24h||' time(s) in the last 24 hours. Last success: '||
            coalesce(r.last_ok::text,'unknown')||'. Check cron.job_run_details for the error text.','pending');
        end if;
        f := f + 1;
      end if;
    end if;
  end loop;

  update agent_runs
     set finished_at=clock_timestamp(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;

-- fn_os_health: DISTINCT ON reads the history once. The LATERAL-per-job version needed the new
-- index to be fast; this one is fast with or without it, which is the difference between a fix and
-- a tuning.
create or replace function public.fn_os_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE res jsonb;
BEGIN
  SELECT jsonb_build_object(
    'generated_at', now(),
    'failing_crons', coalesce((
      SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'status', lr.status, 'when', lr.end_time,
                                          'message', left(coalesce(lr.return_message,''),160))
                       ORDER BY lr.end_time DESC)
      FROM (SELECT DISTINCT ON (jobid) jobid, status, end_time, return_message
              FROM cron.job_run_details
             WHERE start_time > now() - interval '7 days'
             ORDER BY jobid, start_time DESC) lr
      JOIN cron.job j ON j.jobid = lr.jobid
      WHERE lr.status = 'failed' AND lr.end_time > now() - interval '24 hours'
    ), '[]'::jsonb),
    'agent_errors_24h', (SELECT count(*) FROM public.agent_runs WHERE status='error' AND started_at > now() - interval '24 hours'),
    'top_error_agents', coalesce((SELECT jsonb_agg(x) FROM (SELECT jsonb_build_object('agent',agent,'errors',count(*)) x FROM public.agent_runs WHERE status='error' AND started_at > now()-interval '24 hours' GROUP BY agent ORDER BY count(*) DESC LIMIT 6) q),'[]'::jsonb),
    'health_check_fails_24h', (SELECT count(*) FROM public.health_checks WHERE ok=false AND created_at > now()-interval '24 hours'),
    'ai_health_fails', coalesce((SELECT value FROM public.app_secrets WHERE key='ai_health_fails'),'0'),
    'payments_7d_count', (SELECT count(*) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),
    'payments_7d_revenue_aed', coalesce((SELECT round(sum(reveal_fee)::numeric,2) FROM public.transactions WHERE revealed_at > now()-interval '7 days'),0)
  ) INTO res;
  RETURN res;
END $function$;
