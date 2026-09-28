-- THE IT ENGINEER BREAKS THE COMPANY ONCE A MONTH, ON PURPOSE, TO PROVE IT NOTICES AND HEALS.
-- Seat: it_engineer. 28 Sep 2026, founder_instruction 1009 (upgrade 9): monthly game days. The IT engineer
-- deliberately injects a fault, sandbox-safe, and proves the system detects it and recovers:
--   email provider down  -> sends are kept for retry and an alert fires;
--   WhatsApp down        -> SMS failover, and the email twin still goes (ruling 994);
--   slow edge function   -> the latency SLI fires;
--   database connections -> the connection-saturation alert fires;
--   expired credential   -> the credential-expiry (rotation) alert fires.
-- Each scenario records detection time, recovery time and pass/fail, opens a finding when it fails, and the
-- results reach the CEO's weekly report.
--
-- HOW A SCENARIO STAYS SANDBOX-SAFE. Every scenario runs inside its own plpgsql BEGIN ... EXCEPTION block, which
-- is a savepoint. It injects the fault, calls the REAL detector (not a copy of its logic), measures, removes the
-- fault, calls the detector again, measures, and then RAISES, so the savepoint rolls back everything it wrote:
-- the fixture rows, the findings it opened and closed, any notification or pg_net request a detector queued.
-- Only the measurements survive, in plpgsql variables, and are written to public.it_game_day_run afterwards.
-- On top of the rollback, every injected row is fixture traffic that cannot reach a person even if it escaped:
-- notifications go to zz-game-day@example.invalid and the reserved fixture mobile +971500000099 (both captured
-- by zzzz_notifications_demo_capture), the edge runs are under the fictitious slug fn:zz_game_day_slow, and the
-- credential is a ZZ DEMO legacy row whose hash is random. After each scenario the runner counts what it left
-- behind; anything left is a failure and a finding.
--
-- WHAT EACH SCENARIO CAN AND CANNOT PROVE (said here so nobody reads more into a green row than it measured):
--   email_provider_down: injects a failing Resend reading into fn_it_integration_settle (the real alert door the
--     itintegrations step uses; every open integration finding is carried unchanged). Proves duty:integration:resend
--     opens and closes again, and that a notice written during the outage stays in public.notifications, unsent,
--     after send_outbox's failure transition (attempts + 1, back to queued below its MAX_ATTEMPTS of 3). It does
--     not run send_outbox itself: the transition is applied as that code writes it.
--   whatsapp_down: opens duty:integration:twilio_whatsapp_sender (what _shared/whatsapp_failover.ts reads as
--     "WhatsApp is down"), then runs fn_wa_sms_twin twice on a demo notice. Proves one SMS twin, the WhatsApp row
--     leaving the queue, and the email twin of the same notice untouched. It does not call Twilio.
--   edge_function_slow: 30 fixture runs at 9,000 ms against a 1,000 ms budget, then fn_it_engineer_latency_slo.
--   db_connection: sets it_threshold connections_ratio_max to 0 (so every open connection counts as saturation),
--     makes db_health due, runs fn_it_duties_scheduled. It cannot sever a real connection from inside one; what
--     it proves is that the saturation that precedes "too many connections" is detected and clears.
--   credential_expired: a legacy internal credential expired an hour ago, then fn_it_duties' expiry section; the
--     fix is retiring it, and the finding must close.
--
-- WHAT THIS DOES NOT CHANGE: no detector, threshold or send path. fn_ceo_weekly_report is redefined verbatim from
-- the_ceo_writes_the_whole_company_report_and_names_what_is_holding_it_back.sql with one section added (GAME DAY)
-- and search_path pinned with pg_temp.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_breaks_the_company_once_a_month_to_prove_it_heals.sql --apply --ddl
--   pure probe after the apply: scripts/sql/the_it_engineer_breaks_the_company_once_a_month_to_prove_it_heals_probe.sql

