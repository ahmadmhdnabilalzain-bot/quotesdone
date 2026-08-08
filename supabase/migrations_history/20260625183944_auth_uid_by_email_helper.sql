-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625183944   name: auth_uid_by_email_helper
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.auth_uid_by_email(p_email text)
returns uuid
language sql
security definer
set search_path = auth, public
as $$
  select id from auth.users where lower(email) = lower(p_email) limit 1;
$$;
revoke all on function public.auth_uid_by_email(text) from public, anon, authenticated;
