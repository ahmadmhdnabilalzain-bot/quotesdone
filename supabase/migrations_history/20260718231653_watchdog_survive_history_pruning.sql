-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260718231653   name: watchdog_survive_history_pruning
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- DEFECT FIX. cron_history_prune deletes cron.job_run_details older than 14 days, but the
-- watchdog's thresholds run to 336h (weekly) and 1440h (monthly/quarterly). Once history is
-- pruned, history_rows falls to 0 and a healthy monthly job drops into the "never ran" branch,
-- producing a FALSE cron_never_ran alert. Persist the last observed success in cron_job_seen
-- so knowledge of a successful run outlives the pruned history.

alter table public.cron_job_seen add column if not exists last_success timestamptz;

comment on column public.cron_job_seen.last_success is
  'Last success observed by fn_agent_silence_watch. Survives cron_history_prune (14d retention), which is shorter than the monthly/quarterly alert thresholds (60d).';

-- Seed from whatever history still exists so the fix is effective immediately.
update public.cron_job_seen s
   set last_success = h.last_ok
  from (select jobid, max(start_time) as last_ok
          from cron.job_run_details where status = 'succeeded' group by jobid) h
 where h.jobid = s.jobid
   and (s.last_success is null or s.last_success < h.last_ok);

create or replace function public.fn_agent_silence_watch()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           (select count(*) from cron.job_run_details d where d.jobid=j.jobid) as history_rows,
           -- effective last success: live history OR the value we persisted before pruning
           greatest(
             (select max(d.start_time) from cron.job_run_details d
               where d.jobid=j.jobid and d.status='succeeded'),
             (select s.last_success from cron_job_seen s where s.jobid=j.jobid)
           ) as last_ok,
           (select count(*) from cron.job_run_details d
             where d.jobid=j.jobid and d.status='failed'
               and d.start_time > now() - interval '24 hours') as fails_24h,
           (select s.first_seen from cron_job_seen s where s.jobid=j.jobid) as first_seen,
           (select s.last_success from cron_job_seen s where s.jobid=j.jobid) as stored_ok
      from cron.job j where j.active
  loop
    -- Never-run: only when there is NO history AND we have never recorded a success.
    -- Previously a pruned-history monthly job hit this branch and false-alarmed.
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
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
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
