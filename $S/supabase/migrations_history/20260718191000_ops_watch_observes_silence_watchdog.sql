-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260718191000   name: ops_watch_observes_silence_watchdog
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- fn_ops_watch runs hourly and is independently proven, so it is the natural place to
-- observe the daily silence watchdog. Without this, a dead watchdog is undetectable.
create or replace function public.fn_ops_watch()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_run bigint; v_ai_1h int; v_ai_24h int; v_top_email text; v_top_cnt int; v_err6h int; v_runerr6h int; v_spammer record; v_owner text; v_alerts int:=0;
  function_alerted boolean;
  v_wd_last timestamptz; v_wd_seen timestamptz;
begin
  insert into agent_runs(agent,started_at) values('ops_watch',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  select count(*) into v_ai_1h from ai_usage where created_at>=now()-interval '1 hour';
  select count(*) into v_ai_24h from ai_usage where created_at>=now()-interval '24 hours';
  select email,count(*) into v_top_email,v_top_cnt from ai_usage where created_at>=now()-interval '24 hours' group by email order by count(*) desc limit 1;
  select count(*) into v_err6h from error_events where created_at>=now()-interval '6 hours' and severity in ('error','high','critical');
  select count(*) into v_runerr6h from agent_runs where status='error' and started_at>=now()-interval '6 hours';

  -- helper: only alert if we have not emailed this ops_alert type in the last 6h
  if (v_ai_1h > coalesce((select value::int from app_secrets where key='ai_cost_alert_hourly'),300))
     or (v_ai_24h > coalesce((select value::int from app_secrets where key='ai_cost_alert_daily'),2500)) then
    insert into error_events(source,kind,severity,detail) values('ops_watch','ai_cost_spike','high',jsonb_build_object('last_hour',v_ai_1h,'last_24h',v_ai_24h,'top_email',v_top_email,'top_count',v_top_cnt));
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: AI usage spike%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: AI usage spike',
        'AI calls in last hour: '||v_ai_1h||', last 24h: '||v_ai_24h||'. Heaviest user: '||coalesce(v_top_email,'?')||' ('||coalesce(v_top_cnt,0)||'). Check for abuse or runaway cost. You can set ai_kill_switch=true to pause AI.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  if v_err6h > 20 or v_runerr6h > 10 then
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: error spike%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: error spike',
        'Errors in last 6h: '||v_err6h||' app errors, '||v_runerr6h||' failed agent runs. Open the IT agent to investigate.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  -- inquiry spam: any customer with > 40 inquiries in 24h
  for v_spammer in select customer_id, count(*) c from inquiries where created_at>=now()-interval '24 hours' group by customer_id having count(*)>40 loop
    insert into error_events(source,kind,severity,detail) values('ops_watch','inquiry_spam','medium',jsonb_build_object('customer_id',v_spammer.customer_id,'count',v_spammer.c));
    v_alerts:=v_alerts+1;
  end loop;

  -- watchdog-of-the-watchdog: the daily silence watch must leave an ok run every 24h.
  -- Grace: stay quiet until the job has been registered for 48h, so a newly created
  -- watchdog whose first slot has not arrived does not trigger a false alarm.
  select max(started_at) into v_wd_last from agent_runs
    where agent='agent_silence_watch' and status='ok' and started_at >= now()-interval '48 hours';
  select first_seen into v_wd_seen from cron_job_seen where jobname='agent_silence_watch_daily';

  if v_wd_last is null and v_wd_seen is not null and v_wd_seen < now()-interval '48 hours' then
    insert into error_events(source,kind,severity,detail)
      values('ops_watch','watchdog_silent','critical',
             jsonb_build_object('agent','agent_silence_watch','registered_since',v_wd_seen,
                                'note','no successful run in 48h - cron failures are going unobserved'));
    select exists(select 1 from notifications where type='ops_alert' and subject like 'QuotesDone: cron watchdog is down%' and created_at>=now()-interval '6 hours') into function_alerted;
    if v_owner is not null and not function_alerted then
      insert into notifications(type,to_email,to_role,channel,subject,body) values('ops_alert',v_owner,'admin','email','QuotesDone: cron watchdog is down',
        'agent_silence_watch has not completed successfully in 48 hours. While it is down, failing or stalled scheduled jobs will not raise alerts. Check that the agent_silence_watch_daily cron job is registered and running.');
      v_alerts:=v_alerts+1;
    end if;
  end if;

  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('ai_1h',v_ai_1h,'ai_24h',v_ai_24h,'err6h',v_err6h,'run_err6h',v_runerr6h,'alerts',v_alerts,'watchdog_ok',(v_wd_last is not null)) where id=v_run;
end; $function$;