-- ── the record ────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_game_day_run (
  id            bigserial primary key,
  run_month     date not null check (run_month = date_trunc('month', run_month)::date),
  scenario      text not null check (scenario in ('email_provider_down', 'whatsapp_down', 'edge_function_slow',
                                                  'db_connection', 'credential_expired')),
  ran_at        timestamptz not null default now(),
  detected      boolean not null,
  recovered     boolean not null,
  passed        boolean not null,
  detection_ms  numeric,      -- fault injected -> the detector's finding is open
  recovery_ms   numeric,      -- fault removed  -> the detector's finding is closed
  checks        jsonb not null default '{}'::jsonb,
  error         text,
  unique (run_month, scenario)
);
alter table public.it_game_day_run enable row level security;
drop policy if exists it_game_day_run_service_role_only on public.it_game_day_run;
create policy it_game_day_run_service_role_only on public.it_game_day_run as permissive for all to public using (false) with check (false);
revoke all on public.it_game_day_run from anon, authenticated;

-- ── shared: the open integration findings, carried unchanged into an injected settle ──────────────────
create or replace function public.fn_it_game_day_integration_items(p_except text)
returns jsonb language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('item', substring(f.issue_key from length('duty:integration:') + 1),
                                               'title', f.title, 'carried', true)), '[]'::jsonb)
    from public.it_engineer_finding f
   where f.closed_at is null and f.issue_key like 'duty:integration:%'
     and f.issue_key <> 'duty:integration:' || p_except
$fn$;
revoke execute on function public.fn_it_game_day_integration_items(text) from public, anon, authenticated;

create or replace function public.fn_it_game_day_open(p_key text)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (select 1 from public.it_engineer_finding where issue_key = p_key and closed_at is null)
$fn$;
revoke execute on function public.fn_it_game_day_open(text) from public, anon, authenticated;

-- ── scenario 1: the email provider is down ────────────────────────────────────────────────────────
create or replace function public.fn_it_game_day_email_provider_down()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; n public.notifications; v_id bigint; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz;
  v_det boolean; v_rec boolean; v_pre boolean;
