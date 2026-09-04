-- AD SPEND NEEDS THE FOUNDER'S CAP AND HIS GO (4 Sep 2026) — MASTER_PLAN D1 + the D3 optimizer half.
--
-- WHAT WAS MEASURED before this file: the autopilot's daily cap lived ONLY in
-- ad_spend_policy.daily_cap_aed (200 — an engineering default written on 3 Sep, not a number the
-- founder chose) and its only "master switch" was whether app_secrets.meta_access_token existed.
-- The plan names two app_secrets keys the code did not read: meta_daily_budget_cap_aed and
-- meta_autospend_golive. Neither row existed. So a token alone would have started real spend at
-- 200 AED/day the morning after it was pasted.
--
-- WHAT THIS FILE DOES
--   app_secrets.meta_daily_budget_cap_aed   the founder's REAL daily ceiling, in AED. Seeded as the
--                                           literal 'UNSET'; anything that is not a positive number
--                                           means "not set" and the real ceiling is 0 — spend nothing.
--   app_secrets.meta_autospend_golive       'false' | 'true'. His go switch for autonomous ad spend,
--                                           the same shape as marketing_golive / invite_enabled.
--   fn_ads_autospend_state()                the three facts in one place: golive, token present, cap.
--                                           live_allowed = all three. No secret VALUE leaves it.
--   fn_ad_spend_daily_ceiling(p_demo)       demo campaigns keep the policy's daily_cap_aed (the
--                                           sandbox ceiling — the rehearsal runs on it); REAL campaigns
--                                           use the founder's cap secret in its place, and 0 when
--                                           live_allowed is false. The zero-argument form = real.
--   fn_ad_spend_ceiling_guard()             BEFORE any activate / budget increase on a REAL campaign
--                                           it now refuses with AD_SPEND_GOLIVE unless live_allowed;
--                                           above the founder's cap it refuses with AD_SPEND_CEILING
--                                           as before. Pauses and reductions always pass. That is the
--                                           founder gate on money leaving: below his number the
--                                           manager auto-approves, above it nothing but him raising
--                                           the number lets a decision through.
--   fn_ads_manage(p_demo)                   for real campaigns, does nothing at all while live_allowed
--                                           is false (it does NOT pause a campaign he switched on by
--                                           hand in Ads Manager); demo behaviour unchanged.
--                                           D3: an insight row older than 3 days is NO DATA (null),
--                                           never "spend fell to 0"; of two rows synced together the
--                                           last_30d window is judged, not lifetime.
--   fn_ads_autopilot_tick()                 reports the autospend state in its result so a silent
--                                           tick says why.
--   fn_ad_decision_mark_executed()          the reallocation ledger cites the ceiling of the world the
--                                           campaign lives in (demo or real), not always the real one.
--
--   node scripts/apply_sql.mjs scripts/sql/ad_spend_needs_the_founders_cap_and_go.sql --apply --ddl

insert into public.app_secrets (key, value) values ('meta_daily_budget_cap_aed', 'UNSET') on conflict (key) do nothing;
insert into public.app_secrets (key, value) values ('meta_autospend_golive', 'false') on conflict (key) do nothing;

create or replace function public.fn_ads_autospend_state()
returns jsonb
language sql
stable
set search_path to 'public'
as $$
  with s as (
    select
      coalesce((select lower(trim(value)) from public.app_secrets where key = 'meta_autospend_golive'), 'false') = 'true' as golive,
      coalesce((select length(trim(value)) >= 24 from public.app_secrets where key = 'meta_access_token'), false)        as token_present,
      (select case when trim(value) ~ '^[0-9]+(\.[0-9]+)?$' and trim(value)::numeric > 0 then trim(value)::numeric end
         from public.app_secrets where key = 'meta_daily_budget_cap_aed')                                               as cap_aed
  )
  select jsonb_build_object(
    'golive', golive,
    'token_present', token_present,
    'cap_aed', cap_aed,
    'live_allowed', golive and token_present and cap_aed is not null,
    'reason', case
      when not golive then 'meta_autospend_golive is not ''true'''
      when not token_present then 'meta_access_token is absent'
      when cap_aed is null then 'meta_daily_budget_cap_aed is not a positive number'
      else 'live spend allowed under ' || cap_aed || ' AED/day' end)
  from s;
