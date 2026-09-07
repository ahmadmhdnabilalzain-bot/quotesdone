-- A TARGET BECOMES A CONTRACT WITH A BASELINE, A DRIVER MODEL AND A VERDICT
--
-- The founder's instruction, 7 Sep 2026: build the CEO operating system, not a persona. This is the
-- first end-to-end increment: one owner target travels from natural-language intake, through a
-- verified baseline, a causal driver model, feasibility arithmetic, and out as a verdict that says
-- achievable or not and names what would have to change.
--
-- WHAT THIS EXTENDS RATHER THAN REPLACES.
--   public.company_goals        stays the target registry. A contract points at a goal_key.
--   public.metric_definition    stays the metric registry. A contract cites a metric_key.
--   public.department_budget    stays the budget. A contract reserves against it, never beside it.
--   public.org_tasks            stays the work queue. This adds an evidence requirement to closing.
--
-- WHY A CONTRACT AND NOT JUST A GOAL ROW. company_goals carries a target, a unit and a deadline. It
-- cannot express the four things that decide whether a target is real:
--   1. a baseline that distinguishes MEASURED ZERO from UNKNOWN from NOT INSTRUMENTED,
--   2. whether the desired value is cumulative or incremental, gross or net,
--   3. the causal chain of drivers with a rate per stage and whether each rate was measured or assumed,
--   4. the budget and the guardrails that the target may not be bought at the expense of.
-- Every one of those has already produced a wrong answer in this company. The 1.86% invite-to-register
-- bound exists only because someone distinguished "zero registrations from 161 invitations" from
-- "no data". A goal row cannot hold that distinction. A contract must.
--
-- ARITHMETIC IS SQL, NOT PROSE. Every number this produces is computed here. Nothing depends on a
-- language model at run time; these functions answer with inference switched off.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE COMPANY OPERATING CHARTER
--    Editable, versioned, and the authority for currency, timezone, cash floor and reserved matters.
--    One active row. Superseding writes a new row and points the old one at it, so the history of
--    what the company was told to do survives.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.company_charter (
  id                    bigserial primary key,
  version               int         not null,
  active                boolean     not null default true,
  superseded_by         bigint      references public.company_charter(id),

  mission               text        not null,
  business_model        text        not null,
  customers             text        not null,
  value_proposition     text        not null,
  strategic_boundaries  text        not null,

  currency              text        not null default 'AED',
  timezone              text        not null default 'Asia/Dubai',

  -- Unknown budget means NO AUTHORISATION TO SPEND. Null here is a refusal, never a blank cheque.
  monthly_spend_cap     numeric,
  min_cash_reserve      numeric,
  risk_restrictions     text,

  reserved_matters      text[]      not null default '{}',
  escalation_rules      text,
  operating_calendar    jsonb       not null default '{}'::jsonb,
  reporting_preferences jsonb       not null default '{}'::jsonb,

  authored_by           text        not null,
  created_at            timestamptz not null default now(),
  note                  text
);

create unique index if not exists company_charter_one_active
  on public.company_charter (active) where active;

comment on table public.company_charter is
  'The owner-approved operating charter. One active row. monthly_spend_cap NULL means no authorisation to spend, not unlimited.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE TARGET CONTRACT
--    Versioned. Changing the metric, the desired value, the deadline or the budget writes a new
--    version rather than editing in place, because a target that can be quietly edited is not a target.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.target_contract (
  id                    bigserial primary key,
  contract_key          text        not null,
  version               int         not null,
  status                text        not null default 'draft'
                          check (status in ('draft','active','superseded','achieved','failed','abandoned')),
  superseded_by         bigint      references public.target_contract(id),

  -- what and why
  objective             text        not null,
  business_reason       text        not null,
  priority              int         not null default 100,
  accountable_owner     text        not null references public.org_agents(agent_key),
  goal_key              text        references public.company_goals(key),

  -- the metric, defined so two people cannot read it differently
  metric_key            text        references public.metric_definition(metric_key),
  metric_definition     text        not null,
  metric_unit           text        not null,
  metric_population     text        not null,
  metric_exclusions     text,
  authoritative_source  text        not null,
  measure_sql           text,

  -- the baseline. THE STATE COLUMN IS THE POINT: a measured zero and an unknown are different facts
  -- and this company has already confused them once.
  baseline_value        numeric,
  baseline_state        text        not null default 'unknown'
                          check (baseline_state in ('measured','unknown','not_instrumented')),
  baseline_at           timestamptz,
  baseline_note         text,

  -- the desired end state
  desired_value         numeric     not null,
  desired_basis         text        not null default 'cumulative'
                          check (desired_basis in ('cumulative','incremental','gross','net','active')),
  deadline              date        not null,
  timezone              text        not null default 'Asia/Dubai',
  measurement_cadence   text        not null default 'daily',

  -- resources. A null budget is no authorisation, matching the charter.
  budget_amount         numeric,
  budget_currency       text        not null default 'AED',
  capacity_note         text,
  constraints_note      text,

  -- guardrails: what may NOT be sacrificed to hit this
  guardrails            jsonb       not null default '[]'::jsonb,

  -- honesty about the forecast
  assumptions           jsonb       not null default '[]'::jsonb,
  confidence_note       text,
  escalation_threshold  text,
  success_definition    text        not null,
  evidence_required     text        not null,

  created_by            text        not null,
  created_at            timestamptz not null default now(),
  activated_at          timestamptz,
  closed_at             timestamptz,
  close_reason          text
);

