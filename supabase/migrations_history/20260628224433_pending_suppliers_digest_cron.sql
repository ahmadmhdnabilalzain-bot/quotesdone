-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260628224433   name: pending_suppliers_digest_cron
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.run_pending_digest() returns void language plpgsql security definer as $fn$
declare s text;
begin
  select value into s from public.app_secrets where key='inbound_secret';
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/pending_digest',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', s)
  );
end$fn$;
do $$ begin perform cron.unschedule('pending_suppliers_digest'); exception when others then null; end $$;
select cron.schedule('pending_suppliers_digest','30 4 * * *','select public.run_pending_digest();');
