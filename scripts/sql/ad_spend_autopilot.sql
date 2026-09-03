-- AD SPEND AUTOPILOT — the deterministic paid-media manager (3 Sep 2026).
--
-- The founder's model for the company: he funds the Meta ad balance and keeps the subscriptions
-- running; the machine turns that balance into RFQs without him. Until today the top of the funnel
-- was the one link that still needed a human every time: meta_ads only ever CREATED paused objects,
-- boost_recommend asked the model whether to boost and then queued a proposal for the FOUNDER to fund,
-- and nothing paced spend against a ceiling. This file is the manager that runs that money on its own,
-- inside a ceiling the database itself enforces.
--
-- THREE OBJECTS AND ONE GUARD
--   ad_spend_policy     one row of knobs: the hard daily ceiling, the cost-per-lead the company will
--                       pay, the kill multiplier, the learning phase, the scaling step.
--   ad_campaign_state   what the manager believes is live on Meta (status, daily budget, adset). With
--                       a token, meta_sync keeps it honest; in the sandbox it is the truth.
--   ad_decision         the ledger. Every activate / pause / set_daily_budget the manager decides is a
--                       row here FIRST, with the rule that fired and the evidence it saw; the executor
--                       (meta_ads action=execute_decisions) carries out unexecuted rows and stamps how
--                       — live against graph.facebook.com when meta_access_token exists, sandbox when
--                       it does not. The ledger is the trace.
--   a00_ad_spend_ceiling_guard   BEFORE INSERT on ad_decision. It projects the sum of ACTIVE daily
--                       budgets after the decision and REFUSES the row if it would exceed the
--                       effective daily ceiling. Because the executor only ever executes ledger rows,
--                       no code path — this manager, a future one, a model, an operator — can put more
--                       money on Meta per day than the ceiling. The ceiling is enforced where every
--                       path has to go through, not in each path.
--
-- THE EFFECTIVE DAILY CEILING is the policy's daily cap, and when the founder has set a monthly cap,
-- the smaller of that and what is left of the month (monthly_cap_aed - month_spent_aed, spread over the
-- days remaining), so the month cannot be blown in a week even if every campaign is a winner.
-- month_spent_aed is what meta_sync writes back from the account once the token exists; the rehearsal
-- sets it inside an aborted transaction to prove the pacing arm.
--
-- THE RULES, in the order they are applied per tick (first match per campaign wins):
--   pace_down / pace_pause   the active set already exceeds the ceiling (the ceiling moved, e.g. the
--                            month is nearly spent): shrink every active budget proportionally, floor
--                            at the per-campaign minimum, and if even the minimums do not fit, pause
--                            the worst cost-per-lead until they do.
--   tracking_gate            an active campaign has spent past the learning threshold and reports NO
--                            results field at all: conversions are not being tracked, so nothing can
--                            be judged. Pause it — spending blind is the one thing this manager never
--                            does.
--   kill_3x                  past the learning phase (both the days AND the spend threshold), the
--                            cost per lead is above kill_multiplier x target, or there is spend and no
--                            leads at all. Pause.
--   (learning)               inside the learning phase: no decision. A campaign is not judged on its
--                            first days.
--   scale_winner             past learning, cost per lead at or under target, budget below the
--                            per-campaign maximum and there is headroom under the ceiling: raise the
--                            daily budget by scale_step_pct (capped by both).
--   activate                 a PAUSED campaign that has never run (started_at is null), carries a
--                            budget, and fits under the ceiling: switch it on. This is the arm that
--                            makes the funnel autonomous; auto_activate=false turns it off.
--
-- SCOPE. fn_ads_manage(p_demo) manages ONLY demo rows when true and ONLY real rows when false, so the
-- sandbox rehearsal can run on the production database without touching a real campaign, and the
-- daily tick can never touch a fixture. A campaign with an unexecuted decision is skipped until the
-- executor has carried it out, so two ticks cannot double-decide.
--
-- WHAT THIS DOES NOT DO (deliberately): it does not create campaigns or creatives (meta_ads
-- quick_campaign + the content pipeline do; created objects arrive PAUSED and this manager activates
-- them), and it does not read the Meta account itself — meta_sync mirrors campaigns, ad-set budgets
-- and month spend into these tables once the founder mints the token. The token is the only switch.