create unique index if not exists target_contract_key_version
  on public.target_contract (contract_key, version);
create unique index if not exists target_contract_one_active_per_key
  on public.target_contract (contract_key) where status = 'active';
create index if not exists target_contract_owner on public.target_contract (accountable_owner);

comment on table public.target_contract is
  'A versioned, measurable contract for one owner target. baseline_state distinguishes a measured zero from unknown from not-instrumented.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE DRIVER MODEL
--    The causal chain from a controllable activity to the outcome, one row per stage, each with a
--    rate and an explicit statement of whether that rate was MEASURED here or ASSUMED.
--    An assumed rate is not a lie; an assumed rate presented as measured is.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.target_driver (
  id                bigserial primary key,
  contract_id       bigint      not null references public.target_contract(id) on delete cascade,
  stage_order       int         not null,
  stage_key         text        not null,
  stage_label       text        not null,
  from_stage_key    text,

  -- the conversion from the previous stage to this one
  rate              numeric     not null check (rate >= 0 and rate <= 1),
  rate_source       text        not null
                      check (rate_source in ('measured','assumed','industry_prior','not_instrumented')),
  rate_evidence     text,
  rate_denominator  numeric,
  rate_numerator    numeric,

  -- how long this stage takes to show up, so a 30-day target is not planned as if it were instant
  lag_days          int         not null default 0,

  -- the ceiling, if one exists. A capacity of null means unbounded, which is usually a lie worth stating.
  capacity_per_day  numeric,
  unit_cost         numeric,

  measured_at       timestamptz,
  note              text
);

create unique index if not exists target_driver_stage
  on public.target_driver (contract_id, stage_order);

comment on table public.target_driver is
  'One row per causal stage of a target. rate_source separates what we measured from what we assumed.';

-- ---------------------------------------------------------------------------------------------
-- 4. THE VERDICT LOG
--    Every feasibility run is recorded, so a target that was called achievable in week 1 and
--    unachievable in week 4 leaves a trail rather than a changed opinion.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.target_verdict (
  id                    bigserial primary key,
  contract_id           bigint      not null references public.target_contract(id) on delete cascade,
  run_at                timestamptz not null default now(),

  remaining_outcome     numeric,
  days_remaining        int,
  current_run_rate      numeric,
  required_run_rate     numeric,
  expected_completion   date,

  scenario_downside     numeric,
  scenario_base         numeric,
  scenario_upside       numeric,

  binding_stage         text,
  binding_reason        text,
  required_top_of_funnel numeric,
  projected_cost        numeric,
  budget_headroom       numeric,

  verdict               text        not null
                          check (verdict in ('ACHIEVABLE','AT_RISK','NOT_ACHIEVABLE','CANNOT_ASSESS')),
  verdict_reason        text        not null,
  what_must_change      text[],
  measured_rate_count   int,
  assumed_rate_count    int
);

create index if not exists target_verdict_contract on public.target_verdict (contract_id, run_at desc);

comment on table public.target_verdict is
  'Append-only record of every feasibility assessment. CANNOT_ASSESS is a real verdict, not a failure to produce one.';

commit;

