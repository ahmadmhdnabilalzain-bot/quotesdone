-- fn_ads_manage CARRIES BOTH 4 SEP CHANGES (integration, 4 Sep 2026).
--
-- Two parallel packets changed this routine the same morning: the ad-spend packet made the real
-- ceiling the founder's cap and go-live switch (ad_spend_needs_the_founders_cap_and_go.sql), and the
-- dead-triggers packet made the pacing branch emit budget.exceeded once per scope per day
-- (dead_workflow_triggers_get_their_real_emitters.sql). Production ran whichever applied last; the
-- manifest named the other canonical. This file is the union: the founder-cap body with the emit
-- block inside its pacing branch. Nothing else changes.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ads_manage_paces_under_the_founders_cap_and_emits_budget_exceeded.sql --apply --ddl
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
    -- 4 Sep 2026: this is the "Meta optimizer over cap" moment MASTER_PLAN §4.4 names as the
    -- producer of budget.exceeded (budget_cycle's trigger). The pacing below is the remedy; the
    -- event is the record Finance consumes (cfo, brief). Once per scope per day.
    if not exists (select 1 from public.company_event e
                    where e.event_type = 'budget.exceeded' and e.entity_type = 'ad_spend'
                      and e.entity_id = case when p_demo then 'demo' else 'meta' end
                      and e.occurred_at > now() - interval '24 hours') then
      perform public.fn_emit('budget.exceeded', 'ad_spend', case when p_demo then 'demo' else 'meta' end,
        'ads_autopilot',
        jsonb_build_object('requested_aed', v_active, 'available_aed', v_ceiling,
          'purpose', 'daily Meta ad spend across the active campaign set',
          'reason', format('active daily total %s AED exceeds the effective ceiling %s AED; pacing down', v_active, v_ceiling),
          'run_tag', p_run_tag, 'is_demo', p_demo));
    end if;
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
