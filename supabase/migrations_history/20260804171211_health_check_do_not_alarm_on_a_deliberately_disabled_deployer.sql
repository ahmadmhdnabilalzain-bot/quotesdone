-- 4 Aug 2026, immediately after unbreaking run_health_check(). Fixing the crash exposed the
-- second half of the problem: `dirty_stuck` is true because auto_deploy and site_autodeploy are
-- DELIBERATELY disabled (containment hold, founder decision 1, containment.cron_disabled ids 5
-- and 31). deploy_state.dirty can therefore never clear, so the check is structurally guaranteed
-- to fire on every 30-minute run, forever. Turning a crash into a permanent alert is not a fix -
-- it is the same monitor being useless in the other direction, and it would bury the checks that
-- do mean something.
--
-- Gate it on the deployer actually being scheduled, exactly as the SMS branch is already gated on
-- a sender being configured. When the two deploy jobs come back under Workstream J the check
-- re-arms itself with no further change.
CREATE OR REPLACE FUNCTION public.run_health_check()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare issues text[] := '{}'; stuck int; failed int; dirty_stuck boolean; inq int; q int; pend int; sms_stuck int; alert_recent boolean;
begin
  select count(*) into stuck from public.notifications
    where coalesce(status,'queued')='queued' and coalesce(channel,'email')<>'sms' and created_at < now()-interval '60 minutes';
  select count(*) into failed from public.notifications where status='failed' and created_at > now()-interval '24 hours';
  select count(*) into sms_stuck from public.notifications where channel='sms' and coalesce(status,'queued')='queued' and created_at < now()-interval '30 minutes';
  select (dirty and coalesce(last_deploy, '2000-01-01') < now()-interval '20 minutes') into dirty_stuck from public.deploy_state where id=1;
  select count(*) into inq from public.inquiries where created_at > now()-interval '24 hours';
  select count(*) into q from public.quotes where created_at > now()-interval '24 hours';
  select count(*) into pend from public.transactions where refund_status='requested';

  -- The ::text casts are load-bearing. `text[] || 'a bare literal'` resolves to anyarray||anyarray
  -- because an unadorned literal is type `unknown`, so Postgres parses the sentence as an array
  -- literal and raises 22P02. The sibling lines survived only because concatenating an int types
  -- the expression as text. 78 of 336 runs died here in the week to 4 Aug 2026 - the monitor
  -- crashed precisely when it had something to report, and took the other checks down with it.
  if stuck > 0 then issues := issues || ('Email queue stuck: '||stuck||' email(s) queued >1h — the email cron / Resend may be down.')::text; end if;
  if failed > 25 then issues := issues || ('High email failures: '||failed||' failed in 24h — check Resend domain auth.')::text; end if;
  -- only flagged while a deployer is actually scheduled; both deploy jobs are held disabled, so
  -- dirty can never clear and an ungated check would alert every 30 minutes about a decision.
  if coalesce(dirty_stuck,false)
     and exists (select 1 from cron.job where jobname in ('auto_deploy','site_autodeploy') and active) then
     issues := issues || ('Auto-deploy stuck: a page change has not deployed in 20+ min — check the Vercel token / cron.')::text; end if;
  -- sms only flagged if a sender is configured (else it is expected to sit)
  if sms_stuck > 0 and exists (select 1 from public.app_secrets where key='twilio_account_sid' and value is not null and value<>'') then
     issues := issues || ('SMS queue stuck: '||sms_stuck||' SMS queued >30min.')::text; end if;

  update public.health_state set last_run=now(), last_status=(case when array_length(issues,1) is null then 'ok' else 'issues' end) where id=1;
  select (last_alert_at > now()-interval '6 hours') into alert_recent from public.health_state where id=1;

  if array_length(issues,1) is not null and not coalesce(alert_recent,false) then
    insert into public.notifications(type,to_email,to_role,subject,body,status)
    select 'health_alert', trim(split_part(value,',',1)), 'admin', 'QuotesDone system health alert',
      'Automated check found issue(s):'||chr(10)||'- '||array_to_string(issues, chr(10)||'- ')||chr(10)||chr(10)||
      'Last 24h: '||inq||' inquiries, '||q||' quotes. Pending refund requests: '||pend||'.'||chr(10)||
      'Open the admin dashboard to investigate.', 'queued'
    from public.app_secrets where key='admin_emails';
    update public.health_state set last_alert_at=now() where id=1;
  end if;

  return json_build_object('ok',true,'status',(case when array_length(issues,1) is null then 'ok' else 'issues' end),'issues',to_jsonb(issues),'stuck_emails',stuck,'failed_24h',failed,'inq_24h',inq,'q_24h',q,'pending_refunds',pend);
end $function$;;
