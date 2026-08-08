-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727112442   name: protect_critical_app_secrets
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Half of the fail-open path in ~77 edge functions is "the app_secrets row is gone or empty".
-- The guard shape is  body.__secret !== await sec('inbound_secret')  and sec() returns
-- undefined/'' when the row is missing, so an omitted __secret would compare equal and pass.
-- This closes the row-missing half at the data layer. The code sweep closes the transient-read half.
create or replace function fn_protect_app_secret() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  protected text[] := array['inbound_secret','stripe_secret_key','service_role_key','resend_api_key'];
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
end $$;

drop trigger if exists trg_protect_app_secret on app_secrets;
create trigger trg_protect_app_secret
  before insert or update or delete on app_secrets
  for each row execute function fn_protect_app_secret();
