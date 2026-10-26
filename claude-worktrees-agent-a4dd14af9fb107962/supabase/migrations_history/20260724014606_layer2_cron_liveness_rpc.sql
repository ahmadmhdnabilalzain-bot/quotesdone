-- Layer 2 external watchdog: liveness of the pg_cron scheduler itself.
-- Read-only; works as long as Postgres is up even if pg_cron has stopped scheduling.
-- Called by the resilience_ping edge function (which an EXTERNAL scheduler hits), so a total
-- pg_cron outage is detectable from outside the database.
create or replace function public.fn_cron_liveness()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_catalog','cron'
as $function$
declare v_age numeric; v_last timestamptz;
begin
  select max(start_time) into v_last from cron.job_run_details;
  if v_last is null then
    return jsonb_build_object('healthy', false, 'newest_run_age_min', null, 'note', 'no cron run history');
  end if;
  v_age := extract(epoch from (now() - v_last))/60.0;
  return jsonb_build_object(
    'healthy', v_age <= 20,               -- crons run every few minutes; >20min silence = scheduler down
    'newest_run_age_min', round(v_age,1),
    'checked_at', now());
exception when others then
  return jsonb_build_object('healthy', null, 'error', sqlerrm);
end $function$;

revoke execute on function public.fn_cron_liveness() from public, anon, authenticated;
grant execute on function public.fn_cron_liveness() to service_role;
