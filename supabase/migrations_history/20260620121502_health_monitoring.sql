-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260620121502   name: health_monitoring
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.health_state (id int primary key, last_run timestamptz, last_status text, last_alert_at timestamptz);
insert into public.health_state(id) values (1) on conflict (id) do nothing;

create or replace function public.run_health_check() returns json language plpgsql security definer as $f$
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

  if stuck > 0 then issues := issues || ('Email queue stuck: '||stuck||' email(s) queued >1h — the email cron / Resend may be down.'); end if;
  if failed > 25 then issues := issues || ('High email failures: '||failed||' failed in 24h — check Resend domain auth.'); end if;
  if coalesce(dirty_stuck,false) then issues := issues || ('Auto-deploy stuck: a page change has not deployed in 20+ min — check the Vercel token / cron.'); end if;
  -- sms only flagged if a sender is configured (else it is expected to sit)
  if sms_stuck > 0 and exists (select 1 from public.app_secrets where key='twilio_account_sid' and value is not null and value<>'') then
     issues := issues || ('SMS queue stuck: '||sms_stuck||' SMS queued >30min.'); end if;

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
end $f$;

select cron.schedule('health_check','*/30 * * * *', $cr$select public.run_health_check()$cr$);