begin
  begin
    v_pre := public.fn_it_game_day_open('duty:integration:resend');
    t_inj := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('resend') || jsonb_build_array(
      jsonb_build_object('item', 'resend', 'title', 'ZZ DEMO game day: Resend answered HTTP 503', 'owner_seat', 'customer_support',
        'subject', 'resend', 'blast', 'customer_facing', 'affected', 1, 'evidence', jsonb_build_object('game_day', true, 'notify', false))));
    v_det := public.fn_it_game_day_open('duty:integration:resend');
    t_det := clock_timestamp();

    -- a notice written during the outage, then send_outbox's failure transition
    insert into public.notifications (channel, status, type, to_email, to_role, subject, body, lang, requested_by)
    values ('email', 'queued', 'zz_game_day', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_id;
    update public.notifications set attempts = attempts + 1, status = 'queued', last_error = 'ZZ DEMO game day: Resend 503'
     where id = v_id;
    select * into n from public.notifications where id = v_id;

    t_fix := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('resend'));
    v_rec := not public.fn_it_game_day_open('duty:integration:resend');
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('alert_opened', v_det, 'alert_was_already_open', v_pre, 'alert_closed', v_rec,
        'notice_kept', n.id is not null, 'notice_unsent', n.sent_at is null and n.status <> 'sent',
        'attempts_counted', n.attempts = 1, 'notice_status', n.status));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean
        and (v#>>'{checks,notice_kept}')::boolean and (v#>>'{checks,notice_unsent}')::boolean and (v#>>'{checks,attempts_counted}')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $fn$;
revoke execute on function public.fn_it_game_day_email_provider_down() from public, anon, authenticated;

-- ── scenario 2: WhatsApp is down (ruling 994: SMS failover, the email twin still goes) ────────────
create or replace function public.fn_it_game_day_whatsapp_down()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; v_wa bigint; v_mail bigint; v_twins int; v_wa_status text; v_mail_status text; v_mail_before text;
  t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean; v_pre boolean;
  k constant text := 'duty:integration:twilio_whatsapp_sender';
begin
  begin
    -- one notice, the way producers write it: an email twin and a WhatsApp row, both to fixture identities
    insert into public.notifications (channel, status, type, to_email, to_role, subject, body, lang, requested_by)
    values ('email', 'queued', 'zz_game_day', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_mail;
    insert into public.notifications (channel, status, type, to_phone, to_email, to_role, subject, body, lang, requested_by)
    values ('whatsapp', 'queued', 'zz_game_day', '+971500000099', 'zz-game-day@example.invalid', 'customer', 'ZZ DEMO game day', 'ZZ DEMO game day', 'en', 'customer_support')
    returning id into v_wa;
    select status into v_mail_before from public.notifications where id = v_mail;

    v_pre := public.fn_it_game_day_open(k);
    t_inj := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('twilio_whatsapp_sender') || jsonb_build_array(
      jsonb_build_object('item', 'twilio_whatsapp_sender', 'title', 'ZZ DEMO game day: the WhatsApp sender is OFFLINE', 'owner_seat', 'customer_support',
        'subject', 'twilio_whatsapp_sender', 'blast', 'customer_facing', 'affected', 1, 'evidence', jsonb_build_object('game_day', true, 'notify', false))));
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    -- what send_whatsapp does for each row while the finding is open; twice, as two overlapping runs would
    perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO game day sms', 'game day: WhatsApp down');
    perform public.fn_wa_sms_twin(v_wa, 'ZZ DEMO game day sms', 'game day: WhatsApp down');
    select count(*) into v_twins from public.notifications where failover_of = v_wa and channel = 'sms';
    select status into v_wa_status from public.notifications where id = v_wa;
    select status into v_mail_status from public.notifications where id = v_mail;

    t_fix := clock_timestamp();
    perform public.fn_it_integration_settle('integration', public.fn_it_game_day_integration_items('twilio_whatsapp_sender'));
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('alert_opened', v_det, 'alert_was_already_open', v_pre, 'alert_closed', v_rec,
        'sms_twins', v_twins, 'whatsapp_left_queue', v_wa_status not in ('queued', 'sending'), 'whatsapp_status', v_wa_status,
        'email_twin_untouched', v_mail_status is not distinct from v_mail_before, 'email_status', v_mail_status));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean
        and (v#>>'{checks,sms_twins}')::int = 1 and (v#>>'{checks,whatsapp_left_queue}')::boolean
        and (v#>>'{checks,email_twin_untouched}')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $fn$;
revoke execute on function public.fn_it_game_day_whatsapp_down() from public, anon, authenticated;

-- ── scenario 3: a slow edge function (the latency SLI) ────────────────────────────────────────────
create or replace function public.fn_it_game_day_edge_function_slow()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:latency_slo:zz_game_day_slow';
begin
  begin
    t_inj := clock_timestamp();
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    select 'fn:zz_game_day_slow', 'ok', now() - make_interval(secs => g), now() - make_interval(secs => g),
           jsonb_build_object('ms', 9000, 'budget_ms', 1000, 'http', 200, 'method', 'POST', 'game_day', true), 'ZZ DEMO game day'
      from generate_series(1, 30) g;
    perform public.fn_it_engineer_latency_slo();
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    delete from public.agent_runs where agent = 'fn:zz_game_day_slow';
    perform public.fn_it_engineer_latency_slo();
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('sli_fired', v_det, 'sli_cleared', v_rec, 'runs', 30, 'p95_ms', 9000, 'budget_ms', 1000));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $fn$;
revoke execute on function public.fn_it_game_day_edge_function_slow() from public, anon, authenticated;

-- ── scenario 4: database connections ──────────────────────────────────────────────────────────────
create or replace function public.fn_it_game_day_db_connection()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; v_old numeric; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:db_health:connections';
begin
  begin
    select value into v_old from public.it_threshold where key = 'connections_ratio_max';
    if v_old is null then raise exception 'it_threshold connections_ratio_max is not set, so the detector has nothing to compare against'; end if;
    update public.it_duty_schedule set every = interval '5 minutes' where duty = 'db_health';   -- due now, and due again
    t_inj := clock_timestamp();
    update public.it_threshold set value = 0 where key = 'connections_ratio_max';
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    update public.it_threshold set value = v_old where key = 'connections_ratio_max';
    perform public.fn_it_duties_scheduled('{}'::jsonb);
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('saturation_alert', v_det, 'cleared', v_rec, 'ratio_max', v_old,
        'in_use', (select count(*) from pg_stat_activity), 'max', current_setting('max_connections')::int));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $fn$;