create table if not exists public.ad_spend_policy (
  policy_key                 text primary key default 'default',
  daily_cap_aed              numeric not null default 200 check (daily_cap_aed >= 0),
  target_cpl_aed             numeric not null default 150 check (target_cpl_aed > 0),
  kill_multiplier            numeric not null default 3 check (kill_multiplier >= 1),
  learning_phase_days        integer not null default 3 check (learning_phase_days >= 0),
  learning_min_spend_aed     numeric not null default 100 check (learning_min_spend_aed >= 0),
  scale_step_pct             numeric not null default 20 check (scale_step_pct >= 0),
  max_daily_per_campaign_aed numeric not null default 100 check (max_daily_per_campaign_aed > 0),
  min_daily_per_campaign_aed numeric not null default 20 check (min_daily_per_campaign_aed > 0),
  auto_activate              boolean not null default true,
  updated_at                 timestamptz not null default now(),
  check (min_daily_per_campaign_aed <= max_daily_per_campaign_aed)
);
-- The MONTH. monthly_cap_aed is the founder's ceiling for the month (null = the daily cap alone);
-- month_spent_aed is what has gone out so far — meta_sync writes it back from the account once the
-- token exists, and it resets with the month. It is deliberately NOT department_budget('growth'):
-- that row is the department's OPERATING budget for model spend (AED 120/month with degrade/halt
-- thresholds), a different pool of money from the founder-funded ad balance.
alter table public.ad_spend_policy add column if not exists monthly_cap_aed numeric check (monthly_cap_aed is null or monthly_cap_aed >= 0);
alter table public.ad_spend_policy add column if not exists month_spent_aed numeric not null default 0 check (month_spent_aed >= 0);
alter table public.ad_spend_policy add column if not exists month_label text not null default to_char(now(), 'YYYY-MM');
alter table public.ad_spend_policy drop column if exists budget_dept_key;
alter table public.ad_spend_policy enable row level security;
insert into public.ad_spend_policy (policy_key) values ('default') on conflict (policy_key) do nothing;

create table if not exists public.ad_campaign_state (
  campaign_id      text primary key,
  campaign_name    text,
  adset_id         text,
  status           text not null default 'PAUSED' check (status in ('ACTIVE', 'PAUSED')),
  daily_budget_aed numeric not null default 0 check (daily_budget_aed >= 0),
  started_at       timestamptz,
  is_demo          boolean not null default false,
  updated_at       timestamptz not null default now()
);
alter table public.ad_campaign_state enable row level security;

create table if not exists public.ad_decision (
  id             bigint generated always as identity primary key,
  decided_at     timestamptz not null default now(),
  campaign_id    text not null references public.ad_campaign_state(campaign_id) on delete cascade,
  action         text not null check (action in ('activate', 'pause', 'set_daily_budget')),
  amount_aed     numeric check (amount_aed is null or amount_aed >= 0),
  rule_key       text not null,
  reason         text not null,
  evidence       jsonb not null default '{}'::jsonb,
  executed_at    timestamptz,
  execution_mode text check (execution_mode is null or execution_mode in ('sandbox', 'live')),
  api_response   jsonb,
  run_tag        text,
  check ((action = 'set_daily_budget') = (amount_aed is not null))
);
alter table public.ad_decision enable row level security;
create index if not exists ad_decision_unexecuted_idx on public.ad_decision (id) where executed_at is null;

