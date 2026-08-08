-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710204533   name: backup_failure_watch
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_backup_watch()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_last timestamptz; v_status text; v_stale boolean; v_owner text; v_open int;
begin
  select started_at, status into v_last, v_status
    from agent_runs where agent='backup' order by started_at desc limit 1;
  v_stale := (v_last is null) or (v_last < now() - interval '26 hours') or (coalesce(v_status,'')='error');
  if not v_stale then
    return jsonb_build_object('ok',true,'last',v_last,'status',v_status);
  end if;
  select count(*) into v_open from agent_actions
    where kind='backup_alert' and coalesce(status,'') in ('pending','needs_review')
      and created_at > now()-interval '24 hours';
  if v_open = 0 then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
    values('security','backup_alert','pending','high',
      'Backup may have failed or is overdue',
      'The daily logical backup has not completed successfully in the last 26 hours (last: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')||'). Check the backup function and logs. Managed daily backups and the Dropbox mirror remain as fallbacks.',
      'agent_runs', jsonb_build_object('last_backup',v_last,'last_status',v_status));
    insert into security_events(kind,severity,source,subject,detail)
    values('backup_overdue','high','backup','logical backup',
      jsonb_build_object('last_backup',v_last,'last_status',v_status));
    select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
      from app_secrets where key='admin_emails';
    insert into notifications(type,to_email,to_role,channel,subject,body,status)
    values('backup_alert', v_owner, 'admin','email','QuotesDone: backup overdue or failed',
      'The daily logical backup has not completed in the last 26 hours (last: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')||'). Please check. Managed daily backups + the Dropbox mirror remain as fallbacks.','queued');
  end if;
  return jsonb_build_object('alerted',true,'last',v_last,'status',v_status,'existing_open',v_open);
end $$;

select cron.schedule('backup_watch_daily','0 8 * * *', $$select public.fn_backup_watch();$$);
