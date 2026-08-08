-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711194309   name: dedupe_double_site_autodeploy
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Both run_auto_deploy (deploy_state) and run_site_autodeploy (site_publish_state)
-- independently trigger the same site_deploy edge function, causing a double
-- Vercel build on every content change. Fix: whichever deploys also clears the
-- OTHER table's dirty flag, so the second job sees "clean" and skips the dup.
-- Neither job is disabled, so no change type can lose its deploy trigger.

create or replace function public.run_auto_deploy()
 returns text
 language plpgsql
 security definer
 set search_path to 'public','pg_temp'
as $function$
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
  -- dedupe: this deploy already renders the full site, so clear the twin path too
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  return 'deploying';
end $function$;

create or replace function public.run_site_autodeploy()
 returns void
 language plpgsql
 security definer
 set search_path to 'public','pg_temp','net'
as $function$
declare s text; d boolean; lastdep timestamptz;
begin
  select dirty, last_deploy_at into d, lastdep from public.site_publish_state where id=1;
  if not coalesce(d,false) then return; end if;
  if lastdep is not null and now()-lastdep < interval '50 seconds' then return; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  if s is null then return; end if;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  -- dedupe: clear the twin path so run_auto_deploy skips the duplicate build
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    body := jsonb_build_object('__secret', s),
    headers := jsonb_build_object('Content-Type','application/json'),
    timeout_milliseconds := 150000
  );
end$function$;