revoke execute on function public.fn_it_game_day_db_connection() from public, anon, authenticated;

-- ── scenario 5: an expired credential ─────────────────────────────────────────────────────────────
create or replace function public.fn_it_game_day_credential_expired()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb; v_id bigint; t_inj timestamptz; t_det timestamptz; t_fix timestamptz; t_rec timestamptz; v_det boolean; v_rec boolean;
  k constant text := 'duty:expiry:credential:zz_game_day.expired';
begin
  begin
    t_inj := clock_timestamp();
    insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, expires_at)
    values ('zz_game_day.expired', 'ZZ DEMO game day', 'zz-game-day-' || gen_random_uuid(), array['zz_game_day'], true, true, now() - interval '1 hour')
    returning id into v_id;
    perform public.fn_it_duties('{}'::jsonb);
    v_det := public.fn_it_game_day_open(k);
    t_det := clock_timestamp();

    t_fix := clock_timestamp();
    update public.internal_credential set active = false, retired_at = now() where id = v_id;   -- the fix: retired
    perform public.fn_it_duties('{}'::jsonb);
    v_rec := not public.fn_it_game_day_open(k);
    t_rec := clock_timestamp();

    v := jsonb_build_object('detected', v_det, 'recovered', v_rec,
      'detection_ms', round(extract(epoch from t_det - t_inj) * 1000, 1), 'recovery_ms', round(extract(epoch from t_rec - t_fix) * 1000, 1),
      'checks', jsonb_build_object('expiry_alert', v_det, 'cleared_after_retire', v_rec));
    raise exception 'QD_GAME_DAY_ROLLBACK';
  exception when others then
    if sqlerrm = 'QD_GAME_DAY_ROLLBACK' then
      return v || jsonb_build_object('passed', (v->>'detected')::boolean and (v->>'recovered')::boolean);
    end if;
    return jsonb_build_object('detected', false, 'recovered', false, 'passed', false, 'error', left(sqlerrm, 500));
  end;
end $fn$;
revoke execute on function public.fn_it_game_day_credential_expired() from public, anon, authenticated;

-- ── what a scenario must never leave behind ───────────────────────────────────────────────────────
create or replace function public.fn_it_game_day_leftovers()
returns int language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select (select count(*) from public.notifications where type = 'zz_game_day' or subject = 'ZZ DEMO game day')::int
       + (select count(*) from public.agent_runs where agent = 'fn:zz_game_day_slow')::int
       + (select count(*) from public.internal_credential where context like 'zz_game_day.%')::int
       + (select count(*) from public.it_engineer_finding where title like 'ZZ DEMO game day%' or issue_key like '%zz_game_day%')::int
$fn$;
revoke execute on function public.fn_it_game_day_leftovers() from public, anon, authenticated;

-- ── the duty: once per Dubai calendar month ───────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_game_day()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_month date := date_trunc('month', (now() at time zone 'Asia/Dubai')::date)::date;
  s text; r jsonb; v_left int; v_out jsonb := '[]'::jsonb; v_key text;
