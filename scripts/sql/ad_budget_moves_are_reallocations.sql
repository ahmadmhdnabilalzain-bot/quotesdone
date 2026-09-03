-- EVERY EXECUTED AD-BUDGET MOVE IS A REALLOCATION OF MARKETING BUDGET BETWEEN CHANNELS, AND IT
-- CITES THE POLICY THAT MOVED IT.
--
-- Measured 3 Sep 2026: allocation_change carried two resource classes in 62 days (ai_budget_aed,
-- supplier_onboarding_capacity) and never a marketing one. The ad spend autopilot has been moving
-- daily budget between campaigns since 3 Sep — scale a winner, pause a loser, activate what fits,
-- pace everything down when the month runs short — and wrote each move only to ad_decision. A budget
-- that moves from one channel to another IS a reallocation, and the spec's ledger for reallocations
-- never saw it.
--
-- The seam is the moment a decision is EXECUTED (fn_ad_decision_mark_executed is the one routine
-- that turns a decision into a state change; meta_ads calls it in live and sandbox mode alike), not
-- the moment it is decided: a pending decision has moved nothing. from/to are the campaign's daily
-- allocation before and after — set_daily_budget: old -> new; pause: old -> 0; activate: 0 -> daily.
-- The policy cited is the live ad_spend_policy row's parameters plus the rule that fired, so the
-- ledger row stands on its own.
--
-- Sandbox executions (no meta_access_token; demo campaigns only) are recorded with the execution
-- mode in the reason and the demo campaign as the subject. The rehearsal that drives them tears its
-- rows down by tag. No real campaign moves until the founder mints the token — this file builds
-- the wire; the class is covered the day a real campaign's budget moves.
--
-- reallocate_monthly (job 166, fn_reallocate) is re-enabled as a traced kernel component under the
-- role its component row already carries (corporate_performance_director / exec).
--
--   node scripts/apply_sql.mjs scripts/sql/ad_budget_moves_are_reallocations.sql --apply --ddl

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
                 p.daily_cap_aed, public.fn_ad_spend_daily_ceiling()));
end;
$function$;

-- The reallocation cron runs again, traced through the kernel.
select public.fn_kernel_wrap_and_enable_cron(166, 'corporate_performance_director', 'exec');
update public.phase_c_component c
   set accountable_role_id = 'corporate_performance_director', department_id = 'exec', activation_state = 'active'
  from public.phase_c_system_execution_wrapper w
 where w.jobid = 166 and c.component_id = w.component_id;

do $$
declare v_bad int;
begin
  select count(*) into v_bad
    from public.phase_c_system_execution_wrapper w
    join public.phase_c_component c on c.component_id = w.component_id
   where w.jobid = 166
     and not exists (select 1 from public.org_role o where o.role_id = c.accountable_role_id);
  if v_bad > 0 then
    raise exception 'reallocate_monthly: accountable role does not resolve in org_role';
  end if;
end $$;
