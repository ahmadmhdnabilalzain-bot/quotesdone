-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260718190921   name: cron_watchdog_zero_history_and_self_check
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Closes two blind spots in the cron watchdog:
--  1. fn_agent_silence_watch skipped jobs with zero run history, so a job that never
--     starts stayed invisible forever. We now track first_seen per job and alert once
--     the job has been known for longer than its expected interval (grace period avoids
--     false alarms on newly created jobs whose first slot has not come round yet).
--  2. Nothing observed the watchdog itself. fn_ops_watch (hourly, proven) now checks it.

create table if not exists public.cron_job_seen (
  jobid      bigint primary key,
  jobname    text not null,
  schedule   text,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);

comment on table public.cron_job_seen is
  'Tracks when each cron job was first observed. cron.job has no created_at, so this supplies the grace-period baseline for alerting on jobs that have never run.';

-- Seed from current state so existing jobs are not treated as brand new.
insert into public.cron_job_seen (jobid, jobname, schedule, first_seen, last_seen)
select j.jobid, j.jobname, j.schedule,
       coalesce((select min(d.start_time) from cron.job_run_details d where d.jobid = j.jobid), now()),
       now()
from cron.job j
on conflict (jobid) do nothing;

create or replace function public.fn_agent_silence_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', now()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  -- Record every active job we can see; first_seen is the baseline for the grace period.
  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  for r in
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           (select count(*) from cron.job_run_details d where d.jobid=j.jobid) as history_rows,
           (select max(d.start_time) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='succeeded') as last_ok,
           (select count(*) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='failed'
               and d.start_time > now() - interval '24 hours') as fails_24h,
           (select s.first_seen from cron_job_seen s where s.jobid=j.jobid) as first_seen
      from cron.job j where j.active
  loop
    -- Never-run jobs: previously skipped outright. Now alerted once the job has been
    -- known for longer than its own expected interval.
    if r.history_rows = 0 then
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
        g := g + 1;   -- within grace period; first slot has not come round yet
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success in retained history'),
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
        -- previously wrote no notification, so failing jobs raised no email
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
     set finished_at=now(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=now(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;
