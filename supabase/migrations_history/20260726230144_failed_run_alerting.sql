-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726230144   name: failed_run_alerting
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- P1: scheduled runs have been failing nightly with nobody told.
-- Deterministic watchdog: no LLM, no cost. Dedupe key prevents alert storms.
create table if not exists public.alert_watermark (
  watcher     text primary key,
  last_run_at timestamptz not null default now(),
  last_alert_at timestamptz
);
alter table public.alert_watermark enable row level security;

create or replace function public.fn_watch_failed_runs()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $fn$
declare
  v_since   timestamptz;
  v_fail    record;
  v_alerts  int := 0;
  v_detail  text := '';
  v_secret  text;
  v_url     text := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/alert_founder';
begin
  select coalesce(last_run_at, now() - interval '24 hours') into v_since
    from alert_watermark where watcher = 'failed_runs';
  if not found then
    insert into alert_watermark (watcher, last_run_at) values ('failed_runs', now() - interval '24 hours');
    v_since := now() - interval '24 hours';
  end if;

  -- Group failures by agent since the last check.
  for v_fail in
    select agent, count(*) as fails, max(started_at) as latest,
           left(coalesce(max(note),''), 300) as sample_note
    from agent_runs
    where started_at > v_since and status = 'error'
    group by agent order by count(*) desc
  loop
    v_detail := v_detail || v_fail.agent || ': ' || v_fail.fails || ' failure(s). ' || v_fail.sample_note || E'\n';
    v_alerts := v_alerts + 1;
  end loop;

  if v_alerts > 0 then
    select value into v_secret from app_secrets where key = 'inbound_secret';
    perform net.http_post(
      url := v_url,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        '__secret', v_secret,
        'event', 'Scheduled runs failed (' || v_alerts || ' agent(s))',
        'detail', v_detail,
        'level', 'error',
        'dedupe_key', 'failed_runs:' || to_char(now(),'YYYY-MM-DD-HH24')
      ),
      timeout_milliseconds := 20000
    );
    update alert_watermark set last_alert_at = now() where watcher = 'failed_runs';
  end if;

  update alert_watermark set last_run_at = now() where watcher = 'failed_runs';
  return jsonb_build_object('checked_since', v_since, 'agents_failing', v_alerts, 'alerted', v_alerts > 0);
end;
$fn$;

-- Also watch company goals that are measurably off target.
create or replace function public.fn_watch_health()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $fn$
declare
  v_score numeric;
  v_at_risk text;
  v_secret text;
begin
  select overall_score_measurable into v_score from v_business_health;
  select string_agg(department || ' ' || score || '% (' || basis || ')', E'\n')
    into v_at_risk from v_department_health where status = 'at risk';

  if v_at_risk is not null then
    select value into v_secret from app_secrets where key = 'inbound_secret';
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/alert_founder',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        '__secret', v_secret,
        'event', 'Business health ' || v_score || '% - department(s) at risk',
        'detail', v_at_risk,
        'level', 'warn',
        'dedupe_key', 'health:' || to_char(now(),'YYYY-MM-DD')
      ),
      timeout_milliseconds := 20000);
  end if;
  return jsonb_build_object('score', v_score, 'at_risk', coalesce(v_at_risk,'none'));
end;
$fn$;

comment on function public.fn_watch_failed_runs is 'Deterministic watchdog: alerts the founder when scheduled runs fail. No LLM, no cost.';