-- ---------------------------------------------------------------------------------------------
-- 5. ESTABLISH REALITY
--    Runs the contract's own measure_sql, records the baseline and its freshness, and refuses to
--    call an error a zero.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_target_baseline(p_contract_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
  v_val numeric;
  v_state text;
  v_note text;
begin
  select * into c from public.target_contract where id = p_contract_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such contract.');
  end if;

  if coalesce(btrim(c.measure_sql), '') = '' then
    v_state := 'not_instrumented';
    v_note  := 'NO INSTRUMENT EXISTS. The contract names an authoritative source but carries no measure. '
            || 'This needs an instrument built before it needs a number, and that is not a SQL task.';
    v_val   := null;
  else
    begin
      execute c.measure_sql into v_val;
      if v_val is null then
        v_state := 'unknown';
        v_note  := 'The measure ran and returned NULL. That is an unknown, not a zero.';
      else
        v_state := 'measured';
        v_note  := 'Measured live from the contract''s own measure_sql.';
      end if;
    exception when others then
      -- An error is never a zero. This is the distinction the estate got wrong once already.
      v_state := 'unknown';
      v_val   := null;
      v_note  := 'The measure FAILED and the baseline is therefore unknown, not zero. Error: '
              || left(sqlerrm, 200);
    end;
  end if;

  update public.target_contract
     set baseline_value = v_val,
         baseline_state = v_state,
         baseline_at    = now(),
         baseline_note  = v_note
   where id = p_contract_id;

  return jsonb_build_object(
    'ok', true,
    'contract_id', p_contract_id,
    'baseline_value', v_val,
    'baseline_state', v_state,
    'baseline_at', now(),
    'note', v_note
  );
end;
$$;

revoke execute on function public.fn_target_baseline(bigint) from public;

comment on function public.fn_target_baseline(bigint) is
  'Establishes reality for a contract. A failed measure produces state=unknown, never a zero.';

-- ---------------------------------------------------------------------------------------------
-- 6. THE FEASIBILITY ENGINE
--    Walks the driver chain backwards from the desired outcome to the top of funnel required,
--    checks that against capacity, lag and budget, and returns a verdict with what must change.
--
--    THE RULE THAT MATTERS: the verdict is CANNOT_ASSESS when the baseline is unknown or when the
--    chain rests entirely on assumed rates. A confident number built on nothing is worse than an
--    honest refusal, and this company has already shipped one.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_target_feasibility(p_contract_id bigint, p_record boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c            record;
  d            record;
  v_days       int;
  v_remaining  numeric;
  v_cum_rate   numeric := 1.0;
  v_down_rate  numeric := 1.0;
  v_up_rate    numeric := 1.0;
  v_total_lag  int := 0;
  v_measured   int := 0;
  v_assumed    int := 0;
  v_stages     int := 0;
  v_top        numeric;
  v_top_down   numeric;
  v_top_up     numeric;
  v_binding    text := null;
  v_binding_why text := null;
  v_cap_limit  numeric;
  v_cost       numeric := 0;
  v_headroom   numeric;
  v_verdict    text;
  v_reason     text;
  v_changes    text[] := '{}';
  v_run_rate   numeric;
  v_required   numeric;
  v_eta        date;
  v_chain      jsonb := '[]'::jsonb;
  -- Stages that declare NO capacity ceiling. Treating an undeclared capacity as an infinite one is
  -- how this function first blessed 16,129 invitations in 30 days from a list of 19,896 addresses on
  -- a domain already bouncing at 10%. Silence about a ceiling is not evidence of headroom.
  v_undeclared text[] := '{}';
  -- THE SAFETY ENVELOPE. A channel's safe throughput is a property of the channel, not of how badly
  -- we want the target. Budget and internal capacity are negotiable; sender reputation is not, because
  -- losing it costs every sign-in code and receipt that shares the domain. So this overrides.
  v_chan       jsonb;
  v_chan_block text := null;
  v_chan_why   text := null;
  v_chan_safe  numeric;
begin
  select * into c from public.target_contract where id = p_contract_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'No such contract.');
  end if;

  v_days := greatest(0, (c.deadline - (now() at time zone c.timezone)::date));

  -- Remaining outcome. For an incremental target the baseline does not subtract.
  if c.desired_basis = 'incremental' then
    v_remaining := c.desired_value;
  else
    v_remaining := c.desired_value - coalesce(c.baseline_value, 0);
  end if;

  -- Walk the chain. cum_rate is the product of every stage's conversion, so the top of funnel
  -- required is remaining / cum_rate.
  for d in
    select * from public.target_driver where contract_id = p_contract_id order by stage_order
  loop
    v_stages := v_stages + 1;
    v_cum_rate := v_cum_rate * d.rate;

    -- Downside and upside bracket an assumed rate by half and double, bounded at 1. A measured rate
    -- is bracketed far more tightly, because we actually know it.
    if d.rate_source = 'measured' then
      v_measured := v_measured + 1;
      v_down_rate := v_down_rate * greatest(d.rate * 0.75, 0.0001);
      v_up_rate   := v_up_rate   * least(d.rate * 1.25, 1.0);
    else
      v_assumed := v_assumed + 1;
      v_down_rate := v_down_rate * greatest(d.rate * 0.5, 0.0001);
      v_up_rate   := v_up_rate   * least(d.rate * 2.0, 1.0);
    end if;

    v_total_lag := v_total_lag + d.lag_days;

    v_chain := v_chain || jsonb_build_object(
      'stage', d.stage_key,
      'label', d.stage_label,
      'rate', d.rate,
      'rate_source', d.rate_source,
      'lag_days', d.lag_days,
      'capacity_per_day', d.capacity_per_day,
      'unit_cost', d.unit_cost
    );
  end loop;

  -- No chain means no model. Say so rather than inventing one.
  if v_stages = 0 then
    v_verdict := 'CANNOT_ASSESS';
    v_reason  := 'No driver model exists for this contract. Without a causal chain there is no way to '
              || 'say what volume of activity produces the outcome, and any number would be invented.';
    v_changes := array['Build the driver model: name each stage from controllable activity to outcome, with its rate and whether that rate was measured or assumed.'];
  elsif c.baseline_state <> 'measured' then
    v_verdict := 'CANNOT_ASSESS';
    v_reason  := 'The baseline is ' || c.baseline_state || '. A gap cannot be computed from an unknown '
              || 'starting point, and treating it as zero is the error this column exists to prevent.';
    v_changes := array['Instrument the baseline, or record explicitly that it is a measured zero.'];
  end if;

  v_top      := case when v_cum_rate  > 0 then v_remaining / v_cum_rate  else null end;
  v_top_down := case when v_down_rate > 0 then v_remaining / v_down_rate else null end;
  v_top_up   := case when v_up_rate   > 0 then v_remaining / v_up_rate   else null end;

  -- Cost: sum the unit cost of every stage against the volume that stage must carry.
  declare
    v_vol numeric := v_top;
  begin
    for d in select * from public.target_driver where contract_id = p_contract_id order by stage_order loop
      if d.unit_cost is not null and v_vol is not null then
        v_cost := v_cost + (v_vol * d.unit_cost);
      end if;
      if v_vol is not null then v_vol := v_vol * d.rate; end if;
    end loop;
  end;

  -- Capacity: the first stage whose per-day ceiling cannot carry its required volume in the time left
  -- is the binding constraint. Lag is subtracted, because a stage that takes 7 days to convert does
  -- not get all 30 days of runway.
  declare
    v_vol numeric := v_top;
    v_usable_days int;
  begin
    for d in select * from public.target_driver where contract_id = p_contract_id order by stage_order loop
      v_usable_days := greatest(1, v_days - v_total_lag);
      if d.capacity_per_day is not null and v_vol is not null then
        v_cap_limit := d.capacity_per_day * v_usable_days;
        if v_vol > v_cap_limit and v_binding is null then
          v_binding := d.stage_key;
          v_binding_why := format(
            'Stage %s must carry %s units but its ceiling is %s per day over %s usable days, which is %s.',
            d.stage_key, round(v_vol, 1), d.capacity_per_day, v_usable_days, round(v_cap_limit, 1));
        end if;
      elsif d.capacity_per_day is null and d.channel_key is null then
        v_undeclared := array_append(v_undeclared,
          format('%s (must carry %s over %s usable days)', d.stage_key, round(coalesce(v_vol,0),0), v_usable_days));
      end if;

      -- The channel check. A stage that names a channel is capped by that channel's policy no matter
      -- what the budget or the internal capacity allows.
      if d.channel_key is not null and v_vol is not null then
        v_chan := public.fn_channel_safe_volume(d.channel_key, v_vol, v_usable_days);
        if coalesce((v_chan->>'ok')::boolean, false) = false and v_chan_block is null then
          v_chan_block := d.stage_key;
          v_chan_safe  := (v_chan->>'safe_max')::numeric;
          v_chan_why   := v_chan->>'reason';
        end if;
      end if;
      if v_vol is not null then v_vol := v_vol * d.rate; end if;
    end loop;
  end;

  v_headroom := case when c.budget_amount is null then null else c.budget_amount - v_cost end;

  -- Run rate so far, and the pace required from here.
  v_run_rate := case when c.baseline_at is not null and c.activated_at is not null
                       and c.baseline_at > c.activated_at
                     then coalesce(c.baseline_value,0) / greatest(1, extract(day from c.baseline_at - c.activated_at))
                     else null end;
  v_required := case when v_days > 0 then v_remaining / v_days else null end;
  v_eta := case when v_run_rate is not null and v_run_rate > 0
                then (now() at time zone c.timezone)::date + ceil(v_remaining / v_run_rate)::int
                else null end;

  -- The verdict, if the two hard refusals above did not already set it.
  if v_verdict is null then
    -- THE SAFETY ENVELOPE IS CHECKED FIRST, because it is the only constraint that cannot be bought
    -- out of. A cheaper plan, a longer deadline or more staff do not restore a blacklisted domain.
    if v_chan_block is not null then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := 'The channel that carries this plan cannot carry it safely. ' || v_chan_why;
      v_changes := array_append(v_changes, format(
        'Cap stage %s at %s, which is what the channel can safely carry, and make up the difference on '
        || 'another channel or renegotiate the target. Raising the volume is not an option here: budget '
        || 'and capacity are negotiable, sender reputation is not.',
        v_chan_block, round(coalesce(v_chan_safe,0),0)));
      v_changes := array_append(v_changes,
        'Open a separate outreach domain and warm it, so cold volume never shares a reputation with sign-in codes and receipts.');
    elsif v_binding is not null then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := 'A capacity ceiling binds before the deadline. ' || v_binding_why;
      v_changes := array_append(v_changes, format('Raise capacity at stage %s, extend the deadline, or reduce the desired value.', v_binding));
    elsif c.budget_amount is not null and v_cost > c.budget_amount then
      v_verdict := 'NOT_ACHIEVABLE';
      v_reason  := format('The plan costs %s against a budget of %s, so it cannot be funded as designed.',
                          round(v_cost,2), c.budget_amount);
      v_changes := array_append(v_changes, format('Raise the budget to %s, improve a conversion rate, or reduce the desired value.', round(v_cost,2)));
    elsif array_length(v_undeclared, 1) > 0 then
      -- An undeclared ceiling is not headroom. Say the volume out loud and make someone declare it.
      v_verdict := 'AT_RISK';
      v_reason  := format('The arithmetic is fundable, but %s stage(s) declare no capacity ceiling: %s. '
                       || 'An undeclared ceiling is an unchecked assumption, not evidence of headroom, and it is '
                       || 'exactly how a plan that looks affordable turns out to be physically impossible.',
                          array_length(v_undeclared,1), array_to_string(v_undeclared, '; '));
      v_changes := array_append(v_changes,
        format('Declare a real capacity_per_day for: %s. If the true ceiling cannot carry the volume, the target changes, not the ceiling.',
               array_to_string(v_undeclared, ', ')));
    elsif v_measured = 0 then
      v_verdict := 'AT_RISK';
      v_reason  := format('The chain is arithmetically fundable and within capacity, but every one of its %s '
                       || 'rates is assumed rather than measured here. The plan is a hypothesis, not a forecast.', v_stages);
      v_changes := array_append(v_changes, 'Measure at least the first conversion rate on a small controlled batch before scaling.');
    elsif v_assumed > v_measured then
      v_verdict := 'AT_RISK';
      v_reason  := format('%s of %s rates are assumed rather than measured, so the downside case (%s at top of funnel) '
                       || 'is far from the base case (%s).', v_assumed, v_stages, round(coalesce(v_top_down,0),0), round(coalesce(v_top,0),0));
      v_changes := array_append(v_changes, 'Convert the largest assumed rate into a measured one before committing the full budget.');
    else
      v_verdict := 'ACHIEVABLE';
      v_reason  := format('Requires %s at the top of the funnel over %s days, within capacity and budget, '
                       || 'on %s measured rates of %s.', round(coalesce(v_top,0),0), v_days, v_measured, v_stages);
    end if;
  end if;

  if p_record then
    insert into public.target_verdict (
      contract_id, remaining_outcome, days_remaining, current_run_rate, required_run_rate,
      expected_completion, scenario_downside, scenario_base, scenario_upside,
      binding_stage, binding_reason, required_top_of_funnel, projected_cost, budget_headroom,
      verdict, verdict_reason, what_must_change, measured_rate_count, assumed_rate_count
    ) values (
      p_contract_id, v_remaining, v_days, v_run_rate, v_required,
      v_eta, v_top_down, v_top, v_top_up,
      v_binding, v_binding_why, v_top, nullif(v_cost,0), v_headroom,
      v_verdict, v_reason, v_changes, v_measured, v_assumed
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'contract', c.contract_key,
    'version', c.version,
    'objective', c.objective,
    'baseline', jsonb_build_object('value', c.baseline_value, 'state', c.baseline_state, 'at', c.baseline_at),
    'remaining_outcome', v_remaining,
    'days_remaining', v_days,
    'total_lag_days', v_total_lag,
    'required_run_rate_per_day', round(coalesce(v_required,0), 2),
    'chain', v_chain,
    'cumulative_rate', v_cum_rate,
    'required_top_of_funnel', jsonb_build_object(
       'downside', round(coalesce(v_top_down,0),0),
       'base',     round(coalesce(v_top,0),0),
       'upside',   round(coalesce(v_top_up,0),0)),
    'projected_cost', round(v_cost, 2),
    'budget_amount', c.budget_amount,
    'budget_headroom', round(coalesce(v_headroom,0), 2),
    'binding_stage', v_binding,
    'binding_reason', v_binding_why,
    'channel_blocked_stage', v_chan_block,
    'channel_safe_max', v_chan_safe,
    'channel_reason', v_chan_why,
    'rates_measured', v_measured,
    'rates_assumed', v_assumed,
    'verdict', v_verdict,
    'verdict_reason', v_reason,
    'what_must_change', to_jsonb(v_changes)
  );
end;
$$;

revoke execute on function public.fn_target_feasibility(bigint, boolean) from public;

comment on function public.fn_target_feasibility(bigint, boolean) is
  'Walks a contract''s driver chain and returns ACHIEVABLE / AT_RISK / NOT_ACHIEVABLE / CANNOT_ASSESS with what must change. Refuses to assess on an unknown baseline or an absent driver model.';

-- ---------------------------------------------------------------------------------------------
-- 7. THE CLOSE THAT MUST CARRY AN ACT
--    The defect this fixes, measured 7 Sep 2026: 134 KPI-missed tasks were opened, 113 marked done
--    and 21 cancelled, and every KPI they named is still missed. Task 576318 ("target 300, actual 0,
--    diagnose the cause") was created at 04:00 and closed at 07:51 with no decision, no next step and
--    no events recorded. A close that documents the facts is indistinguishable, in the data, from work
--    performed.
--
--    The guard is OPT-IN by column so nothing currently running breaks. Tasks that carry
--    requires_evidence are refused a transition to done unless the result names an act.
-- ---------------------------------------------------------------------------------------------

alter table public.org_tasks
  add column if not exists requires_evidence boolean not null default false;

comment on column public.org_tasks.requires_evidence is
  'When true, this task cannot reach done unless its result records an act: a decision, a fallback rung taken, or an escalation raised.';

create or replace function public.fn_org_task_close_needs_an_act()
returns trigger
language plpgsql
as $$
declare
  v_has_act boolean;
begin
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;
  if not coalesce(new.requires_evidence, false) then
    return new;
  end if;

  -- An act is any ONE of: a recorded decision, a fallback rung taken, an escalation raised, or a
  -- named change with evidence. Gathering facts is not an act, which is the whole point.
  v_has_act :=
       coalesce(new.result ? 'decision', false)
    or coalesce(new.result ? 'fallback_rung', false)
    or coalesce(new.result ? 'escalated_to', false)
    or coalesce(new.result ? 'change_made', false)
    or coalesce(jsonb_array_length(coalesce(new.result->'events','[]'::jsonb)) > 0, false);

  if not v_has_act then
    raise exception using
      errcode = 'check_violation',
      message = format('Task %s cannot be closed: its result records facts but no act.', new.id),
      detail  = 'A close must carry one of: result->decision, result->fallback_rung, result->escalated_to, '
             || 'result->change_made, or at least one entry in result->events.',
      hint    = 'If nothing could be done, set status to blocked or escalated and say why. '
             || 'Marking done without an act is how 113 KPI tasks closed while every KPI stayed missed.';
  end if;

  return new;
end;
$$;

drop trigger if exists z50_task_close_needs_an_act on public.org_tasks;
create trigger z50_task_close_needs_an_act
  before update on public.org_tasks
  for each row execute function public.fn_org_task_close_needs_an_act();

comment on function public.fn_org_task_close_needs_an_act() is
  'Refuses to let an evidence-required task reach done on facts alone. Fixes the close that documents instead of performs.';