begin
  if (select count(*) from public.it_game_day_run where run_month = v_month) >= 5 then
    return jsonb_build_object('ran', false, 'reason', 'this month''s game day is recorded', 'month', v_month);
  end if;
  foreach s in array array['email_provider_down', 'whatsapp_down', 'edge_function_slow', 'db_connection', 'credential_expired'] loop
    continue when exists (select 1 from public.it_game_day_run where run_month = v_month and scenario = s);
    execute format('select public.%I()', 'fn_it_game_day_' || s) into r;
    v_left := public.fn_it_game_day_leftovers();
    if v_left > 0 then
      r := r || jsonb_build_object('passed', false, 'error', coalesce(r->>'error' || '; ', '') || v_left || ' fixture row(s) left behind');
    end if;
    insert into public.it_game_day_run (run_month, scenario, detected, recovered, passed, detection_ms, recovery_ms, checks, error)
    values (v_month, s, coalesce((r->>'detected')::boolean, false), coalesce((r->>'recovered')::boolean, false),
            coalesce((r->>'passed')::boolean, false), (r->>'detection_ms')::numeric, (r->>'recovery_ms')::numeric,
            coalesce(r->'checks', '{}'::jsonb) || jsonb_build_object('leftovers', v_left), r->>'error');

    v_key := 'game_day:' || s;
    if coalesce((r->>'passed')::boolean, false) then
      update public.it_engineer_finding set closed_at = now(), close_note = 'the ' || to_char(v_month, 'Mon YYYY') || ' game day passed'
       where issue_key = v_key and closed_at is null;
    else
      perform public.fn_it_engineer_finding_upsert(v_key,
        'Game day ' || to_char(v_month, 'Mon YYYY') || ': ' || replace(s, '_', ' ') || ' failed ('
          || case when r->>'error' is not null then left(r->>'error', 150)
                  when not coalesce((r->>'detected')::boolean, false) then 'the injected fault was not detected'
                  when not coalesce((r->>'recovered')::boolean, false) then 'the alert did not clear after the fix'
                  else 'a recovery check failed' end || ')',
        'public.it_game_day_run / fn_it_game_day_' || s, 'customer_facing', 1,
        r || jsonb_build_object('month', v_month, 'owner_seat', 'it_engineer'),
        '{}'::text[], array['why the detector or the recovery path did not behave as the scenario expects'], 'it_engineer');
    end if;
    v_out := v_out || jsonb_build_object('scenario', s, 'passed', r->'passed', 'detection_ms', r->'detection_ms', 'recovery_ms', r->'recovery_ms');
  end loop;
  return jsonb_build_object('ran', true, 'month', v_month, 'scenarios', v_out);
end $fn$;
revoke execute on function public.fn_it_engineer_game_day() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_game_day() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.game_day', 'it_engineer', interval '1 month', 'fn_it_engineer_game_day',
   'Monthly game day: five faults injected inside rolled-back savepoints on fixture traffic; detection and recovery timed; a failure is a finding.',
   'scripts/sql/the_it_engineer_breaks_the_company_once_a_month_to_prove_it_heals.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── the CEO's weekly report carries the latest game day ──────────────────────────────────────────
create or replace function public.fn_it_game_day_weekly_line()
returns text language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with last as (select max(run_month) m from public.it_game_day_run)
  select case when (select m from last) is null then '  No game day has run yet.'
    else format('  %s: %s of %s scenarios passed.', to_char((select m from last), 'Mon YYYY'),
                count(*) filter (where g.passed), count(*)) || E'\n' ||
         string_agg(format('  %-20s %s  detected in %s ms, recovered in %s ms%s', g.scenario,
                           case when g.passed then 'PASS' else 'FAIL' end,
                           coalesce(g.detection_ms::text, '-'), coalesce(g.recovery_ms::text, '-'),
                           case when g.error is not null then '  (' || left(g.error, 80) || ')' else '' end),
                    E'\n' order by g.scenario)
    end
    from public.it_game_day_run g where g.run_month = (select m from last)
$fn$;
revoke execute on function public.fn_it_game_day_weekly_line() from public, anon, authenticated;

