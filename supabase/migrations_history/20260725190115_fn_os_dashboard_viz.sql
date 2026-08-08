-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260725190115   name: fn_os_dashboard_viz
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_os_dashboard_viz()
returns jsonb
language plpgsql stable security definer
set search_path to 'public','pg_catalog'
as $$
declare
  out jsonb := '{}'::jsonb;
  v_total bigint; v_contacted bigint; v_invited bigint; v_claimed bigint;
  v_registered bigint; v_verified bigint; v_approved bigint;
  v_runs24 bigint; v_agents24 bigint;
  j_sector jsonb; j_emirate jsonb; j_invites jsonb; j_agents jsonb; j_funnel jsonb; j_pipeline jsonb;
begin
  select count(*) into v_total from leads;
  select count(*) into v_contacted from leads where contacted is true;
  select count(*) into v_invited from leads where invited_at is not null;
  select count(*) into v_claimed from leads where claimed is true;
  select count(*) into v_registered from leads where registration_submitted_at is not null;
  select count(*) into v_verified from leads where verified is true;
  select count(*) into v_approved from leads where approved_at is not null;

  -- agent activity (best-effort; agent_actions may be large)
  begin
    select count(*) into v_runs24 from agent_actions where created_at > now() - interval '24 hours';
    select count(distinct actor) into v_agents24 from agent_actions where created_at > now() - interval '24 hours';
    select coalesce(jsonb_agg(x), '[]'::jsonb) into j_agents from (
      select actor as agent, count(*)::int as runs
      from agent_actions where created_at > now() - interval '24 hours'
      group by actor order by count(*) desc limit 10
    ) x;
  exception when others then v_runs24 := 0; v_agents24 := 0; j_agents := '[]'::jsonb; end;

  -- suppliers by sector (top 12)
  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_sector from (
    select coalesce(nullif(trim(sector),''),'unspecified') as label, count(*)::int as n
    from leads group by 1 order by count(*) desc limit 12
  ) x;

  -- suppliers by emirate
  select coalesce(jsonb_agg(x), '[]'::jsonb) into j_emirate from (
    select coalesce(nullif(trim(emirate),''),'unknown') as label, count(*)::int as n
    from leads group by 1 order by count(*) desc limit 9
  ) x;

  -- invites over the last 14 days (zero-filled)
  select coalesce(jsonb_agg(jsonb_build_object('d', to_char(d.day,'Mon DD'), 'n', coalesce(c.n,0)) order by d.day), '[]'::jsonb)
    into j_invites
  from (select generate_series((current_date - interval '13 days')::date, current_date, interval '1 day')::date as day) d
  left join (select invited_at::date as day, count(*)::int as n from leads where invited_at > now() - interval '14 days' group by 1) c
    on c.day = d.day;

  -- supplier lifecycle funnel
  j_funnel := jsonb_build_array(
    jsonb_build_object('stage','Sourced', 'n', v_total),
    jsonb_build_object('stage','Contacted', 'n', v_contacted),
    jsonb_build_object('stage','Invited', 'n', v_invited),
    jsonb_build_object('stage','Claimed', 'n', v_claimed),
    jsonb_build_object('stage','Registered', 'n', v_registered),
    jsonb_build_object('stage','Verified', 'n', v_verified),
    jsonb_build_object('stage','Approved', 'n', v_approved)
  );

  -- marketplace pipeline (RFQ lifecycle)
  begin
    j_pipeline := jsonb_build_array(
      jsonb_build_object('stage','New', 'n', (select count(*) from inquiries)),
      jsonb_build_object('stage','Matched', 'n', (select count(distinct inquiry_id) from quotes)),
      jsonb_build_object('stage','Quoted', 'n', (select count(*) from quotes)),
      jsonb_build_object('stage','Revealed', 'n', (select count(*) from quotes where coalesce(revealed,false) is true)),
      jsonb_build_object('stage','Won', 'n', (select count(*) from inquiries where status = 'won'))
    );
  exception when others then j_pipeline := jsonb_build_array(); end;

  out := jsonb_build_object(
    'headline', jsonb_build_object(
      'suppliers_total', v_total, 'invited_total', v_invited, 'verified_total', v_verified,
      'approved_total', v_approved, 'registered_total', v_registered,
      'agents_active_24h', v_agents24, 'runs_24h', v_runs24),
    'funnel', j_funnel,
    'pipeline', j_pipeline,
    'by_sector', j_sector,
    'by_emirate', j_emirate,
    'invites_14d', j_invites,
    'agents_24h', j_agents,
    'generated_at', to_char(now(),'YYYY-MM-DD"T"HH24:MI:SSOF')
  );
  return out;
end $$;
