-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710200947   name: security_audit_trail
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.security_audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  db_user    text not null default current_user,
  action     text not null,
  table_name text not null,
  row_pk     text,
  old_data   jsonb,
  new_data   jsonb
);
create index if not exists ix_sec_audit_at on public.security_audit_log(at desc);
create index if not exists ix_sec_audit_tbl on public.security_audit_log(table_name, at desc);
alter table public.security_audit_log enable row level security;

create or replace function public.fn_security_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'security_audit_log is append-only; % is not permitted', tg_op;
end $$;
drop trigger if exists trg_sec_audit_immutable on public.security_audit_log;
create trigger trg_sec_audit_immutable
  before update or delete on public.security_audit_log
  for each row execute function public.fn_security_audit_immutable();

create or replace function public.fn_security_audit()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_old jsonb; v_new jsonb; v_pk text;
begin
  v_old := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_new := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  if tg_table_name = 'app_secrets' then
    if v_old ? 'value' then v_old := jsonb_set(v_old, '{value}', '"***REDACTED***"'); end if;
    if v_new ? 'value' then v_new := jsonb_set(v_new, '{value}', '"***REDACTED***"'); end if;
  end if;
  v_pk := coalesce(v_new->>'id', v_old->>'id', v_new->>'key', v_old->>'key',
                   v_new->>'name', v_old->>'name', v_new->>'role', v_old->>'role');
  insert into public.security_audit_log(action, table_name, row_pk, old_data, new_data)
  values (tg_op, tg_table_name, v_pk, v_old, v_new);
  return coalesce(new, old);
end $$;

drop trigger if exists trg_audit_roles on public.roles;
create trigger trg_audit_roles after insert or update or delete on public.roles
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_user_roles on public.user_roles;
create trigger trg_audit_user_roles after insert or update or delete on public.user_roles
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_role_permissions on public.role_permissions;
create trigger trg_audit_role_permissions after insert or update or delete on public.role_permissions
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_collections_config on public.collections_config;
create trigger trg_audit_collections_config after insert or update or delete on public.collections_config
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_pricing_config on public.pricing_config;
create trigger trg_audit_pricing_config after insert or update or delete on public.pricing_config
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_feature_flags on public.feature_flags;
create trigger trg_audit_feature_flags after insert or update or delete on public.feature_flags
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_gl_settings on public.gl_settings;
create trigger trg_audit_gl_settings after insert or update or delete on public.gl_settings
  for each row execute function public.fn_security_audit();
drop trigger if exists trg_audit_app_secrets on public.app_secrets;
create trigger trg_audit_app_secrets after insert or update or delete on public.app_secrets
  for each row execute function public.fn_security_audit();
