-- Layer 2 (resilience): pipeline-liveness watchdog with self-heal + immediate escalation.
-- Complements fn_ops_watch (abuse/cost/error detection) — this watches that the company's
-- critical pipelines are actually ALIVE, heals the safe ones, and pages the founder the moment
-- something would genuinely stop the business (so a week-long absence never hides an outage).
-- Heartbeats use ops_watch/ai_health (which log unconditionally); send_outbox/email_cron are
-- silent-when-idle so email LIVENESS is measured by backlog, not by a heartbeat.
create or replace function public.fn_resilience_watch()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_run bigint; v_owner text; v_secret text;
  v_base text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/';
  v_email_backlog int := 0; v_prev_backlog int; v_flushed boolean := false;
  v_email_on text; v_stripe text; v_kill text;
  v_last_ops timestamptz; v_last_ai timestamptz; v_match_stuck int := 0;
  v_missing text[] := '{}'; k text; v_issues text := ''; v_heals int := 0; v_alerts int := 0;
  v_deduped boolean;
begin
  select value into v_secret from app_secrets where key='inbound_secret';
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';
  v_owner := coalesce(nullif(btrim(v_owner),''),'management@quotesdone.com');
  insert into agent_runs(agent,started_at) values('resilience_watch',clock_timestamp()) returning id into v_run;

  -- 1. EMAIL PIPELINE liveness + safe self-heal (idempotent flush; respects cap/suppressions).
  select value into v_email_on from app_secrets where key='email_enabled';
  select count(*) into v_email_backlog from notifications
    where channel='email' and coalesce(status,'queued') in ('queued','pending') and created_at < now()-interval '15 minutes';
  if v_email_backlog>0 and coalesce(v_email_on,'')='true' and v_secret is not null then
    perform net.http_post(url:=v_base||'send_outbox',
      headers:='{"Content-Type":"application/json"}'::jsonb,
      body:=jsonb_build_object('__secret',v_secret,'limit',50), timeout_milliseconds:=20000);
    v_flushed := true; v_heals := v_heals+1;
    select (counts->>'email_backlog')::int into v_prev_backlog from agent_runs
      where agent='resilience_watch' and id<>v_run order by id desc limit 1;
    if coalesce(v_prev_backlog,0)>0 then
      v_issues := v_issues||'- Email pipeline STUCK: '||v_email_backlog||' message(s) undelivered >15min despite auto-flush.'||E'\n';
    end if;
  end if;

  -- 2. CRITICAL credentials present (a missing one silently kills a whole flow).
  foreach k in array array['openrouter_api_key','resend_api_key','stripe_secret_key','inbound_secret'] loop
    if not exists(select 1 from app_secrets where key=k and value is not null and length(btrim(value))>0) then
      v_missing := array_append(v_missing,k);
    end if;
  end loop;
  if array_length(v_missing,1)>0 then
    v_issues := v_issues||'- CRITICAL credential(s) MISSING: '||array_to_string(v_missing,', ')||' — dependent flows are down.'||E'\n';
  end if;
  select left(value,8) into v_stripe from app_secrets where key='stripe_secret_key';
  if v_stripe is not null and v_stripe not like 'sk_live_%' then
    v_issues := v_issues||'- Stripe key is NOT live mode — payments will not settle.'||E'\n';
  end if;
  select value into v_kill from app_secrets where key='ai_kill_switch';
  if coalesce(v_kill,'')='true' then
    v_issues := v_issues||'- AI kill-switch is ON — every AI agent is paused.'||E'\n';
  end if;

  -- 3. SCHEDULER heartbeat via always-logging agents (catches a degraded pg_cron while it still partly runs).
  select max(started_at) into v_last_ops from agent_runs where agent='ops_watch' and started_at>now()-interval '4 hours';
  select max(started_at) into v_last_ai  from agent_runs where agent='ai_health' and started_at>now()-interval '4 hours';
  if v_last_ops is null or v_last_ops < now()-interval '90 minutes' then
    v_issues := v_issues||'- Ops-watch heartbeat stale (>90min) — the scheduler may be degraded.'||E'\n';
  end if;
  if v_last_ai is null or v_last_ai < now()-interval '45 minutes' then
    v_issues := v_issues||'- AI-health heartbeat stale (>45min) — the scheduler or AI monitor may be down.'||E'\n';
  end if;

  -- 4. MATCHING liveness: open inquiries with no shortlist after 6h.
  select count(*) into v_match_stuck from inquiries i
    where i.created_at between now()-interval '24 hours' and now()-interval '6 hours'
      and i.status not in ('completed','accepted','closed','cancelled','draft')
      and not exists(select 1 from inquiry_matches m where m.inquiry_id=i.id);
  if v_match_stuck>0 then
    v_issues := v_issues||'- '||v_match_stuck||' inquiry(ies) unmatched for >6h — the matcher may be stuck.'||E'\n';
  end if;

  -- ESCALATE: resilience failures would actually STOP the business, so page immediately
  -- (bypasses the Phase-B digest) — deduped to once per 3h via a silent marker row.
  if v_issues<>'' then
    select exists(select 1 from notifications where type='resilience_alert' and created_at>now()-interval '3 hours') into v_deduped;
    if not v_deduped and v_secret is not null then
      perform net.http_post(url:=v_base||'alert_founder',
        headers:='{"Content-Type":"application/json"}'::jsonb,
        body:=jsonb_build_object('__secret',v_secret,'event','Resilience: the platform needs attention',
          'level','critical','dedupe_key','resilience',
          'detail','The self-healing watchdog found issues it could not auto-fix:'||E'\n'||v_issues),
        timeout_milliseconds:=20000);
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('resilience_alert',v_owner,'admin','email','QuotesDone resilience: action needed',v_issues,'digested');
      v_alerts := v_alerts+1;
    end if;
  end if;

  update agent_runs set finished_at=clock_timestamp(),
    status=case when v_issues<>'' then 'error' else 'ok' end,
    counts=jsonb_build_object('email_backlog',v_email_backlog,'flushed',v_flushed,'heals',v_heals,'alerts',v_alerts,'has_issues',(v_issues<>'')),
    note=coalesce(nullif(v_issues,''),'all critical pipelines healthy')
    where id=v_run;
  return jsonb_build_object('ok',true,'email_backlog',v_email_backlog,'flushed',v_flushed,'issues',nullif(v_issues,''),'alerts',v_alerts);
end $function$;

revoke execute on function public.fn_resilience_watch() from public, anon, authenticated;
grant execute on function public.fn_resilience_watch() to service_role;

-- schedule every 10 minutes (idempotent: drop any prior definition of the same job first)
do $$ begin perform cron.unschedule('resilience_watch_10min'); exception when others then null; end $$;
select cron.schedule('resilience_watch_10min', '*/10 * * * *', 'select public.fn_resilience_watch()');