-- The effective daily ceiling: the policy's daily cap, and when a monthly cap is set, what is left
-- of the month spread over the days remaining (a month_spent figure from an earlier month counts as
-- zero). No monthly cap = the daily cap alone.
create or replace function public.fn_ad_spend_daily_ceiling()
returns numeric
language sql
stable
set search_path to 'public'
as $$
  -- NOTE the explicit null branch: greatest()/least() IGNORE nulls in Postgres, so
  -- greatest(0, null - x) is 0, not null, and the first cut of this function paced every
  -- campaign to zero whenever no monthly cap was set.
  select case
    when p.monthly_cap_aed is null then p.daily_cap_aed
    else least(
      p.daily_cap_aed,
      greatest(0, p.monthly_cap_aed - case when p.month_label = to_char(now(), 'YYYY-MM') then p.month_spent_aed else 0 end)
        / greatest(1, (date_trunc('month', now()) + interval '1 month')::date - current_date))
  end
  from public.ad_spend_policy p
  where p.policy_key = 'default';
$$;

-- THE GUARD. Projects the active daily total after this row and refuses anything over the ceiling.
-- Demo and real campaigns are projected separately: a fixture cannot eat the real ceiling, and a real
-- campaign cannot be refused because a rehearsal is running.
create or replace function public.fn_ad_spend_ceiling_guard()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  s        public.ad_campaign_state%rowtype;
  p        public.ad_spend_policy%rowtype;
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

  v_ceiling := public.fn_ad_spend_daily_ceiling();
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

drop trigger if exists a00_ad_spend_ceiling_guard on public.ad_decision;
create trigger a00_ad_spend_ceiling_guard
  before insert on public.ad_decision
  for each row execute function public.fn_ad_spend_ceiling_guard();

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
  select * into p from public.ad_spend_policy where policy_key = 'default';
  v_ceiling := public.fn_ad_spend_daily_ceiling();

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
        from public.meta_insights i where i.campaign_id = s.campaign_id order by i.synced_at desc limit 1
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
        from public.meta_insights i where i.campaign_id = s.campaign_id order by i.synced_at desc limit 1
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
  for c in
    select s.*, m.spend, m.results, m.has_results_field
    from public.ad_campaign_state s
    left join lateral (
      select i.spend, i.results, (i.results is not null) as has_results_field
      from public.meta_insights i where i.campaign_id = s.campaign_id order by i.synced_at desc limit 1
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
      continue;  -- not judged on its first days
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

-- The executor's bookkeeping: apply an executed decision to the manager's picture of Meta.
create or replace function public.fn_ad_decision_mark_executed(p_id bigint, p_mode text, p_response jsonb default '{}'::jsonb)
returns void
language plpgsql
set search_path to 'public'
as $$
declare d public.ad_decision%rowtype;
begin
  select * into d from public.ad_decision where id = p_id for update;
  if not found then raise exception 'ad_decision % does not exist', p_id; end if;
  if d.executed_at is not null then return; end if;
  update public.ad_decision set executed_at = now(), execution_mode = p_mode, api_response = p_response where id = p_id;
  update public.ad_campaign_state set
    status = case d.action when 'activate' then 'ACTIVE' when 'pause' then 'PAUSED' else status end,
    daily_budget_aed = case d.action when 'set_daily_budget' then d.amount_aed else daily_budget_aed end,
    started_at = case when d.action = 'activate' then coalesce(started_at, now()) else started_at end,
    updated_at = now()
  where campaign_id = d.campaign_id;
end;
$$;

-- The ledger carries a raising trigger, which makes it an ENFORCING table in the kernel's eyes
-- (fn_kernel_truncate_protection_state): a truncate would erase the trace behind every budget move,
-- so it gets the same guard as every other enforcing table and no role may truncate it.
revoke truncate on public.ad_decision from public, anon, authenticated, service_role;
drop trigger if exists z00_kernel_truncate_guard on public.ad_decision;
create trigger z00_kernel_truncate_guard before truncate on public.ad_decision
  for each statement execute function public.fn_kernel_truncate_guard();
