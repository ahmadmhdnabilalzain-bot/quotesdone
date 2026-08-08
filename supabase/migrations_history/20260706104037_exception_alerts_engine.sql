-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706104037   name: exception_alerts_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ LEVEL 4: exception alerts ============
create or replace function public.fn_exception_alerts()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  rev_today numeric; rev_prev numeric;
  gw_bad int; q24 int; qpass24 int; last_backup timestamptz;
  fired text[] := '{}';
  procedure_note text;
begin
  -- helper: only fire if same event not raised in last 12h
  -- 1) revenue drop > 20% day-over-day (needs a meaningful prior day)
  select coalesce(sum(reveal_fee),0) into rev_today from transactions
    where revealed_at::date = current_date and coalesce(refund_status,'')<>'approved';
  select coalesce(sum(reveal_fee),0) into rev_prev from transactions
    where revealed_at::date = current_date-1 and coalesce(refund_status,'')<>'approved';
  if rev_prev >= 100 and rev_today < rev_prev*0.8 then
     if not exists(select 1 from founder_alerts where event='revenue_drop' and created_at>now()-interval '12 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','revenue_drop','Revenue AED '||round(rev_today)||' today vs AED '||round(rev_prev)||' yesterday (>20% drop).','email');
        fired := array_append(fired,'revenue_drop'); end if;
  end if;

  -- 2) payment gateway offline (latest stripe health check failing in last hour)
  select count(*) into gw_bad from health_checks
    where created_at>now()-interval '1 hour' and not ok
      and (lower(coalesce(check_kind,'')) like '%stripe%' or lower(coalesce(target,'')) like '%stripe%' or lower(coalesce(check_kind,'')) like '%pay%');
  if gw_bad > 0 then
     if not exists(select 1 from founder_alerts where event='gateway_offline' and created_at>now()-interval '3 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','gateway_offline','Payment gateway health check failing in the last hour.','email');
        fired := array_append(fired,'gateway_offline'); end if;
  end if;

  -- 3) AI confidence / quote-quality below threshold (proxy: gate pass-rate collapse with volume)
  select count(*) filter (where quality is not null),
         count(*) filter (where nullif(quality->>'score','')::numeric >= 60)
    into q24, qpass24 from quotes where created_at>now()-interval '24 hours';
  if q24 >= 5 and qpass24::numeric/nullif(q24,0) < 0.5 then
     if not exists(select 1 from founder_alerts where event='ai_confidence_low' and created_at>now()-interval '12 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('warning','ai_confidence_low','Quote-quality gate pass rate '||round(qpass24::numeric/q24*100)||'% over last 24h ('||q24||' quotes) — below 50% threshold.','email');
        fired := array_append(fired,'ai_confidence_low'); end if;
  end if;

  -- 4) backup stale (no backup manifest in > 8 days)
  select max(updated_at) into last_backup from storage.objects where bucket_id='backups' and name like '%/_manifest.json';
  if last_backup is null or last_backup < now()-interval '8 days' then
     if not exists(select 1 from founder_alerts where event='backup_stale' and created_at>now()-interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel) values
          ('critical','backup_stale','No fresh backup manifest in over 8 days (last: '||coalesce(last_backup::text,'never')||').','email');
        fired := array_append(fired,'backup_stale'); end if;
  end if;

  -- surface criticals as founder notifications too
  insert into notifications(type,to_role,channel,subject,body)
  select 'exception_alert','admin','email','QuotesDone ALERT: '||event, detail
  from founder_alerts fa
  where fa.created_at>now()-interval '2 minutes' and fa.level='critical'
    and not exists(select 1 from notifications n where n.type='exception_alert' and n.subject='QuotesDone ALERT: '||fa.event and n.created_at>now()-interval '3 hours');

  return jsonb_build_object('fired', to_jsonb(fired), 'rev_today',rev_today,'rev_prev',rev_prev,'checked_at',now());
end $$;

select cron.schedule('exception_alerts_hourly','35 * * * *', $$select public.fn_exception_alerts();$$);
select public.fn_exception_alerts() as first_run;