$$;
revoke execute on function public.fn_ads_autospend_state() from public, anon, authenticated;

create or replace function public.fn_ad_spend_daily_ceiling(p_demo boolean)
returns numeric
language sql
stable
set search_path to 'public'
as $$
  -- NOTE the explicit null branch: greatest()/least() IGNORE nulls in Postgres, so
  -- greatest(0, null - x) is 0, not null, and the first cut of this function paced every
  -- campaign to zero whenever no monthly cap was set.
  with st as (select public.fn_ads_autospend_state() j),
  cap as (
    select case
      when p_demo then p.daily_cap_aed
      when (st.j->>'live_allowed')::boolean then (st.j->>'cap_aed')::numeric
      else 0 end as daily_cap, p.*
    from public.ad_spend_policy p, st
    where p.policy_key = 'default')
  select case
    when cap.monthly_cap_aed is null then cap.daily_cap
    else least(
      cap.daily_cap,
      greatest(0, cap.monthly_cap_aed - case when cap.month_label = to_char(now(), 'YYYY-MM') then cap.month_spent_aed else 0 end)
        / greatest(1, (date_trunc('month', now()) + interval '1 month')::date - current_date))
  end
  from cap;
$$;
revoke execute on function public.fn_ad_spend_daily_ceiling(boolean) from public, anon, authenticated;

-- the zero-argument form every existing caller uses = the REAL ceiling
create or replace function public.fn_ad_spend_daily_ceiling()
returns numeric
language sql
stable
set search_path to 'public'
as $$
  select public.fn_ad_spend_daily_ceiling(false);
$$;

create or replace function public.fn_ad_spend_ceiling_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  s        public.ad_campaign_state%rowtype;
  p        public.ad_spend_policy%rowtype;
  st       jsonb;
  v_ceiling numeric;
  v_total  numeric;
  v_new_budget numeric;
  v_new_active boolean;
begin
  select * into s from public.ad_campaign_state where campaign_id = new.campaign_id;
  if not found then
    raise exception 'AD_SPEND_GUARD: decision for unknown campaign %', new.campaign_id using errcode = '23503';
  end if;
  select * into p from public.ad_spend_policy where policy_key = 'default';

  v_new_budget := case when new.action = 'set_daily_budget' then new.amount_aed else s.daily_budget_aed end;
  v_new_active := case new.action when 'activate' then true when 'pause' then false else (s.status = 'ACTIVE') end;

  if new.action = 'set_daily_budget' and new.amount_aed > p.max_daily_per_campaign_aed then
    raise exception 'AD_SPEND_GUARD: % AED/day on campaign % exceeds the per-campaign maximum of % AED',
      new.amount_aed, new.campaign_id, p.max_daily_per_campaign_aed using errcode = 'P0001';
  end if;
  if new.action = 'activate' and s.daily_budget_aed <= 0 then
    raise exception 'AD_SPEND_GUARD: campaign % cannot be activated with no daily budget', new.campaign_id using errcode = 'P0001';
  end if;

  -- A decision that takes money OFF Meta is always allowed: a pause, or a budget at or below the
  -- current one. The guard exists to stop INCREASES beyond the ceiling; refusing a reduction would
  -- make the pacing arm unable to bring an over-ceiling set back down one campaign at a time (the
  -- first rehearsal hit exactly that).
  if new.action = 'pause' or (new.action = 'set_daily_budget' and new.amount_aed <= s.daily_budget_aed) then
    return new;
  end if;

  -- THE FOUNDER'S GO (4 Sep 2026): real money may only be switched on or raised when his go switch
  -- is 'true', his token exists and his daily cap is a number. Demo campaigns are the sandbox.
  if not s.is_demo then
    st := public.fn_ads_autospend_state();
    if not (st->>'live_allowed')::boolean then
      raise exception 'AD_SPEND_GOLIVE: % on real campaign % refused: % (rule %)',
        new.action, new.campaign_id, st->>'reason', new.rule_key using errcode = 'P0001';
    end if;
  end if;

  v_ceiling := public.fn_ad_spend_daily_ceiling(s.is_demo);
  select coalesce(sum(case when c.campaign_id = new.campaign_id then v_new_budget else c.daily_budget_aed end), 0)
    into v_total
  from public.ad_campaign_state c
  where c.is_demo = s.is_demo
    and (c.status = 'ACTIVE' or c.campaign_id = new.campaign_id)
    and (c.campaign_id <> new.campaign_id or v_new_active);

  if v_total > v_ceiling then
    raise exception 'AD_SPEND_CEILING: % would put % AED/day on Meta against an effective ceiling of % AED/day (campaign %, rule %)',
      new.action, v_total, v_ceiling, new.campaign_id, new.rule_key using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- THE MANAGER. Deterministic; returns the decisions it wrote this tick.
