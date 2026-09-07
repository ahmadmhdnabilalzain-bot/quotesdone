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

-- ROUTINE REMOVED 7 September 2026. public.fn_target_baseline was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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

-- ROUTINE REMOVED 7 September 2026. public.fn_target_feasibility was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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
