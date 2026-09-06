-- ADS HAVE A 30 AED DAILY CAP AND NO FOUNDER COST-PER-LEAD TARGET (6 Sep 2026, the founder's decisions).
--
--   "meta token is already with you, and the daily budget cap is 30 AED per day. that target you ingested
--    i never actually mentioned it [the AED 150 cost-per-lead target]. ... these are my decisions so never
--    ask about them again. make sure everything is in sync"
--
-- WHAT WAS MEASURED BEFORE THIS FILE. app_secrets.meta_daily_budget_cap_aed held a 5-character value that
-- is not a positive number (fn_ads_autospend_state reported "meta_daily_budget_cap_aed is not a positive
-- number"); ad_spend_policy.default had daily_cap_aed 200, target_cpl_aed 150, max_daily_per_campaign_aed
-- 100; fn_ads_manage killed at kill_multiplier x target_cpl_aed and scaled at <= target_cpl_aed, so a NULL
-- target would have made both rules silently inert (NULL comparisons) rather than derived; the
-- reallocation ledger text in fn_ad_decision_mark_executed printed "target CPL  AED" for a NULL target.
-- meta_autospend_golive = 'false'; app_secrets holds NO meta_access_token row (0 rows by key;
-- fn_ads_autospend_state token_present = false) - the founder says the token is with us, the store says it is
-- not, and company_policy_decision.meta_token_and_daily_cap records the absence. No knowledge record
-- outside the category packs states "AED 150" (ops_knowledge, agent_knowledge, pages, company_faq: 0 rows).
-- Measured after the first apply (the adversarial verifier, 6 Sep 2026): target_cpl_aed had lost NOT NULL and
-- its value, but kept column DEFAULT '150' - a fresh policy row would have re-acquired the never-founder's
-- target. The default is dropped below and the proof asserts information_schema says so.
--
-- WHAT THIS FILE DOES, BY MECHANISM.
--   * app_secrets.meta_daily_budget_cap_aed = '30' (the founder's cap). meta_autospend_golive is NOT touched:
--     it stays 'false' until he switches it on, so live spend is still refused by fn_ads_autospend_state.
--   * ad_spend_policy.default: daily_cap_aed 30 (the same cap for the demo arm), target_cpl_aed NULL (no
--     founder target; the column is nullable with NO default, so no future row inherits 150),
--     max_daily_per_campaign_aed 30 (one campaign can never exceed the daily cap).
--   * fn_ads_manage(): with target_cpl_aed NULL the target is DERIVED - the median measured cost per lead of
--     the active campaigns that have results - and every decision names its source. With no measured leads
--     there is no target: spend with no leads past learning is still killed; nothing is scaled.
--   * fn_ad_decision_mark_executed(): the policy text in the reallocation ledger says the target is derived.
--   * The proof rehearses the derived rule on demo campaigns inside a sub-transaction that is rolled back.
--
--   node scripts/apply_sql.mjs scripts/sql/ads_have_a_30_aed_daily_cap_and_no_founder_cpl_target.sql --apply --ddl
begin;

-- 1. THE CAP AND THE POLICY.
update public.app_secrets set value = '30', updated_at = now() where key = 'meta_daily_budget_cap_aed';
insert into public.app_secrets (key, value)
select 'meta_daily_budget_cap_aed', '30' where not exists (select 1 from public.app_secrets where key = 'meta_daily_budget_cap_aed');

-- measured on the first apply: the column was NOT NULL (23502 rolled the file back); NULL is the rule now
alter table public.ad_spend_policy alter column target_cpl_aed drop not null;
-- measured after the first apply: column_default was still '150' - a new policy row would re-acquire the
-- target the founder never gave. No default: a fresh row has no target until measured data derives one.
alter table public.ad_spend_policy alter column target_cpl_aed drop default;
update public.ad_spend_policy
   set daily_cap_aed = 30,
       target_cpl_aed = null,
       max_daily_per_campaign_aed = least(max_daily_per_campaign_aed, 30),
       min_daily_per_campaign_aed = least(min_daily_per_campaign_aed, 30),
       updated_at = now()
 where policy_key = 'default';
comment on column public.ad_spend_policy.target_cpl_aed is
  'Founder, 6 Sep 2026: NULL and stays NULL - there is no founder cost-per-lead target (the AED 150 figure was never his). fn_ads_manage derives the target from measured campaign data: the median CPL of the active set with results.';
comment on column public.ad_spend_policy.daily_cap_aed is
  'Founder, 6 Sep 2026: AED 30 per day. The live arm reads app_secrets.meta_daily_budget_cap_aed (the same 30); this column is the demo arm''s cap.';

-- 2. THE AD MANAGER derives its target.
CREATE OR REPLACE FUNCTION public.fn_ads_manage(p_demo boolean DEFAULT false, p_run_tag text DEFAULT NULL::text)
 RETURNS SETOF ad_decision
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
  v_target   numeric;
  v_target_src text;
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

  -- 6 Sep 2026 (founder): there is NO founder cost-per-lead target ("that target you ingested i never
  -- actually mentioned it"). With ad_spend_policy.target_cpl_aed NULL the target is DERIVED from measured
  -- campaign data: the median cost per lead of the active campaigns that have results in their freshest
  -- row (3 days). Until at least one campaign has measured leads there is no target: spend with no leads
  -- past learning is still killed, and nothing is scaled.
  if p.target_cpl_aed is not null then
    v_target := p.target_cpl_aed; v_target_src := 'ad_spend_policy';
  else
    select percentile_cont(0.5) within group (order by m.cpl) into v_target
    from public.ad_campaign_state s
    join lateral (
      select case when coalesce(i.results, 0) > 0 then i.spend / i.results else null end as cpl
      from public.meta_insights i where i.campaign_id = s.campaign_id
        and i.synced_at > now() - interval '3 days'
      order by (i.time_window = 'last_30d') desc, i.synced_at desc limit 1
    ) m on true
    where s.is_demo = p_demo and s.status = 'ACTIVE' and m.cpl is not null;
    v_target_src := 'median measured CPL of the active set (no founder target)';
  end if;

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
    if v_cpl is null or (v_target is not null and v_cpl > p.kill_multiplier * v_target) then
      insert into public.ad_decision (campaign_id, action, rule_key, reason, evidence, run_tag)
      values (c.campaign_id, 'pause', 'kill_3x',
              case when v_cpl is null
                   then format('%s AED spent past the learning phase with no leads at all', c.spend)
                   else format('cost per lead %s AED is above %s x the %s AED target (%s)', round(v_cpl, 2), p.kill_multiplier, round(v_target, 2), v_target_src) end,
              jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', v_target, 'target_source', v_target_src, 'kill_multiplier', p.kill_multiplier), p_run_tag)
      returning * into d;
      return next d;
      continue;
    end if;

    -- scale: at or under target, room on the campaign and under the ceiling
    if v_target is not null and v_cpl <= v_target and c.daily_budget_aed < p.max_daily_per_campaign_aed then
      v_new := least(p.max_daily_per_campaign_aed,
                     floor(c.daily_budget_aed * (1 + p.scale_step_pct / 100.0)),
                     c.daily_budget_aed + greatest(0, v_ceiling - v_active));
      if v_new > c.daily_budget_aed then
        insert into public.ad_decision (campaign_id, action, amount_aed, rule_key, reason, evidence, run_tag)
        values (c.campaign_id, 'set_daily_budget', v_new, 'scale_winner',
                format('cost per lead %s AED is at or under the %s AED target (%s); raising %s to %s AED/day', round(v_cpl, 2), round(v_target, 2), v_target_src, c.daily_budget_aed, v_new),
                jsonb_build_object('spend', c.spend, 'results', c.results, 'cpl', v_cpl, 'target_cpl', v_target, 'target_source', v_target_src, 'from', c.daily_budget_aed, 'ceiling', v_ceiling, 'active_total', v_active), p_run_tag)
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
$function$;

-- 3. THE REALLOCATION LEDGER names the derived target.
CREATE OR REPLACE FUNCTION public.fn_ad_decision_mark_executed(p_id bigint, p_mode text, p_response jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
                 coalesce(p.policy_key, 'default'), d.rule_key,
                 coalesce(p.target_cpl_aed::text, 'derived from measured campaign data (no founder target, 6 Sep 2026)'), p.kill_multiplier,
                 p.scale_step_pct, p.min_daily_per_campaign_aed, p.max_daily_per_campaign_aed,
                 case when s.is_demo then p.daily_cap_aed else coalesce((public.fn_ads_autospend_state()->>'cap_aed')::numeric, 0) end,
                 public.fn_ad_spend_daily_ceiling(s.is_demo)));
end;
$function$;

-- 4. THE OWNERSHIP LEDGER follows the manifest (neither routine had a row).
insert into public.kernel_routine_ownership (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public', 'fn_ads_manage', 'p_demo boolean, p_run_tag text', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/ads_have_a_30_aed_daily_cap_and_no_founder_cpl_target.sql (6 Sep 2026): the CPL target is derived from measured data, never a founder figure.', 'MANIFEST', 'scripts/sql/ads_have_a_30_aed_daily_cap_and_no_founder_cpl_target.sql'),
  ('public', 'fn_ad_decision_mark_executed', 'p_id bigint, p_mode text, p_response jsonb', 'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'defined by scripts/sql/ads_have_a_30_aed_daily_cap_and_no_founder_cpl_target.sql (6 Sep 2026): the reallocation ledger names the derived target.', 'MANIFEST', 'scripts/sql/ads_have_a_30_aed_daily_cap_and_no_founder_cpl_target.sql')
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule, evidence = excluded.evidence,
  source_kind = excluded.source_kind, source_file = excluded.source_file, justification = null, recorded_at = now();

-- 5. PROOF. Values read back (never the token), then a demo rehearsal in a sub-transaction that is rolled back.
do $proof$
declare
  v_state jsonb; v_pol record; v_is30 boolean; v_golive boolean;
  v_kill int := -1; v_scale int := -1; v_held int := -1; v_reason text; v_median_ok boolean := false;
begin
  select trim(value) ~ '^30(\.0+)?$' into v_is30 from public.app_secrets where key = 'meta_daily_budget_cap_aed';
  if not coalesce(v_is30, false) then raise exception 'meta_daily_budget_cap_aed is not 30'; end if;
  select lower(trim(value)) = 'false' into v_golive from public.app_secrets where key = 'meta_autospend_golive';
  if not coalesce(v_golive, false) then raise exception 'meta_autospend_golive is no longer false - this file must not change it'; end if;
  v_state := public.fn_ads_autospend_state();
  if (v_state->>'cap_aed')::numeric <> 30 or (v_state->>'live_allowed')::boolean then
    raise exception 'fn_ads_autospend_state: cap_aed=% live_allowed=% reason=%', v_state->>'cap_aed', v_state->>'live_allowed', v_state->>'reason';
  end if;
  select * into v_pol from public.ad_spend_policy where policy_key = 'default';
  if v_pol.daily_cap_aed <> 30 or v_pol.target_cpl_aed is not null or v_pol.max_daily_per_campaign_aed > 30 then
    raise exception 'ad_spend_policy: daily_cap=% target_cpl=% max_per_campaign=%', v_pol.daily_cap_aed, v_pol.target_cpl_aed, v_pol.max_daily_per_campaign_aed;
  end if;
  -- the column itself carries no target: nullable, and no default a new row could inherit
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'ad_spend_policy' and column_name = 'target_cpl_aed'
                and (is_nullable <> 'YES' or column_default is not null)) then
    raise exception 'ad_spend_policy.target_cpl_aed still carries a NOT NULL or a column default: %',
      (select is_nullable || ' / ' || coalesce(column_default, 'NULL') from information_schema.columns
        where table_schema = 'public' and table_name = 'ad_spend_policy' and column_name = 'target_cpl_aed');
  end if;
  if exists (select 1 from public.app_secrets where key = 'meta_access_token') then
    raise notice 'a meta_access_token row exists now (header measured none on 6 Sep 2026); the decision record may be updated by hand';
  end if;
  if public.fn_ad_spend_daily_ceiling(true) <> 30 then raise exception 'demo ceiling is % not 30', public.fn_ad_spend_daily_ceiling(true); end if;
  if public.fn_ad_spend_daily_ceiling(false) <> 0 then raise exception 'live ceiling is % while go-live is false', public.fn_ad_spend_daily_ceiling(false); end if;

  -- REHEARSAL (demo arm, rolled back): three campaigns past learning with measured CPL 10, 20 and 90 AED and
  -- one with spend and no leads. Median of the measured set = 20; kill at 3 x 20 = 60 -> the 90 AED campaign
  -- and the no-lead campaign are paused, the 10 AED campaign scales, the 20 AED campaign scales (<= target).
  begin
    insert into public.ad_campaign_state (campaign_id, campaign_name, status, daily_budget_aed, started_at, is_demo, updated_at) values
      ('zz-demo-cpl-10', 'ZZ DEMO cpl 10', 'ACTIVE', 5, now() - interval '10 days', true, now()),
      ('zz-demo-cpl-20', 'ZZ DEMO cpl 20', 'ACTIVE', 5, now() - interval '10 days', true, now()),
      ('zz-demo-cpl-90', 'ZZ DEMO cpl 90', 'ACTIVE', 5, now() - interval '10 days', true, now()),
      ('zz-demo-noleads', 'ZZ DEMO no leads', 'ACTIVE', 5, now() - interval '10 days', true, now());
    insert into public.meta_insights (campaign_id, campaign_name, time_window, spend, results, synced_at, synced_via) values
      ('zz-demo-cpl-10', 'ZZ DEMO cpl 10', 'last_30d', 200, 20, now(), 'wf9d-proof'),
      ('zz-demo-cpl-20', 'ZZ DEMO cpl 20', 'last_30d', 200, 10, now(), 'wf9d-proof'),
      ('zz-demo-cpl-90', 'ZZ DEMO cpl 90', 'last_30d', 180, 2, now(), 'wf9d-proof'),
      ('zz-demo-noleads', 'ZZ DEMO no leads', 'last_30d', 150, 0, now(), 'wf9d-proof');
    perform public.fn_ads_manage(true, 'wf9d-proof');
    select count(*) filter (where rule_key = 'kill_3x'), count(*) filter (where rule_key = 'scale_winner')
      into v_kill, v_scale from public.ad_decision where run_tag = 'wf9d-proof';
    select reason into v_reason from public.ad_decision where run_tag = 'wf9d-proof' and campaign_id = 'zz-demo-cpl-90';
    v_median_ok := exists (select 1 from public.ad_decision where run_tag = 'wf9d-proof'
                            and (evidence->>'target_cpl')::numeric = 20 and evidence->>'target_source' like 'median measured%');
    raise exception 'wf9d_rollback';
  exception when others then
    if sqlerrm <> 'wf9d_rollback' then raise; end if;
  end;
  if v_kill <> 2 or v_scale <> 2 or not v_median_ok then
    raise exception 'derived-target rehearsal: kills=% scales=% median_target_20=% (reason for cpl-90: %)', v_kill, v_scale, v_median_ok, v_reason;
  end if;
  if exists (select 1 from public.ad_campaign_state where campaign_id like 'zz-demo-%') or exists (select 1 from public.ad_decision where run_tag = 'wf9d-proof') then
    raise exception 'the rehearsal left rows behind';
  end if;
  raise notice 'proof: meta_daily_budget_cap_aed=30 (read back as a boolean); meta_autospend_golive=false untouched; fn_ads_autospend_state cap_aed=% live_allowed=% (%); ad_spend_policy daily_cap=% target_cpl=NULL (column nullable, column_default NULL) max_per_campaign=%; demo ceiling 30, live ceiling 0; rehearsal (rolled back): kills=% scales=% target derived as the median 20 AED - "%"',
    v_state->>'cap_aed', v_state->>'live_allowed', v_state->>'reason', v_pol.daily_cap_aed, v_pol.max_daily_per_campaign_aed, v_kill, v_scale, v_reason;
end $proof$;

commit;
