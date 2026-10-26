-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706115642   name: rbac_abac_policy_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.roles(name text primary key, description text);
create table if not exists public.role_permissions(role text references public.roles(name), action text, constraint_json jsonb default '{}', primary key(role,action));
create table if not exists public.user_roles(email text, role text references public.roles(name), added_at timestamptz default now(), primary key(email,role));
do $$ begin
  execute 'alter table public.roles enable row level security'; execute 'revoke all on public.roles from anon, authenticated';
  execute 'alter table public.role_permissions enable row level security'; execute 'revoke all on public.role_permissions from anon, authenticated';
  execute 'alter table public.user_roles enable row level security'; execute 'revoke all on public.user_roles from anon, authenticated';
end $$;

insert into public.roles(name,description) values
 ('owner','Founder / full control'),('admin','Staff administrator'),('ops','Operations'),
 ('finance','Finance & billing'),('support','Customer/supplier support'),
 ('supplier','Registered supplier'),('customer','Registered customer'),('agent','Autonomous AI agent'),('guest','Unauthenticated')
on conflict (name) do nothing;

insert into public.role_permissions(role,action,constraint_json) values
 ('owner','*','{}'),
 ('admin','approve_supplier','{}'),('admin','view_customer_pii','{}'),('admin','publish_content','{}'),('admin','run_agent_action','{}'),('admin','edit_pricing','{}'),
 ('finance','issue_refund','{"max_amount_aed":10000}'),('finance','view_invoices','{}'),('finance','edit_pricing','{}'),
 ('ops','approve_supplier','{}'),('ops','route_inquiry','{}'),('ops','run_agent_action','{}'),
 ('support','send_message','{}'),('support','view_customer_pii','{"purpose":"support"}'),
 ('agent','run_agent_action','{"max_amount_aed":0}'),('agent','send_message','{}'),('agent','route_inquiry','{}'),
 ('supplier','submit_quote','{}'),('supplier','view_own_profile','{}'),
 ('customer','create_rfq','{}'),('customer','reveal_supplier','{}'),('customer','view_own_data','{}')
on conflict (role,action) do nothing;

insert into public.user_roles(email,role)
select trim(lower(e)), 'owner' from unnest(string_to_array((select value from app_secrets where key='admin_emails'),',')) e
on conflict do nothing;

create or replace function public.fn_role_of(p_email text)
returns text language plpgsql stable security definer set search_path=public,pg_temp as $$
declare e text := lower(trim(coalesce(p_email,''))); v_role text;
begin
  if e='' then return 'guest'; end if;
  select ur.role into v_role from user_roles ur where ur.email=e order by array_position(array['owner','admin','ops','finance','support','agent'],ur.role) limit 1;
  if v_role is not null then return v_role; end if;
  if e = any (string_to_array(lower(coalesce((select value from app_secrets where key='admin_emails'),'')),',')) then return 'owner'; end if;
  if exists(select 1 from leads where lower(coalesce(claimed_by,''))=e) then return 'supplier'; end if;
  if exists(select 1 from customers where lower(coalesce(email,''))=e) then return 'customer'; end if;
  return 'guest';
end $$;

create or replace function public.fn_authorize(p_email text, p_action text, p_attrs jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_role text; c jsonb; ok boolean:=false; reason text; maxamt numeric; amt numeric;
begin
  v_role := public.fn_role_of(p_email);
  if v_role='owner' then return jsonb_build_object('allowed',true,'role',v_role,'reason','owner has full access'); end if;
  select rp.constraint_json into c from role_permissions rp where rp.role=v_role and rp.action=p_action;
  if c is null then
    if exists(select 1 from role_permissions rp where rp.role=v_role and rp.action='*') then
      return jsonb_build_object('allowed',true,'role',v_role,'reason','role wildcard'); end if;
    return jsonb_build_object('allowed',false,'role',v_role,'reason','role "'||v_role||'" lacks permission "'||p_action||'"');
  end if;
  ok := true; reason := 'granted';
  if c ? 'max_amount_aed' then
    maxamt := (c->>'max_amount_aed')::numeric; amt := nullif(p_attrs->>'amount_aed','')::numeric;
    if amt is not null and amt > maxamt then ok:=false; reason:='amount '||amt||' exceeds role limit '||maxamt; end if;
  end if;
  if c ? 'purpose' and coalesce(p_attrs->>'purpose','') <> (c->>'purpose') then ok:=false; reason:='purpose must be '||(c->>'purpose'); end if;
  return jsonb_build_object('allowed',ok,'role',v_role,'reason',reason,'constraint',c);
end $$;

select 'a' t, public.fn_authorize((select value from app_secrets where key='admin_emails'),'issue_refund','{"amount_aed":50000}'::jsonb) r
union all select 'b', public.fn_authorize('someagent@x','run_agent_action','{"amount_aed":500}'::jsonb)
union all select 'c', public.fn_authorize('nobody@x','approve_supplier','{}'::jsonb);
