-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727133041   name: protect_deploy_secret_in_app_secrets
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

CREATE OR REPLACE FUNCTION public.fn_protect_app_secret()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  protected text[] := array['inbound_secret','deploy_secret','stripe_secret_key','service_role_key','resend_api_key'];
  k text := coalesce(old.key, new.key);
begin
  if tg_op = 'DELETE' then
    if old.key = any(protected) then
      raise exception 'app_secrets.% is load-bearing for edge-function authentication and cannot be deleted; rotate the value instead', old.key
        using errcode = 'raise_exception';
    end if;
    return old;
  end if;
  if new.key = any(protected) then
    if new.value is null or length(btrim(new.value)) < 24 then
      raise exception 'app_secrets.% must stay a non-empty secret of at least 24 characters (got %); an empty value would make every __secret guard pass',
        new.key, coalesce(length(btrim(new.value)), 0)
        using errcode = 'raise_exception';
    end if;
  end if;
  return new;
end $function$;