create or replace function public.fn_ads_manage(p_demo boolean default false, p_run_tag text default null)
returns setof public.ad_decision
language plpgsql
set search_path to 'public'
as $$
declare
  p          public.ad_spend_policy%rowtype;
  v_ceiling  numeric;
  v_active   numeric;
  c          record;
  v_cpl      numeric;
  v_learning boolean;
  v_new      numeric;
  v_factor   numeric;
  d          public.ad_decision%rowtype;
begin
  -- 0. THE FOUNDER'S GO. Real campaigns are not managed at all until his switch, token and cap are
  --    in place: nothing is activated, nothing is raised, and nothing he switched on by hand in Ads
  --    Manager is paused by a manager that has not been given the go. The guard refuses the same
  --    things independently; this early return keeps the ledger free of refused attempts.
  if not p_demo and not (public.fn_ads_autospend_state()->>'live_allowed')::boolean then
    return;
  end if;

  select * into p from public.ad_spend_policy where policy_key = 'default';
  v_ceiling := public.fn_ad_spend_daily_ceiling(p_demo);

  -- 1. PACE. If the active set already exceeds the ceiling, shrink it before judging anyone.
  select coalesce(sum(daily_budget_aed), 0) into v_active
  from public.ad_campaign_state where is_demo = p_demo and status = 'ACTIVE'
    and campaign_id not in (select campaign_id from public.ad_decision where executed_at is null);
  if v_active > v_ceiling then
    v_factor := v_ceiling / v_active;
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by coalesce(m.cpl, 1e12) asc
    loop
      v_new := greatest(p.min_daily_per_campaign_aed, floor(c.daily_budget_aed * v_factor));
      if v_new < c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'pace_down',
                format('active daily total %s AED exceeds the effective ceiling %s AED; scaled by %s', v_active, v_ceiling, round(v_factor, 3)),
                jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'factor', v_factor, 'from', c.daily_budget_aed),
                p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end loop;
    -- if the minimums still do not fit, pause the worst cost-per-lead until they do
    for c in
      select s.*, m.cpl from public.ad_campaign_state s
      left join lateral (
        select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
        from public.meta_insights i where i.campaign_id = s.campaign_id
          and i.synced_at > now() - interval '3 days'
        order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
      ) m on true
      where s.is_demo = p_demo and s.status = 'ACTIVE'
      order by coalesce(m.cpl, 1e12) desc
    loop
      exit when v_active <= v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'pace_pause',
              format('even at minimum budgets the active set (%s AED) exceeds the ceiling (%s AED); pausing the worst cost per lead', v_active, v_ceiling),
              jsonb_build_object('active_total', v_active, 'ceiling', v_ceiling, 'cpl', c.cpl), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active - least(c.daily_budget_aed, greatest(p.min_daily_per_campaign_aed, floor(c.daily_budget_aed * coalesce(v_factor, 1))));
    end loop;
    return;  -- a pacing tick judges nothing else; the next tick sees the paced set
  end if;

  -- 2. JUDGE every active campaign that has no decision waiting.
  --    D3 (4 Sep 2026): the evidence is the FRESHEST row within 3 days, last_30d preferred over the
  --    lifetime window synced beside it. No fresh row = no data = the campaign is held, exactly like
  --    a learner. meta_sync no longer writes a row when Meta errors or returns nothing, so a missing
  --    or stale row can never read as "spend fell to 0" and pause a winner.
  for c in
    select s.*, m.spend, m.results, m.has_results_field
    from public.ad_campaign_state s
    left join lateral (
      select i.spend, i.results, (i.results is not null) as has_results_field
      from public.meta_insights i where i.campaign_id = s.campaign_id
        and i.synced_at > now() - interval '3 days'
      order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
    ) m on true
    where s.is_demo = p_demo and s.status = 'ACTIVE'
      and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
    order by s.campaign_id
  loop
    v_learning := (c.started_at is null)
                  or (c.started_at > now() - make_interval(days => p.learning_phase_days))
                  or (coalesce(c.spend, 0) < p.learning_min_spend_aed);

    -- tracking gate: spent past the threshold and results are not even reported
    if coalesce(c.spend, 0) >= p.learning_min_spend_aed and not coalesce(c.has_results_field, false) then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'tracking_gate',
              format('%s AED spent and no results field is reported: conversions are not tracked, so nothing can be judged', c.spend),
              jsonb_build_object('spend', c.spend), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    if v_learning then
      continue;  -- not judged on its first days, nor without fresh data
    end if;

    v_cpl := case when coalesce(c.results, 0) > 0 then c.spend / c.results else null end;

    -- kill: past learning and the cost per lead is above the multiplier, or spend with no leads
    if v_cpl is null or v_cpl > p.kill_multiplier * p.target_cpl_aed then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'kill_3x',
              case when v_cpl is null
                   then format('%s AED spent past the learning phase with no leads at all', c.spend)
                   else format('cost per lead %s AED is above %s x the %s AED target', round(v_cpl, 2), p.kill_multiplier, p.target_cpl_aed) end,
              jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', p.target_cpl_aed, 'kill_multiplier', p.kill_multiplier), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    -- scale: at or under target, room on the campaign and under the ceiling
    if v_cpl <= p.target_cpl_aed and c.daily_budget_aed < p.max_daily_per_campaign_aed then
      v_new := least(p.max_daily_per_campaign_aed,
                     floor(c.daily_budget_aed * (1 + p.scale_step_pct / 100.0)),
                     c.daily_budget_aed + greatest(0, v_ceiling - v_active));
      if v_new > c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'scale_winner',
                format('cost per lead %s AED is at or under the %s AED target; raising %s to %s AED/day', round(v_cpl, 2), p.target_cpl_aed, c.daily_budget_aed, v_new),
                jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'from', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
        returning * into d;
        return next d;
        v_active := v_active - c.daily_budget_aed + v_new;
      end if;
    end if;
  end loop;

  -- 3. ACTIVATE never-run paused campaigns that fit under the ceiling.
  if p.auto_activate then
    for c in
      select s.* from public.ad_campaign_state s
      where s.is_demo = p_demo and s.status = 'PAUSED' and s.started_at is null and s.daily_budget_aed > 0
        and s.campaign_id not in (select campaign_id from public.ad_decision where executed_at is null)
      order by s.daily_budget_aed asc
    loop
      exit when v_active + c.daily_budget_aed > v_ceiling;
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'activate', 'activate',
              format('never run, carries %s AED/day and fits under the %s AED/day ceiling (active total %s)', c.daily_budget_aed, v_ceiling, v_active),
              jsonb_build_object('daily_budget', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
      returning * into d;
      return next d;
      v_active := v_active + c.daily_budget_aed;
    end loop;
  end if;
  return;
end;
$$;

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
  v_state   jsonb;
begin
  v_state := public.fn_ads_autospend_state() - 'cap_aed';
  select count(*) into v_decided from public.fn_ads_manage(false, null);
  select count(*) into v_pending from public.ad_decision where executed_at is null;
  if v_pending = 0 then
    return jsonb_build_object('decided', v_decided, 'pending', 0, 'posted', false, 'autospend', v_state);
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
  return jsonb_build_object('decided', v_decided, 'pending', v_pending, 'posted', true, 'request_id', v_req, 'autospend', v_state);
end;
$$;

create or replace function public.fn_ad_decision_mark_executed(p_id bigint, p_mode text, p_response jsonb default '{}'::jsonb)
 returns void
 language plpgsql
 set search_path to 'public'
as $function$
declare
  d      public.ad_decision%rowtype;
  s      public.ad_campaign_state%rowtype;
  p      public.ad_spend_policy%rowtype;
  v_from numeric;
  v_to   numeric;
begin
  select * into d from public.ad_decision where id = p_id for update;
  if not found then raise exception 'ad_decision % does not exist', p_id; end if;
  if d.executed_at is not null then return; end if;

  -- the channel's allocation BEFORE the move
  select * into s from public.ad_campaign_state where campaign_id = d.campaign_id;

  update public.ad_decision set executed_at = now(), execution_mode = p_mode, api_response = p_response where id = p_id;
  update public.ad_campaign_state set
    status = case d.action when 'activate' then 'ACTIVE' when 'pause' then 'PAUSED' else status end,
    daily_budget_aed = case d.action when 'set_daily_budget' then d.amount_aed else daily_budget_aed end,
    started_at = case when d.action = 'activate' then coalesce(started_at, now()) else started_at end,
    updated_at = now()
  where campaign_id = d.campaign_id;

  -- the reallocation ledger: marketing budget between channels, citing the policy that moved it
  if s.campaign_id is null then return; end if;
  v_from := case d.action
              when 'set_daily_budget' then coalesce((d.evidence->>'from')::numeric, s.daily_budget_aed)
              when 'pause'            then case when s.status = 'ACTIVE' then s.daily_budget_aed else 0 end
              when 'activate'         then 0
              else null end;
  v_to   := case d.action
              when 'set_daily_budget' then d.amount_aed
              when 'pause'            then 0
              when 'activate'         then s.daily_budget_aed
              else null end;
  if v_from is null or v_to is null or v_from = v_to then return; end if;

  select * into p from public.ad_spend_policy where policy_key = 'default';
  insert into public.allocation_change (resource, subject, from_value, to_value, reason, policy)
  values ('marketing_budget_channels', d.campaign_id, v_from, v_to,
          format('%s: %s [ad_decision %s executed %s on %s]',
                 d.rule_key, d.reason, d.id, p_mode, coalesce(s.campaign_name, d.campaign_id)),
          format('ad_spend_policy %s, rule %s: target CPL %s AED, kill at %sx, scale step %s%%, '
                 || 'per-campaign %s..%s AED/day, daily cap %s AED, effective ceiling %s AED/day',
                 coalesce(p.policy_key, 'default'), d.rule_key, p.target_cpl_aed, p.kill_multiplier,
                 p.scale_step_pct, p.min_daily_per_campaign_aed, p.max_daily_per_campaign_aed,
                 case when s.is_demo then p.daily_cap_aed else coalesce((public.fn_ads_autospend_state()->>'cap_aed')::numeric, 0) end,
                 public.fn_ad_spend_daily_ceiling(s.is_demo)));
end;
$function$;
