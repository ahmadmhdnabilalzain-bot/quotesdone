-- WHY. On 29 Jul 2026 the OpenRouter balance was found at $1.48. Nothing was broken: the figure
-- was measured correctly and reported accurately - into a WEEKLY email, with no threshold ever
-- compared against it. A balance that empties in about ten days cannot be guarded by a seven-day
-- check, and a number inside a summary is not an alarm. Every agent, the Secretary, document
-- reading, translation and supplier matching stop at zero, so this is the single point of failure
-- for the whole company.
--
-- cost_snapshot now compares the balance against app_secrets.openrouter_min_usd and raises a
-- CRITICAL founder alert (WhatsApp + email, de-duplicated for 6 hours) when it is at or below it.
-- This job runs that check every day at 05:00 UTC (09:00 Dubai) with email:false, so the balance
-- is watched daily WITHOUT turning the weekly summary into daily noise. The Monday 07:00 job is
-- left exactly as it was and still sends the full burn + revenue email.

select cron.schedule(
  'cost_snapshot_balance_daily',
  '0 5 * * *',
  $job$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/cost_snapshot',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object(
      '__secret',(select value from app_secrets where key='inbound_secret'),
      'email', false),
    timeout_milliseconds:=120000)
  $job$
);

insert into app_secrets (key, value) values ('openrouter_min_usd','20')
on conflict (key) do nothing;