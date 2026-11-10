-- THE FOUNDER HEARS BEFORE THE AI CREDIT RUNS OUT.
--
-- Seat: accountant. 10 Nov 2026 (it_engineer session, for the accountant's money duty).
--
-- MEASURED ON PRODUCTION, 10 Nov 2026 00:50 UTC:
--   v_openrouter_position (read 9 Nov 23:31): topped up USD 540, spent 538.72, balance USD 1.28.
--   From ~00:40 about half of all llm_attempt rows failed with OpenRouter 402 "This request would exceed your
--   available credits"; the homepage widget answered visitors "Sorry - something went wrong" (assistant_logs
--   7403/7405/7406, all_models_failed). The meter is read ~14 times a day (resilience_ping accountant tick), but
--   NOTHING read it to warn anyone: public.notifications holds no credit or balance alert, ever. The founder found out
--   from a session, after visitors had already been failed.
--
-- WHAT THIS DOES
--   1. fn_openrouter_balance_band(balance): the pure decision. 'critical' under USD 2, 'low' under USD 10, else 'ok'.
--      NULL (no reading) is 'unknown', never 'ok'.
--   2. fn_openrouter_low_balance_tick(): reads the newest reading in v_openrouter_position. On 'low' or 'critical' it
--      emails the founder through fn_notify_founder with kind finance_reminder ("a payment falling due is money he
--      pays", already allowed by founder_mail_policy), at most ONCE A DAY PER BAND (dedupe
--      openrouter_low:<band>:<date>), so a balance that stays low is one email a day, and a drop from low to
--      critical is one more. It checks founder_alerts itself first, so no 'deduped' row is written every hour.
--      It also says when the reading is older than 12 hours, because an old reading can hide a balance that ran out.
--   3. Schedules it hourly at minute 23 (off the :00 and the 5-minute marks), with its cron_registry and writer_seat
--      rows (owner accountant).
--   Nothing here spends, calls a model or changes the meter.
--
-- Prevented by: scripts/checks/the_founder_hears_before_the_ai_credit_runs_out.test.mjs.

create or replace function public.fn_openrouter_balance_band(p_balance_usd numeric)
returns text
language sql
immutable
set search_path to 'pg_catalog', 'pg_temp'
as $fn$
  select case
    when p_balance_usd is null then 'unknown'
    when p_balance_usd < 2 then 'critical'
    when p_balance_usd < 10 then 'low'
    else 'ok'
  end
$fn$;

revoke execute on function public.fn_openrouter_balance_band(numeric) from public, anon, authenticated;

create or replace function public.fn_openrouter_low_balance_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_pos   record;
  v_band  text;
  v_key   text;
  v_age_h numeric;
  v_sent  jsonb;
begin
  select * into v_pos from public.v_openrouter_position limit 1;
  if not found then
    return jsonb_build_object('band', 'unknown', 'why', 'no OpenRouter reading at all');
  end if;
  v_band  := public.fn_openrouter_balance_band(v_pos.account_balance_usd);
  v_age_h := round(extract(epoch from (now() - v_pos.read_at)) / 3600.0, 1);
  if v_band in ('ok', 'unknown') then
    return jsonb_build_object('band', v_band, 'balance_usd', v_pos.account_balance_usd, 'reading_age_h', v_age_h);
  end if;
  v_key := 'openrouter_low:' || v_band || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  if exists (select 1 from public.founder_alerts f where f.dedupe_key = v_key and f.channel = 'email') then
    return jsonb_build_object('band', v_band, 'balance_usd', v_pos.account_balance_usd, 'sent', false, 'why', 'already told today');
  end if;
  v_sent := public.fn_notify_founder(
    p_event => case when v_band = 'critical'
                    then 'TOP UP OPENROUTER NOW: the AI credit is almost gone (USD ' || round(v_pos.account_balance_usd, 2) || ' left)'
                    else 'OpenRouter credit is low: USD ' || round(v_pos.account_balance_usd, 2) || ' left' end,
    p_detail => 'The company''s AI account (OpenRouter) has USD ' || round(v_pos.account_balance_usd, 2) || ' of credit left'
      || ' (topped up ' || round(v_pos.account_topped_up_usd, 2) || ', spent ' || round(v_pos.account_spent_usd, 2) || ').'
      || ' When it reaches zero every AI reply fails: the website chat, WhatsApp and the agents'' work.'
      || ' Add credit at openrouter.ai (Settings, Credits).'
      || case when v_age_h > 12 then ' Note: this reading is ' || v_age_h || ' hours old, so the balance may already be lower.' else '' end,
    p_level => case when v_band = 'critical' then 'critical' else 'high' end,
    p_kind => 'finance_reminder', p_dedupe_key => v_key, p_owner_agent => 'accountant');
  return jsonb_build_object('band', v_band, 'balance_usd', v_pos.account_balance_usd, 'reading_age_h', v_age_h, 'sent', v_sent);
