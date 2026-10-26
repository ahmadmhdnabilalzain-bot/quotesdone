-- AUDIT 9.5, the part the credential model could not see.
--
-- internal_credential models `body.__secret`. Two live mechanisms authenticated some other way and
-- were therefore invisible to it, to v_legacy_secret_users, and to
-- v_internal_secret_migration_progress - which reported "0 crons still on the shared secret" while
-- these ran in the same table:
--
--   x-internal-key: <app_secrets.postiz_publish_key>   qa_suite_daily (active), social_stage_hourly
--   no internal credential at all                       wa_templates_watch (active, every 15 min)
--
-- postiz_publish_key was a SECOND shared secret: one string, no scope, no attribution, no rotation
-- path, spanning a QA suite and a live social publisher. wa_templates_watch had no gate in its
-- handler whatsoever - `Deno.serve(async ()=>{...})` never read the request - and ran as the service
-- role behind nothing but verify_jwt, which the public anon key satisfies.
--
-- Both edge functions now use requireInternal, deployed before this migration runs. This moves the
-- crons onto scoped credentials to match.
--
-- wa_templates_watch is UNSCHEDULED rather than re-credentialed. wa_templates_ready is already
-- 'true', so every run since has returned on its first line: the function's own design unschedules
-- itself when all templates are approved (cron_unschedule_wa_watch), that RPC does not exist, and it
-- has therefore been polling Twilio for nothing every fifteen minutes. Finishing what the function
-- intended is better than paying to authenticate a no-op.
set local app.change_reason = 'Audit 9.5: qa_suite and social_stage move from a shared x-internal-key header onto their existing cron credentials. This is a narrowing - the header key had no scope at all - and the two functions were redeployed to require it immediately before this ran.';

update public.internal_credential
   set scope = array(select distinct s from unnest(scope || array['qa_suite']) s order by s)
 where context = 'cron.monitoring' and active and not (scope @> array['qa_suite']);

update public.internal_credential
   set scope = array(select distinct s from unnest(scope || array['social_stage']) s order by s)
 where context = 'cron.content' and active and not (scope @> array['social_stage']);

select cron.alter_job(28, command := $CRON$
  select net.http_post(
    url  := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/qa_suite',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret',(select value from public.app_secrets where key='cred_cron_monitoring'))
  );
$CRON$);

select cron.alter_job(27, command := $CRON$
  select net.http_post(
    url  := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/social_stage',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('__secret',(select value from public.app_secrets where key='cred_cron_content'))
  );
$CRON$);

select cron.unschedule('wa_templates_watch');

do $$
declare v_bad text;
begin
  -- Assert the invariant, not the change: no active cron may authenticate to an edge function by any
  -- mechanism other than a credential the verifier understands.
  select string_agg(jobname, ', ') into v_bad
    from cron.job
   where active
     and (regexp_match(command, 'functions/v1/([a-z0-9_]+)'))[1] is not null
     and command !~ 'key\s*=\s*''cred_[a-z0-9_]+''';
  if v_bad is not null then
    raise exception 'active cron job(s) still call an edge function without a scoped credential: %', v_bad;
  end if;

  if exists (select 1 from cron.job where jobname = 'wa_templates_watch') then
    raise exception 'wa_templates_watch is still scheduled';
  end if;
end $$;;
