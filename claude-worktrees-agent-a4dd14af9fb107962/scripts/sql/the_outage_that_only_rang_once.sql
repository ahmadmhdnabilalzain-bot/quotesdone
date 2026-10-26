-- fn_backup_watch rang once for a two-day outage. See the comments inside.
-- Definition otherwise byte-identical to production on 13 Aug 2026.

CREATE OR REPLACE FUNCTION public.fn_backup_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- A DEDUPE WINDOW THE SAME LENGTH AS THE CHECK INTERVAL SUPPRESSES ON A KNIFE EDGE (13 Aug 2026).
  -- The backup was broken from 10 to 12 August and this watcher produced exactly ONE alert:
  -- agent_action 2662 at 2026-08-11 08:00:00.63, one email, still pending. The watcher runs daily
  -- at 08:00, and the previous row was 24 hours old minus a fraction of a second, so it was still
  -- inside `created_at > now() - 24 hours` and the second day's alert was skipped. Twenty hours is
  -- strictly shorter than the cadence, so a daily check always re-alerts on a continuing outage
  -- while a ten-minute caller still cannot spam.
      and created_at > now()-interval '20 hours';

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
    -- AN OUTAGE THAT LASTS MUST GET LOUDER, NOT REPEAT ITSELF. One identical email a day says the
    -- same thing on day one and on day five, and the day-five reader has already filed the day-one
    -- copy. Past 48 hours this also raises a founder_alert and states the age in hours, which is
    -- the number that decides whether this is a hiccup or a company with no restorable backup.
    if v_last is null or v_last < now() - interval '48 hours' then
      insert into founder_alerts(level,event,detail,channel)
      values('crit','backup_outage_prolonged',
        'The daily logical backup has now been failing for '
        || coalesce(round(extract(epoch from (now()-v_last))/3600)::text || ' hours', 'as long as there are records')
        || ' (last run: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')
        || '). This is past the point where one more day of silence is acceptable: verify the backup '
        || 'function itself, then run dr_drill to prove the newest backup still restores.','system');
    end if;

  end if;
  return jsonb_build_object('alerted',true,'last',v_last,'status',v_status,'existing_open',v_open);
end $function$
;
