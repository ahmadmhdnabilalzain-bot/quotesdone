-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619154458   name: auto_deploy_wiring
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.deploy_state (id int primary key, dirty boolean default false, last_deploy timestamptz, last_status text);
insert into public.deploy_state(id,dirty) values (1,false) on conflict (id) do nothing;

create or replace function public.trg_pages_dirty() returns trigger language plpgsql as $f$
begin update public.deploy_state set dirty=true where id=1; return null; end $f$;
drop trigger if exists trg_pages_dirty_a on public.pages;
create trigger trg_pages_dirty_a after insert or update on public.pages
  for each row execute function public.trg_pages_dirty();

create or replace function public.run_auto_deploy() returns text language plpgsql security definer as $f$
declare d boolean; s text;
begin
  select dirty into d from public.deploy_state where id=1;
  if not coalesce(d,false) then return 'clean'; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    headers:='{"Content-Type":"application/json"}'::jsonb,
    body:=jsonb_build_object('__secret', s));
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  return 'deploying';
end $f$;

select cron.schedule('auto_deploy','*/2 * * * *', $cr$select public.run_auto_deploy()$cr$);
