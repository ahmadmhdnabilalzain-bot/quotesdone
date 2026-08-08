-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260629193405   name: licence_reminders_cron
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create or replace function public.run_licence_reminders() returns void language plpgsql security definer as $$
declare s text;
begin
  select value into s from app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/licence_reminder',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'days', 7)
  );
end $$;
select cron.schedule('licence_reminders_daily','0 5 * * *', $$ select public.run_licence_reminders(); $$);

