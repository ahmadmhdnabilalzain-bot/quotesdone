-- THE LEAD SOURCING KICK SENDS THE PUBLISHABLE KEY, NOT THE LEGACY ANON JWT (it_engineer, 27 Oct 2026).
-- Assigned: it_engineer. docs/reports/security/SECURITY_HARDENING_27_OCT.md item 3, consumer A4.
--
-- The legacy anon key is a JWT signed with the project's HS256 secret, and that secret leaked. It can be revoked
-- only once nothing sends a token it signed. Measured 27 Oct 2026: 0 legacy keys in vault.decrypted_secrets, 0 in
-- cron.job.command, and exactly one routine body that sends one, fn_lead_sourcing_kick(), which reads
-- app_secrets.anon_key (a JWT, 208 characters) and posts it as apikey and Bearer to the marketing function.
--
-- What this file changes:
--   1. fn_gateway_client_key(): the one place a routine picks the key it shows the API gateway. It returns
--      app_secrets.publishable_key (the sb_publishable_ 'default' key) and falls back to app_secrets.anon_key
--      only while that row is absent. The fallback is TEMPORARY: the PR that follows 24 to 48 h of zero HS256
--      traffic removes it, and the anon_key row with it.
--   2. fn_lead_sourcing_kick() reads its key through fn_gateway_client_key(). Its body is otherwise the live one
--      (pg_get_functiondef read back 27 Oct 2026), byte for byte, error text included bar the key's name.
--
-- THE VALUE IS NOT IN THIS FILE. No key value is ever committed. The publishable_key row is written at release by
-- scripts/it/store_the_publishable_key_in_app_secrets.mjs, which reads the key from the Management API and
-- verifies it by digest, printing neither. Until it runs, the fallback keeps the kick working exactly as today,
-- so the order of the two steps does not matter and neither costs a failed batch.
--
-- The gateway accepts the publishable key on functions with verify_jwt on or off (proved 27 Oct 2026 against
-- customer_api and public_site: the function's own answer, never the gateway's). The marketing function
-- authenticates the batch by __secret = cred_fn_marketing, which this file does not touch.
--
-- Proof: scripts/sql/the_lead_sourcing_kick_sends_the_publishable_key_not_the_legacy_anon_jwt_probe.sql, replayed
-- after this file in one rolled-back transaction by
-- scripts/checks/the_lead_sourcing_kick_sends_the_publishable_key.test.mjs.

create or replace function public.fn_gateway_client_key()
returns text language sql stable security invoker set search_path to 'public', 'pg_temp' as $fn$
  -- the new key first; the legacy anon JWT only while the publishable_key row is absent (TEMPORARY, 27 Oct 2026)
  select coalesce(
    (select nullif(btrim(value), '') from public.app_secrets where key = 'publishable_key'),
    (select nullif(btrim(value), '') from public.app_secrets where key = 'anon_key'));
$fn$;
revoke execute on function public.fn_gateway_client_key() from public, anon, authenticated;
comment on function public.fn_gateway_client_key() is
  'The key a routine shows the Supabase API gateway: app_secrets.publishable_key, else (temporarily, until 24-48 h of zero HS256 traffic) the legacy app_secrets.anon_key. it_engineer, 27 Oct 2026.';

create or replace function public.fn_lead_sourcing_kick()
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ref text; v_anon text; v_cred text; t jsonb;
begin
  t := public.fn_lead_sourcing_today();
  if t->>'stop' is not null then return null; end if;   -- lead quota, Serper cap or model cap reached (or set to 0)
  select value into v_ref  from public.app_secrets where key = 'project_ref';
  v_anon := public.fn_gateway_client_key();   -- publishable_key, else the legacy anon_key (27 Oct 2026)
  select value into v_cred from public.app_secrets where key = 'cred_fn_marketing';
  if v_ref is null or v_anon is null or v_cred is null then
    raise exception 'fn_lead_sourcing_kick: project_ref, publishable_key (or anon_key) or cred_fn_marketing missing from app_secrets';
  end if;
  return net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/marketing',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_anon, 'apikey', v_anon),
    body := jsonb_build_object('__secret', v_cred, 'action', 'lead_sourcing'), timeout_milliseconds := 10000);
end $fn$;
revoke execute on function public.fn_lead_sourcing_kick() from public, anon, authenticated;