-- Verbatim from the_ceo_writes_the_whole_company_report_and_names_what_is_holding_it_back.sql, plus GAME DAY.
create or replace function public.fn_ceo_weekly_report(p_week_start date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_ws date; v_we date; v_key text; v_fig jsonb; v_con jsonb; v_id bigint; v_body text; v_subj text;
  m jsonb; s jsonb; d jsonb; h jsonb;
begin
  v_ws := coalesce(p_week_start, (date_trunc('week', (now() at time zone 'Asia/Dubai')::date - 7))::date);
  v_we := v_ws + 6;
  v_key := 'quotesdone:' || to_char(v_ws, 'IYYY-"W"IW');

  v_fig := public.fn_ceo_weekly_figures(v_ws, v_we);
  v_con := public.fn_ceo_binding_constraint(v_fig);
  m := v_fig->'money'; s := v_fig->'supply'; d := v_fig->'demand'; h := v_fig->'health';

  v_subj := format('QuotesDone weekly - %s to %s - %s',
                   to_char(v_ws,'DD Mon'), to_char(v_we,'DD Mon YYYY'),
                   case when (v_con->>'severity') = 'healthy'
                        then 'AED ' || (m->>'revenue_week_aed') || ' revenue'
                        else 'blocked at ' || replace(v_con->>'stage','_',' ') end);

  v_body :=
    'WHAT IS HOLDING THE COMPANY BACK' || E'\n' ||
    (v_con->>'finding') || E'\n\n' ||
    'Why this outranks everything else: ' || (v_con->>'why_it_outranks_everything') || E'\n\n' ||
    'What to do: ' || (v_con->>'proposal') || E'\n' ||
    'How we will know it worked: ' || (v_con->>'measure_of_success') || E'\n\n' ||
    '--------------------------------------------------' || E'\n' ||
    'MONEY' || E'\n' ||
    format('  Revenue this week   AED %s   (prior week AED %s)', m->>'revenue_week_aed', m->>'revenue_prior_aed') || E'\n' ||
    format('  Revenue to date     AED %s', m->>'revenue_life_aed') || E'\n' ||
    format('  Spend this week     AED %s   (to date AED %s)', m->>'spend_week_aed', m->>'spend_life_aed') || E'\n' ||
    format('  VAT registration    %s (%s%% of the AED %s threshold)',
           (m->'vat_position'->>'band'), (m->'vat_position'->>'pct_of_threshold'), (m->'vat_position'->>'threshold_aed')) || E'\n\n' ||
    'SUPPLY' || E'\n' ||
    format('  On file %s, contactable %s, invited %s, registered %s, verified %s, MATCHABLE %s',
           s->>'leads_total', s->>'contactable', s->>'invited_ever', s->>'registered', s->>'verified', s->>'matchable') || E'\n' ||
    format('  Invited this week %s. Last invitation went out %s days ago.',
           s->>'invited_week', coalesce(s->>'days_since_last_invite','never')) || E'\n\n' ||
    'DEMAND' || E'\n' ||
    format('  Customers %s (with evidence behind them: %s)', d->>'customers', d->>'customers_real') || E'\n' ||
    format('  Requests this week %s, ever %s. Quotes %s. Comparisons %s. Paid reveals %s.',
           d->>'inquiries_week', d->>'inquiries_ever', d->>'quotes_ever', d->>'comparisons_ever', d->>'reveals_ever') || E'\n\n' ||
    'THE SEATS' || E'\n' ||
    (select string_agg(format('  %-17s %s run(s), %s error(s)', k, v->>'runs_week', v->>'errors_week'), E'\n' order by k)
       from jsonb_each(v_fig->'seats') as t(k,v)) || E'\n\n' ||
    'HEALTH' || E'\n' ||
    format('  Open IT findings %s. Alerts sent to you this week %s.', h->>'it_findings_open', h->>'it_alerts_week') || E'\n' ||
    format('  Reports waiting on the CEO %s. Your instructions still open %s.',
           h->>'reports_awaiting_ceo', h->>'founder_instructions_open') || E'\n\n' ||
    'GAME DAY (the IT engineer breaks the company on purpose once a month and times the recovery)' || E'\n' ||
    public.fn_it_game_day_weekly_line() || E'\n\n' ||
    'Every figure above is measured from the ledger and the live tables at the moment of writing. ' ||
    'A zero here means nothing happened, not that nothing was counted.';

  insert into public.ceo_weekly_report
    (iso_year, iso_week, week_start, week_end, report_key, subject, body, figures, constraint_now,
     proposals, status)
  values
    (extract(isoyear from v_ws)::int, extract(week from v_ws)::int, v_ws, v_we, v_key,
     v_subj, v_body, v_fig, v_con, jsonb_build_array(v_con->>'proposal'), 'generated')
  on conflict (report_key, revision) do update
     set subject = excluded.subject, body = excluded.body, figures = excluded.figures,
         constraint_now = excluded.constraint_now, proposals = excluded.proposals, updated_at = now()
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'report_key', v_key,
    'week', v_ws || ' to ' || v_we, 'constraint', v_con->>'stage', 'subject', v_subj);
end $fn$;
revoke execute on function public.fn_ceo_weekly_report(date) from public, anon, authenticated;
