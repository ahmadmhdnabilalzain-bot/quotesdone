-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708130418   name: doc_reminders_runner
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.run_doc_reminders()
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare s text;
begin
  select value into s from public.app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/doc_reminder',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s, 'days', 14));
end $$;
