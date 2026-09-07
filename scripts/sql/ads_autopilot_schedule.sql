-- AD SPEND AUTOPILOT — the daily tick, and the sync that keeps it honest (3 Sep 2026).
--
-- scripts/sql/ad_spend_autopilot.sql is the manager; this file puts it on the clock.
--
--   fn_ads_autopilot_tick()   runs fn_ads_manage(false) — the REAL campaigns, never a fixture — and,
--                             only if it left unexecuted decisions, posts execute_decisions to the
--                             meta_ads edge function with a credential scoped to that one callee.
--                             No decisions, no HTTP call, no run row: an idle day is silent.
--   ads_autopilot_daily       pg_cron 04:20 UTC (08:20 Dubai), wrapped and traced by the kernel like
--                             every other scheduled component, owned by marketing_director / growth.
--   meta_sync_daily (job 72)  re-enabled under the same wrap. It was switched off with the 16 Aug
--                             stand-down; without meta_access_token it logs 'skipped' and touches
--                             nothing (measured: an intentional off state, not a failure). With the
--                             token it now also mirrors campaigns, ad-set budgets and month spend into
--                             ad_campaign_state / ad_spend_policy so the manager judges the truth.
--
-- The credential is issued here, once, through fn_internal_credential_issue (scope ['meta_ads'] and
-- nothing else) and its value stored under app_secrets.cred_cron_ads_autopilot for the cron to read —
-- the same shape as cred_cron_notifications and cred_cron_knowledge. Re-applying this file does not
-- issue a second one.
--
-- Both crons are registered as Phase D committed-scenario sources because meta_ads writes
-- agent_runs, a watched relation. The literal component declaration for the new cron lives in
-- scripts/sql/declare_ads_autopilot_cron_component.sql (the wrap declares dynamically; CI wants the
-- literal), and its crosswalk row in docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv.

create or replace function public.fn_ads_autopilot_tick()
returns jsonb
language plpgsql
set search_path to 'public', 'net', 'pg_temp'
as $$
declare
  v_decided int := 0;
  v_pending int := 0;
  v_ref     text;
  v_secret  text;
  v_req     bigint;
begin
  select count(*) into v_decided from public.fn_ads_manage(false, null);
  select count(*) into v_pending from public.ad_decision where executed_at is null;
  if v_pending = 0 then
    return jsonb_build_object('decided', v_decided, 'pending', 0, 'posted', false);
  end if;
  select value into v_ref    from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_cron_ads_autopilot';
  if v_ref is null or v_secret is null then
    raise exception 'fn_ads_autopilot_tick: % decision(s) are waiting but % is missing from app_secrets, so they cannot be executed',
      v_pending, case when v_ref is null then 'project_ref' else 'cred_cron_ads_autopilot' end;
  end if;
  select net.http_post(
    url     := 'https://' || v_ref || '.supabase.co/functions/v1/meta_ads',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body    := jsonb_build_object('__secret', v_secret, 'action', 'execute_decisions', 'limit', 50)
  ) into v_req;
  return jsonb_build_object('decided', v_decided, 'pending', v_pending, 'posted', true, 'request_id', v_req);
end;
$$;

begin;
do $$
declare
  v_job bigint;
  v_cred jsonb;
begin
  -- 1. the credential, once
  if not exists (select 1 from public.app_secrets where key = 'cred_cron_ads_autopilot') then
    v_cred := public.fn_internal_credential_issue('cron.ads_autopilot', array['meta_ads'],
                'ads autopilot daily tick -> meta_ads execute_decisions (3 Sep 2026)');
    insert into public.app_secrets (key, value) values ('cred_cron_ads_autopilot', v_cred->>'secret');
  end if;

  -- 2. the daily tick
  select jobid into v_job from cron.job where jobname = 'ads_autopilot_daily';
  if v_job is null then
    -- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").
    -- This scheduled ads_autopilot_daily, which was deleted from cron.job in the same change.
    -- The notice replaces the call so this routine still runs and still reports, rather
    -- than silently doing nothing or quietly recreating a job nobody asked for.
    raise notice 'cron scheduling removed on 7 Sep 2026: ads_autopilot_daily is not recreated';
  end if;
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'marketing_director', 'growth');
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values (v_job, 'ads_autopilot_daily',
          'Runs fn_ads_manage(false) over REAL ad campaigns: INSERTs public.ad_decision, then (only if decisions are waiting) posts to meta_ads execute_decisions, which UPDATEs ad_decision / ad_campaign_state and INSERTs public.agent_runs.',
          'Daily 04:20 UTC. fn_ads_manage(false) reads only is_demo=false campaigns, so a scenario''s fixtures (is_demo=true, tagged zzdemo-ads-*) are invisible to it and its writes never touch a scenario row; the rehearsal proves fn_ads_manage(false) writes nothing about demo campaigns. Its own transaction on a scheduled tick; close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;

  -- 3. meta_sync_daily back on the clock, traced
  perform public.fn_kernel_wrap_and_enable_cron(72, 'marketing_director', 'growth');
  -- the wrap resets authority_class to its default on a component that was ALREADY declared; put the
  -- committed crosswalk value back so the live row and docs/phase-c/PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv agree
  update public.phase_c_component set authority_class = 'marketing_publish' where component_id = 'cron:meta_sync_daily';
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values (72, 'meta_sync_daily',
          'With meta_access_token: UPSERTs public.meta_insights and public.ad_campaign_state, UPDATEs public.ad_spend_policy.month_spent_aed, INSERTs public.agent_runs. Without the token: INSERTs one agent_runs row (status skipped) and nothing else.',
          'Daily 03:35 UTC. Writes are keyed by Meta campaign id (never a zzdemo-* id) and by the single policy row; a scenario''s fixtures carry is_demo=true and zzdemo-ads-* ids, which Meta never returns. Own transaction on a scheduled tick; close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;
commit;
