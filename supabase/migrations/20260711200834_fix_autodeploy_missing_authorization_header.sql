-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260711200834   name: fix_autodeploy_missing_authorization_header
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ROOT CAUSE of the frozen live site: site_deploy has verify_jwt=true, so the
-- Supabase gateway 401s any call without an Authorization header. The cron
-- callers sent only {__secret} in the body -> every auto-deploy was rejected
-- before site_deploy ran. Fix: pass a valid project JWT (anon_key) as the
-- gateway bearer; site_deploy's own __secret check still does the real auth.

create or replace function public.run_auto_deploy()
 returns text
 language plpgsql
 security definer
 set search_path to 'public','pg_temp'
as $function$
declare d boolean; s text; ak text;
begin
  select dirty into d from public.deploy_state where id=1;
  if not coalesce(d,false) then return 'clean'; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  select value into ak from public.app_secrets where key='anon_key';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    body:=jsonb_build_object('__secret', s),
    timeout_milliseconds:=150000);
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  return 'deploying';
end $function$;

create or replace function public.run_site_autodeploy()
 returns void
 language plpgsql
 security definer
 set search_path to 'public','pg_temp','net'
as $function$
declare s text; d boolean; lastdep timestamptz; ak text;
begin
  select dirty, last_deploy_at into d, lastdep from public.site_publish_state where id=1;
  if not coalesce(d,false) then return; end if;
  if lastdep is not null and now()-lastdep < interval '50 seconds' then return; end if;
  select value into s from public.app_secrets where key='inbound_secret';
  select value into ak from public.app_secrets where key='anon_key';
  if s is null then return; end if;
  update public.site_publish_state set dirty=false, last_deploy_at=now() where id=1;
  update public.deploy_state set dirty=false, last_deploy=now(), last_status='triggered' where id=1;
  perform net.http_post(
    url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/site_deploy',
    body := jsonb_build_object('__secret', s),
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||ak),
    timeout_milliseconds := 150000
  );
end$function$;
