CREATE OR REPLACE FUNCTION public.fn_recert_rotate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_agent text; v_secret text;
begin
  perform fn_onboarding_ingest_runs();
  select agent_key into v_agent from org_onboarding
    order by coalesce(greatest(l1_at,l2_at,l3_at,l4_at), 'epoch'::timestamptz) asc limit 1;
  if v_agent is null then return jsonb_build_object('skipped','no onboarding records'); end if;
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/canon_eval',
    body:=jsonb_build_object('__secret', v_secret, 'agent', v_agent, 'limit', 8),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=150000);
  return jsonb_build_object('examined', v_agent);
end $function$