end
$fn$;

revoke execute on function public.fn_openrouter_low_balance_tick() from public, anon, authenticated;

comment on function public.fn_openrouter_low_balance_tick() is
  'Hourly: emails the founder (finance_reminder) at most once a day per band when the OpenRouter balance is under USD 10 (critical under 2). accountant, 10 Nov 2026.';

select cron.schedule('openrouter_low_balance_hourly', '23 * * * *', $CRON$select public.fn_openrouter_low_balance_tick();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('openrouter_low_balance_hourly', 'the founder hears before the AI credit runs out', 'AI cost',
   'Hourly at :23: fn_openrouter_low_balance_tick() reads v_openrouter_position and emails the founder once a day per band '
   || 'when the balance is under USD 10 (critical under USD 2). Before 10 Nov 2026 nothing warned him; the credit ran out.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'openrouter_low_balance_hourly', 'accountant',
   'Hourly: warns the founder before the OpenRouter credit runs out (finance_reminder, once a day per band).',
   'scripts/sql/the_founder_hears_before_the_ai_credit_runs_out.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with cases(b, want) as (values (null::numeric, 'unknown'), (0::numeric, 'critical'), (1.99, 'critical'), (2::numeric, 'low'),
                               (9.99, 'low'), (10::numeric, 'ok'), (540::numeric, 'ok')),
     wrong as (select count(*) n from cases where public.fn_openrouter_balance_band(b) is distinct from want),
     j as (select count(*) n from cron.job where jobname = 'openrouter_low_balance_hourly' and active),
     f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname = 'fn_openrouter_low_balance_tick' and p.prosecdef),
     anon as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
               where s.nspname = 'public' and p.proname in ('fn_openrouter_low_balance_tick', 'fn_openrouter_balance_band')
                 and has_function_privilege('anon', p.oid, 'execute')),
     pol as (select coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'finance_reminder'), false) ok)
select case
  when (select n from wrong) <> 0 then 'PROBE FAILED: fn_openrouter_balance_band decides ' || (select n from wrong) || ' of 7 cases wrong'
  when (select n from f) <> 1 then 'PROBE FAILED: fn_openrouter_low_balance_tick missing or not security definer'
  when (select n from anon) <> 0 then 'PROBE FAILED: anon can execute a balance routine'
  when (select n from j) <> 1 then 'PROBE FAILED: openrouter_low_balance_hourly not scheduled and active'
  when not (select ok from pol) then 'PROBE FAILED: founder_mail_policy does not allow finance_reminder, so the warning would be held'
  when (select count(*) from public.writer_seat where kind = 'cron_job' and name = 'openrouter_low_balance_hourly' and owner_seat = 'accountant') <> 1
    then 'PROBE FAILED: openrouter_low_balance_hourly names no seat in writer_seat'
  when (select count(*) from public.cron_registry where jobname = 'openrouter_low_balance_hourly') <> 1
    then 'PROBE FAILED: openrouter_low_balance_hourly is not in cron_registry'
  else 'PROBE OK: 7 of 7 band cases right, hourly warning scheduled, finance_reminder allowed, anon cannot run it'
end as verdict;
