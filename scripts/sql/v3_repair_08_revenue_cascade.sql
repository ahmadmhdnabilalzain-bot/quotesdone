-- V3 REMEDIATION — STAGE 8: REVENUE OBJECTIVE AND KPI CASCADE
--
-- CMP-BZ-01 scored 14.76%: a decision almost never resolved to the department objective AND the
-- company revenue target. The handoff calls this a knowledge-and-prompt gap. It is not only that.
-- Measured on staging (pglpqrhvozwepymcuunn) on 14 Aug 2026, before anything in this file ran:
--
--   department_objective:  66 active rows, 37 carrying a goal_key,
--                          0 carrying a target_value, 0 carrying a measure_sql, 0 measured.
--
-- Every department objective in this database was a SENTENCE. Not one of them carried the number
-- it was supposed to move, so there was nothing for a role KPI to reconcile to and nothing for an
-- answer to cite. An agent asked to link its decision to the department objective could only
-- restate prose.
--
-- WHY. `fn_goal_decompose()` — the routine that hands a company goal's target and measure down to
-- the owning department — already existed and HAS NEVER RUN. Probed in an aborted transaction
-- before this file was written:
--
--   do $$ declare r jsonb; c int; begin
--     r := fn_goal_decompose();
--     select count(*) filter (where target_value is not null) into c from department_objective;
--     raise exception 'PROBE %  with_target=%', r, c; end $$;
--   -> ERROR: PROBE {"created":25,"adopted":6,...}  after_with_target=30   (rolled back)
--
-- 25 objectives it would create, 6 it would repair, 30 targets it would land — from zero. A
-- finished capability with no entry point, and the largest business-value gap in the certification
-- sat downstream of it. This file gives it one, and then builds the readable chain above it.
--
-- WHAT THIS FILE ADDS
--   company objective + deadline  ->  fn_revenue_trajectory()   where we are vs where we must be
--   -> department objective       ->  fn_revenue_cascade(dept[, role])
--   -> role KPI                   ->  same call, classified by fn_metric_class()
--   -> task expected effect       ->  task_commercial_effect + fn_task_commercial_effect()
--   -> measured result            ->  same table, measured_outcome_value
--   -> management response        ->  v_commercial_effect_due + fn_binding_constraint()
--
-- TWO RULES THIS FILE OBEYS, BOTH LEARNED HERE THE EXPENSIVE WAY
--   1. NO least()/greatest() ANYWHERE. least(100, NULL) = 100 once scored 56 unmeasured company
--      goals as perfect and put 97.7% attainment in the founder's email on a zero-revenue day.
--      Nothing below combines an attainment across items. Unmeasured is reported as
--      "not_measured" with the reason, and counted separately from measured.
--   2. NOTHING IS FORCED TO BE ABOUT REVENUE. A task with no plausible commercial effect opts out
--      explicitly, in a column, with a reason. Inventing a revenue link for a backup-rotation task
--      is the same defect as omitting one for a pricing change.

begin;

-- =================================================================================================
-- 1. THE DEADLINE. A target with no date has no trajectory — only a gap.
-- =================================================================================================
-- company_goals had target_value and horizon ('year_1') and no date at all. The date is not
-- invented here: org_departments.north_star already carries it verbatim on two active rows —
--   exec   "AED 1,000,000 by 31 August 2027, with every department's objectives tracing to it"
--   growth "AED 1,000,000 in revenue by 31 August 2027"
-- This column lifts that sentence into a column so a function can subtract it from today.
alter table public.company_goals add column if not exists deadline date;

comment on column public.company_goals.deadline is
  'The date the target must be met by. Nullable on purpose: a goal with no agreed date reports '
  '"no deadline recorded" rather than being given one. revenue_annual is set from the wording '
  'already carried in org_departments.north_star for exec and growth.';

update public.company_goals
   set deadline = date '2027-08-31'
 where key = 'revenue_annual' and deadline is null;

-- =================================================================================================
-- 2. THE CLASSIFICATION. Management must be able to tell activity from a business result.
-- =================================================================================================
-- An override column first, because a heuristic must never be the only answer available.
alter table public.employee_kpi add column if not exists kpi_class text;

alter table public.employee_kpi drop constraint if exists employee_kpi_class_check;
alter table public.employee_kpi add constraint employee_kpi_class_check
  check (kpi_class is null or kpi_class in
    ('activity','leading_indicator','quality_metric','conversion','revenue','cost','risk'));

comment on column public.employee_kpi.kpi_class is
  'Explicit class, set by a human or a manager agent. NULL means "not stated", and readers fall '
  'back to fn_metric_class(), which returns unclassified rather than guessing.';

-- The classifier. Deterministic, keyword-based, and — the only part that matters — it returns
-- 'unclassified' when it cannot tell. A classifier whose default bucket is 'activity' would report
-- that every unrecognised KPI is busywork, which is a different lie from the one it was built to
-- stop. Order is deliberate: money first, then harm, then the funnel, then quality, then inputs.
create or replace function public.fn_metric_class(
  p_label text, p_metric text default null, p_unit text default null)
returns text
language sql immutable
set search_path = 'public'
as $function$
  with t as (select lower(coalesce(p_label,'')||' '||coalesce(p_metric,'')||' '||coalesce(p_unit,'')) s)
  select case
    when (select s from t) ~ '(revenue|turnover|gmv|gross merchandise|dirhams earned|recognised|reveal fee|collections?\b|collected)'
      then 'revenue'
    when (select s from t) ~ '(cost|spend|opex|budget|aed per|per call|price paid|burn|bill)'
      then 'cost'
    when (select s from t) ~ '(risk|fraud|breach|incident|violation|exposure|bad debt|chargeback|refund|penalt|non.?complian|complian|unsafe|leak)'
      then 'risk'
    when (select s from t) ~ '(conversion|convert|win rate|close rate|reach a paid|paid reveal|quote.to|acceptance rate|took up|activation rate)'
      then 'conversion'
    when (select s from t) ~ '(accuracy|quality|pass rate|defect|error rate|bounce|first time|satisfaction|rating|csat|nps|completeness|uptime|availabilit|latency|response time|sla|on.?time|rework)'
      then 'quality_metric'
    when (select s from t) ~ '(pipeline|lead|inquir|enquir|invit|sign.?up|registration|registered|coverage|reach|traffic|visitors|response rate|activation|adoption|retention)'
      then 'leading_indicator'
    -- Count-shaped language only. 'sends' and 'messages' were here in the first draft and pulled
    -- "share of sends that hard bounce" — a quality rate — into 'activity'. A classifier that
    -- mislabels a quality metric as busywork is worse than one that says it cannot tell.
    when (select s from t) ~ '(count|number of|volume|tasks|runs|processed|published|reviewed|completed|closed|throughput|per day|per week)'
      then 'activity'
    else 'unclassified' end;
$function$;

revoke all on function public.fn_metric_class(text, text, text) from public;
grant execute on function public.fn_metric_class(text, text, text) to service_role;

-- =================================================================================================
-- 3. THE ENTRY POINT fn_goal_decompose NEVER HAD
-- =================================================================================================
-- Runs the existing decomposition, then the existing measurement sweep. Both are idempotent:
-- decompose adopts an existing (dept, goal) objective rather than duplicating it, and the sweep
-- overwrites actual_value in place. Called here so this file leaves a cascade with numbers in it,
-- and callable again from cron or a manager agent.
create or replace function public.fn_cascade_refresh()
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_decompose jsonb;
  v_dept_ok int; v_dept_bad int;
  v_kpi_ok int;  v_kpi_bad int;
begin
  v_decompose := public.fn_goal_decompose();
  select measured, failed into v_dept_ok, v_dept_bad from public.fn_dept_objective_measure();
  select measured, failed into v_kpi_ok,  v_kpi_bad  from public.fn_employee_kpi_measure();

  -- NO KPI->OBJECTIVE COLUMN IS WRITTEN HERE, AND THAT IS DELIBERATE.
  -- The first draft of this function bound employee_kpi.serves_objective to the matching
  -- department_objective.id. Staging refused it:
  --   ERROR 23503: Key (serves_objective)=(139) is not present in table "os_objective"
  -- employee_kpi.serves_objective is a foreign key to os_objective, NOT to department_objective.
  -- The column name says "objective"; the constraint says which one, and the two tables are
  -- different layers with different vocabularies. Had the ids happened to overlap, that update
  -- would have joined every role KPI to an unrelated row and nothing would have failed.
  -- The KPI->objective link is therefore resolved at read time in fn_revenue_cascade, on
  -- (department, serves_goal), which is a fact rather than an id coincidence.
  return jsonb_build_object(
    'decompose', v_decompose,
    'department_objectives_measured', v_dept_ok,
    'department_objectives_measure_failed', v_dept_bad,
    'role_kpis_measured', v_kpi_ok,
    'role_kpis_measure_failed', v_kpi_bad,
    'role_kpis_pointing_at_an_os_objective',
      (select count(*) from public.employee_kpi where active and serves_objective is not null),
    'note', 'employee_kpi.serves_objective references os_objective, a second objective table that '
            ||'is measured but carries no company goal_key. It is reported, never written here.');
end $function$;

revoke all on function public.fn_cascade_refresh() from public;
grant execute on function public.fn_cascade_refresh() to service_role;

-- =================================================================================================
-- 4. COMPANY TRAJECTORY — where we are against where we must be
-- =================================================================================================
create or replace function public.fn_revenue_trajectory()
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  g record;
  v_actual numeric;
  v_err text;
  v_days int;
  v_gap numeric;
begin
  select key, goal, metric, target_value, unit, deadline, measure_sql, no_measure_reason
    into g from public.company_goals where key = 'revenue_annual' and active;

  if not found then
    return jsonb_build_object('measured', false,
      'reason', 'company_goals has no active row with key = revenue_annual');
  end if;

  if coalesce(g.measure_sql,'') = '' then
    v_err := coalesce(g.no_measure_reason, 'no measure_sql recorded for this goal');
  else
    begin
      execute g.measure_sql into v_actual;
    exception when others then
      v_actual := null;
      v_err := 'measure_sql failed: ' || sqlerrm;
    end;
  end if;

  v_days := case when g.deadline is null then null else (g.deadline - current_date) end;
  v_gap  := case when v_actual is null then null else g.target_value - v_actual end;

  return jsonb_build_object(
    'objective',        g.goal,
    'metric',           g.metric,
    'target_value',     g.target_value,
    'unit',             g.unit,
    'deadline',         g.deadline,
    'days_remaining',   v_days,
    'measured',         v_actual is not null,
    'actual_value',     v_actual,
    'not_measured_reason', case when v_actual is null then coalesce(v_err,'unknown') end,
    'gap_to_target',    v_gap,
    -- Run rate, not a score. Null propagates: no actual or no deadline means no run rate, never a
    -- comfortable number standing in for one.
    'required_per_month', case
        when v_gap is null or v_days is null or v_days <= 0 then null
        else round(v_gap / (v_days / 30.44), 2) end,
    'required_per_day',   case
        when v_gap is null or v_days is null or v_days <= 0 then null
        else round(v_gap / v_days, 2) end,
    'deadline_passed',  case when v_days is null then null else v_days <= 0 end,
    'source', 'company_goals.measure_sql executed live; deadline from company_goals.deadline');
end $function$;

revoke all on function public.fn_revenue_trajectory() from public;
grant execute on function public.fn_revenue_trajectory() to service_role;

-- =================================================================================================
-- 5. THE CHAIN — company goal -> trajectory -> department objective -> role KPI
-- =================================================================================================
-- Accepts either vocabulary for the department. The certification names 24 packaged departments
-- (customer_success, qa_testing, trust_safety ...); the runtime has 10 canonical dept_keys. They
-- are already reconciled in org_department_alias and every caller here goes through it, because an
-- agent that answers for `customer_success` must not be told its department does not exist.
create or replace function public.fn_revenue_cascade(p_dept text, p_role text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_dept text;
  v_name text;
  v_north text;
  v_objectives jsonb;
  v_kpis jsonb;
  v_os jsonb;
  v_agents text[];
begin
  if coalesce(p_dept,'') = '' then
    return jsonb_build_object('error','department_required');
  end if;

  select d.dept_key, d.name, d.north_star into v_dept, v_name, v_north
    from public.org_departments d where d.dept_key = lower(btrim(p_dept)) and d.active;

  if v_dept is null then
    select d.dept_key, d.name, d.north_star into v_dept, v_name, v_north
      from public.org_department_alias a
      join public.org_departments d on d.dept_key = a.dept_key and d.active
     where a.packaged_department = lower(btrim(p_dept)) and not a.is_second_home;
  end if;

  if v_dept is null then
    return jsonb_build_object(
      'error','unknown_department',
      'asked_for', p_dept,
      'known_canonical', (select jsonb_agg(dept_key order by dept_key)
                            from public.org_departments where active),
      'known_packaged',  (select jsonb_agg(distinct packaged_department)
                            from public.org_department_alias));
  end if;

  -- Department objectives. Every one reports whether it reconciles upward and whether it carries a
  -- number, separately — a linked objective with no target is a different problem from an unlinked
  -- one, and collapsing them is how 66 sentences passed for a cascade.
  select coalesce(jsonb_agg(x order by x->>'objective'), '[]'::jsonb) into v_objectives from (
    select jsonb_build_object(
      'objective',            o.objective,
      'horizon',              o.horizon,
      'reconciles_to_goal',   o.goal_key,
      'company_goal',         cg.goal,
      -- coalesced, not bare: `null = 'revenue_annual'` is NULL, and an objective that does not
      -- reach the revenue target must read as false, not as an unanswered question.
      'is_the_revenue_target', coalesce(o.goal_key = 'revenue_annual', false),
      'target_value',         o.target_value,
      'unit',                 o.unit,
      'measured',             o.actual_value is not null,
      'actual_value',         o.actual_value,
      'measured_at',          o.measured_at,
      'not_measured_reason', case
          when o.actual_value is not null then null
          when coalesce(o.measure_sql,'') = '' then 'no measure_sql recorded for this objective'
          else 'measure_sql present but has not produced a value; run fn_cascade_refresh()' end,
      'attainment_pct', case
          when o.actual_value is null or o.target_value is null or o.target_value = 0 then null
          else round(100.0 * o.actual_value / o.target_value, 1) end
    ) x
    from public.department_objective o
    left join public.company_goals cg on cg.key = o.goal_key and cg.active
   where o.dept_key = v_dept and o.active) s;

  select array_agg(distinct r.runtime_agent_key) into v_agents
    from public.org_role r
   where r.primary_department_id = v_dept and r.status = 'active'
     and r.runtime_agent_key is not null
     and (p_role is null or r.role_id = p_role or r.runtime_agent_key = p_role);

  -- The KPI -> department objective link is resolved on (this department, the goal the KPI names),
  -- not on employee_kpi.serves_objective — that column is a foreign key to os_objective, a
  -- different table. Where the department holds more than one objective against the same goal, all
  -- of them are listed and none is picked.
  select coalesce(jsonb_agg(x order by x->>'agent_key', x->>'kpi'), '[]'::jsonb) into v_kpis from (
    select jsonb_build_object(
      'agent_key',   k.agent_key,
      'kpi',         k.kpi,
      'metric',      k.metric,
      'class',       coalesce(k.kpi_class, public.fn_metric_class(k.kpi, k.metric, k.unit)),
      'class_source', case when k.kpi_class is not null then 'declared' else 'inferred' end,
      'target_value', k.target_value,
      'unit',        k.unit,
      'measured',    k.actual_value is not null,
      'actual_value', k.actual_value,
      'measured_at', k.measured_at,
      'not_measured_reason', case
          when k.actual_value is not null then null
          when k.no_measure_reason is not null then k.no_measure_reason
          when coalesce(k.measure_sql,'') = '' then 'no measure_sql recorded for this KPI'
          else 'measure_sql present but has not produced a value' end,
      'serves_company_goal',           k.serves_goal,
      'serves_department_objectives',  m.objectives,
      'connects_to_revenue_target',    coalesce(k.serves_goal = 'revenue_annual', false),
      'attainment_pct', case
          when k.actual_value is null or k.target_value is null or k.target_value = 0 then null
          else round(100.0 * k.actual_value / k.target_value, 1) end
    ) x
    from public.employee_kpi k
    left join lateral (
      select jsonb_agg(o.objective order by o.objective) as objectives
        from public.department_objective o
       where o.dept_key = v_dept and o.active and o.goal_key = k.serves_goal) m on true
   where k.active and k.agent_key = any(v_agents)) s;

  -- THE SECOND OBJECTIVE TABLE. os_objective is measured (a sweep populates actual_value) and
  -- carries no goal_key at all, so nothing in it reconciles to a company goal. Hiding it would
  -- make the cascade look complete while a department's most current numbers sat outside it.
  select coalesce(jsonb_agg(jsonb_build_object(
      'objective',    oo.objective,
      'measure',      oo.measure,
      'measured',     oo.actual_value is not null,
      'actual_value', oo.actual_value,
      'measured_at',  oo.measured_at,
      'reconciles_to_a_company_goal', false) order by oo.id), '[]'::jsonb)
    into v_os
    from public.os_objective oo
    join public.os_department od on od.os_key = oo.os_key
   where od.dept_key = v_dept and oo.active;

  return jsonb_build_object(
    'department',            v_dept,
    'department_name',       v_name,
    'asked_for',             p_dept,
    'role_filter',           p_role,
    'north_star',            v_north,
    'company_objective',     public.fn_revenue_trajectory(),
    'department_objectives', v_objectives,
    'operating_system_objectives', v_os,
    'operating_system_objectives_note',
      'A second objective table, measured but carrying no company goal_key. Listed so its numbers '
      ||'are visible; none of them reconciles upward, and that is a gap, not a link.',
    'role_kpis',             v_kpis,
    -- Counts, not a composite. There is deliberately no single number here: an average over items
    -- of which half are unmeasured is the exact instrument that reported 97.7% on a zero-revenue
    -- day, and management cannot act on it.
    'counts', jsonb_build_object(
      'department_objectives',                    jsonb_array_length(v_objectives),
      'department_objectives_linked_to_a_goal',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where e->>'reconciles_to_goal' is not null),
      'department_objectives_on_the_revenue_target',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where (e->>'is_the_revenue_target')::boolean),
      'department_objectives_measured',
        (select count(*) from jsonb_array_elements(v_objectives) e
          where (e->>'measured')::boolean),
      'role_kpis',                                jsonb_array_length(v_kpis),
      'role_kpis_measured',
        (select count(*) from jsonb_array_elements(v_kpis) e where (e->>'measured')::boolean),
      'role_kpis_connected_to_the_revenue_target',
        (select count(*) from jsonb_array_elements(v_kpis) e
          where (e->>'connects_to_revenue_target')::boolean),
      'role_kpis_that_are_activity_only',
        (select count(*) from jsonb_array_elements(v_kpis) e where e->>'class' = 'activity'),
      'role_kpis_unclassified',
        (select count(*) from jsonb_array_elements(v_kpis) e where e->>'class' = 'unclassified')),
    'before_you_reallocate',
      'Name the binding constraint first: select public.fn_binding_constraint(). Moving effort to a '
      ||'stage that is not binding changes this department''s activity and not the company''s revenue.');
end $function$;

revoke all on function public.fn_revenue_cascade(text, text) from public;
grant execute on function public.fn_revenue_cascade(text, text) to service_role;

-- =================================================================================================
-- 6. RECONCILIATION COVERAGE — the honest scoreboard for the 24 certification departments
-- =================================================================================================
create or replace view public.v_revenue_cascade_coverage as
with d as (
  select a.packaged_department, a.dept_key
    from public.org_department_alias a
    join public.org_departments od on od.dept_key = a.dept_key and od.active
   where not a.is_second_home),
o as (
  select o.dept_key,
         count(*) filter (where o.active)                                       as objectives,
         count(*) filter (where o.active and cg.key is not null)                as linked_to_a_goal,
         count(*) filter (where o.active and o.goal_key = 'revenue_annual')     as on_revenue_target,
         count(*) filter (where o.active and cg.key is not null
                           and o.target_value is not null
                           and coalesce(o.measure_sql,'') <> '')                as linked_and_measurable,
         count(*) filter (where o.active and o.actual_value is not null)        as measured
    from public.department_objective o
    left join public.company_goals cg on cg.key = o.goal_key and cg.active
   group by o.dept_key),
k as (
  select r.primary_department_id as dept_key,
         count(*) filter (where k.active)                                   as role_kpis,
         count(*) filter (where k.active and k.serves_goal = 'revenue_annual') as kpis_on_revenue,
         count(*) filter (where k.active and k.actual_value is not null)     as kpis_measured
    from public.employee_kpi k
    join public.org_role r on r.runtime_agent_key = k.agent_key and r.status = 'active'
   group by r.primary_department_id)
select d.packaged_department,
       d.dept_key,
       coalesce(o.objectives, 0)            as objectives,
       coalesce(o.linked_to_a_goal, 0)      as objectives_linked_to_a_company_goal,
       coalesce(o.on_revenue_target, 0)     as objectives_on_the_revenue_target,
       coalesce(o.linked_and_measurable, 0) as objectives_linked_and_measurable,
       coalesce(o.measured, 0)              as objectives_measured,
       coalesce(k.role_kpis, 0)             as role_kpis,
       coalesce(k.kpis_on_revenue, 0)       as role_kpis_on_the_revenue_target,
       coalesce(k.kpis_measured, 0)         as role_kpis_measured,
       case
         when coalesce(o.linked_and_measurable,0) > 0 then 'reconciled_and_measurable'
         when coalesce(o.linked_to_a_goal,0)      > 0 then 'reconciled_not_measurable'
         when coalesce(o.objectives,0)            > 0 then 'objectives_but_none_linked_to_a_company_goal'
         else 'no_objective_at_all' end     as reconciliation_status,
       (coalesce(o.on_revenue_target,0) > 0 or coalesce(k.kpis_on_revenue,0) > 0)
                                            as reaches_the_revenue_target
  from d
  left join o on o.dept_key = d.dept_key
  left join k on k.dept_key = d.dept_key;

comment on view public.v_revenue_cascade_coverage is
  'One row per certification department (24, resolved through org_department_alias). Four '
  'reconciliation states, no score: a department that owns an objective nobody can measure is not '
  'the same as one that owns none, and averaging them would hide both.';

grant select on public.v_revenue_cascade_coverage to service_role;

-- =================================================================================================
-- 7. A TASK'S EXPECTED COMMERCIAL EFFECT — with an explicit way to say "none"
-- =================================================================================================
create table if not exists public.task_commercial_effect (
  task_id                    bigint primary key
                               references public.org_tasks(id) on delete cascade,
  -- THE OPT-OUT. Rotating a backup credential has no plausible commercial effect and must not be
  -- made to invent one. Saying so is a recorded decision, not a silent null.
  no_commercial_effect       boolean not null default false,
  no_effect_reason           text,
  -- The claim.
  causal_kpi_chain           text[],      -- ordered: the KPI this moves, then what that moves, ...
  terminal_goal_key          text references public.company_goals(key),
  expected_leading_indicator text,        -- what moves FIRST, and is therefore falsifiable early
  expected_leading_value     numeric,
  expected_outcome           text,        -- the business result claimed
  expected_outcome_value     numeric,
  expected_outcome_unit      text,
  expected_cost_aed          numeric,
  risk                       text,        -- the metric this could damage (CMP-UC-03)
  measurement_window_days    integer,
  owner_agent_key            text,
  review_trigger             text,        -- what would make someone look before the review date
  review_date                date,
  -- The other end of the loop.
  measured_outcome_value     numeric,
  measured_at                timestamptz,
  management_response        text,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  constraint task_commercial_effect_claim_is_complete check (
    (no_commercial_effect
       and no_effect_reason is not null and length(btrim(no_effect_reason)) >= 10
       and causal_kpi_chain is null and terminal_goal_key is null)
    or
    (not no_commercial_effect
       and causal_kpi_chain is not null and array_length(causal_kpi_chain, 1) >= 1
       and terminal_goal_key is not null
       and expected_leading_indicator is not null
       and expected_outcome is not null
       and expected_cost_aed is not null
       and risk is not null
       and measurement_window_days is not null and measurement_window_days > 0
       and owner_agent_key is not null
       and review_trigger is not null
       and review_date is not null)),
  constraint task_commercial_effect_window_sane
    check (measurement_window_days is null or measurement_window_days between 1 and 730)
);

comment on table public.task_commercial_effect is
  'The commercial claim a task is making, or the recorded decision that it makes none. The check '
  'constraint allows exactly two shapes: a complete claim, or an opt-out with a reason. There is '
  'no third state where the fields are simply absent, because that state is what let 2,284 answers '
  'describe work without ever naming what it was worth.';

create index if not exists task_commercial_effect_review_idx
  on public.task_commercial_effect (review_date)
  where not no_commercial_effect and measured_at is null;

create index if not exists task_commercial_effect_goal_idx
  on public.task_commercial_effect (terminal_goal_key)
  where not no_commercial_effect;

create or replace function public.fn_task_commercial_effect(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_task bigint := (p->>'task_id')::bigint;
  v_none boolean := coalesce((p->>'no_commercial_effect')::boolean, false);
begin
  if v_task is null then
    return jsonb_build_object('ok', false, 'error', 'task_id is required');
  end if;
  if not exists (select 1 from public.org_tasks where id = v_task) then
    return jsonb_build_object('ok', false, 'error', 'no such task', 'task_id', v_task);
  end if;

  insert into public.task_commercial_effect as t (
    task_id, no_commercial_effect, no_effect_reason,
    causal_kpi_chain, terminal_goal_key,
    expected_leading_indicator, expected_leading_value,
    expected_outcome, expected_outcome_value, expected_outcome_unit,
    expected_cost_aed, risk, measurement_window_days, owner_agent_key,
    review_trigger, review_date)
  values (
    v_task, v_none, nullif(btrim(coalesce(p->>'no_effect_reason','')),''),
    case when v_none then null else
      (select array_agg(value::text) from jsonb_array_elements_text(coalesce(p->'causal_kpi_chain','[]'::jsonb)) value) end,
    case when v_none then null else nullif(p->>'terminal_goal_key','') end,
    nullif(p->>'expected_leading_indicator',''), (p->>'expected_leading_value')::numeric,
    nullif(p->>'expected_outcome',''), (p->>'expected_outcome_value')::numeric,
    nullif(p->>'expected_outcome_unit',''),
    (p->>'expected_cost_aed')::numeric, nullif(p->>'risk',''),
    (p->>'measurement_window_days')::int, nullif(p->>'owner_agent_key',''),
    nullif(p->>'review_trigger',''), (p->>'review_date')::date)
  on conflict (task_id) do update set
    no_commercial_effect = excluded.no_commercial_effect,
    no_effect_reason     = excluded.no_effect_reason,
    causal_kpi_chain     = excluded.causal_kpi_chain,
    terminal_goal_key    = excluded.terminal_goal_key,
    expected_leading_indicator = excluded.expected_leading_indicator,
    expected_leading_value     = excluded.expected_leading_value,
    expected_outcome     = excluded.expected_outcome,
    expected_outcome_value = excluded.expected_outcome_value,
    expected_outcome_unit  = excluded.expected_outcome_unit,
    expected_cost_aed    = excluded.expected_cost_aed,
    risk                 = excluded.risk,
    measurement_window_days = excluded.measurement_window_days,
    owner_agent_key      = excluded.owner_agent_key,
    review_trigger       = excluded.review_trigger,
    review_date          = excluded.review_date,
    updated_at           = now()
  where t.measured_at is null;   -- a measured claim is history; it is not edited after the fact

  return jsonb_build_object('ok', true, 'task_id', v_task,
    'recorded', case when v_none then 'no_commercial_effect' else 'commercial_claim' end);
exception when check_violation then
  return jsonb_build_object('ok', false, 'error', 'incomplete',
    'detail', sqlerrm,
    'required', 'Either no_commercial_effect with a reason of 10+ characters, or ALL of: '
      ||'causal_kpi_chain, terminal_goal_key, expected_leading_indicator, expected_outcome, '
      ||'expected_cost_aed, risk, measurement_window_days, owner_agent_key, review_trigger, '
      ||'review_date. A partial claim is refused rather than stored as a half-truth.');
end $function$;

revoke all on function public.fn_task_commercial_effect(jsonb) from public;
grant execute on function public.fn_task_commercial_effect(jsonb) to service_role;

-- Measured result -> management response. The rows that are DUE, so a claim cannot quietly expire.
create or replace view public.v_commercial_effect_due as
select e.task_id, t.title, t.dept_key, e.owner_agent_key, e.terminal_goal_key,
       e.expected_outcome, e.expected_outcome_value, e.expected_outcome_unit,
       e.expected_cost_aed, e.risk, e.review_date, e.review_trigger,
       current_date - e.review_date as days_overdue
  from public.task_commercial_effect e
  join public.org_tasks t on t.id = e.task_id
 where not e.no_commercial_effect
   and e.measured_at is null
   and e.review_date <= current_date;

grant select on public.v_commercial_effect_due to service_role;

-- =================================================================================================
-- 8. THE BINDING CONSTRAINT — identify it before reallocating
-- =================================================================================================
-- CMP-CA-04 scored 39.34%. This does not decide the reallocation; it refuses to let one be decided
-- on a stage that is not binding. A stage with a zero denominator is reported 'no_demand', never
-- 0% — an idle stage and a broken stage produce the same zero and are opposite problems.
create or replace function public.fn_binding_constraint(p_days integer default 90)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
  v_since timestamptz := now() - make_interval(days => greatest(p_days, 1));
  v_visitors_reason text;
  v_stages jsonb;
begin
  select no_measure_reason into v_visitors_reason
    from public.company_goals where key = 'website_visitors';

  with raw as (
    select
      (select count(*) from public.customers  where created_at >= v_since)              as customers,
      (select count(*) from public.inquiries  where created_at >= v_since)              as inquiries,
      (select count(distinct q.inquiry_id) from public.quotes q where q.created_at >= v_since)
                                                                                        as inquiries_quoted,
      (select count(*) from public.quotes     where created_at >= v_since)              as quotes,
      (select count(*) from public.transactions
        where revealed_at >= v_since and refund_confirmed_at is null)                   as paid_reveals,
      (select count(*) from public.supplier_capabilities where confirmed_at is not null) as confirmed_suppliers
  ),
  st as (
    select * from (values
      ('visitors_to_registration', 'Site visitors who register',      null::bigint, null::bigint,
       v_visitors_reason),
      ('registration_to_inquiry',  'Registered customers who post an inquiry',
       (select customers from raw), (select inquiries from raw), null),
      ('inquiry_to_quote',         'Inquiries that receive at least one quote',
       (select inquiries from raw), (select inquiries_quoted from raw), null),
      ('quote_to_paid_reveal',     'Quoted inquiries that reach a paid reveal',
       (select inquiries_quoted from raw), (select paid_reveals from raw), null)
    ) v(stage_key, stage, denominator, numerator, not_measurable_reason))
  select jsonb_agg(jsonb_build_object(
      'stage_key', stage_key,
      'stage', stage,
      'denominator', denominator,
      'numerator', numerator,
      'state', case
        when not_measurable_reason is not null then 'not_instrumented'
        when denominator is null or numerator is null then 'not_measured'
        when denominator = 0 then 'no_demand'
        else 'measured' end,
      'pass_through_pct', case
        when not_measurable_reason is not null or denominator is null
          or numerator is null or denominator = 0 then null
        else round(100.0 * numerator / denominator, 1) end,
      'reason', not_measurable_reason)
    order by stage_key)
    into v_stages from st;

  return jsonb_build_object(
    'window_days', p_days,
    'stages', v_stages,
    'confirmed_suppliers', (select count(*) from public.supplier_capabilities where confirmed_at is not null),
    -- The binding stage is the lowest MEASURED pass-through. Stages that are not instrumented or
    -- have no demand are excluded from the ranking and listed separately, because a stage nobody
    -- can measure could easily be the real constraint and must not be quietly ruled out.
    'binding_stage', (
      select e->>'stage_key' from jsonb_array_elements(v_stages) e
       where e->>'state' = 'measured'
       order by (e->>'pass_through_pct')::numeric asc limit 1),
    'binding_pass_through_pct', (
      select (e->>'pass_through_pct')::numeric from jsonb_array_elements(v_stages) e
       where e->>'state' = 'measured'
       order by (e->>'pass_through_pct')::numeric asc limit 1),
    'stages_ranked', (select count(*) from jsonb_array_elements(v_stages) e
                       where e->>'state' = 'measured'),
    'stages_excluded_from_the_ranking', (
      select coalesce(jsonb_agg(jsonb_build_object('stage_key', e->>'stage_key',
                                                   'state', e->>'state',
                                                   'reason', e->>'reason')), '[]'::jsonb)
        from jsonb_array_elements(v_stages) e where e->>'state' <> 'measured'),
    'reallocation_rule',
      'Effort moved to a stage other than the binding one changes activity, not revenue. If a stage '
      ||'is listed as not_instrumented, the honest answer is that the binding constraint is not '
      ||'known yet and the first move is to instrument it.',
    'trajectory', public.fn_revenue_trajectory());
end $function$;

revoke all on function public.fn_binding_constraint(integer) from public;
grant execute on function public.fn_binding_constraint(integer) to service_role;

-- =================================================================================================
-- 9. ENTRY POINTS. A capability nobody can call is the defect this file started with.
-- =================================================================================================
insert into public.agent_tool
  (tool_id, purpose, kind, impl_kind, impl_target, authorised_roles, authorised_departments,
   min_authority, input_schema, timeout_seconds, failure_behaviour, requires_current_data, note)
values
  ('revenue_cascade',
   'The chain from the AED 1,000,000 revenue objective down to this department''s objectives and '
   ||'this role''s KPIs, with the current measured value or an explicit reason there is none.',
   'read', 'rpc', 'fn_revenue_cascade', '{*}', '{*}', 'advisory',
   '{"type":"object","required":["p_dept"],"properties":{"p_dept":{"type":"string"},"p_role":{"type":"string"}},"additionalProperties":false}'::jsonb,
   15, 'degrade_with_caveat', true,
   'Accepts either the certification department name or the canonical dept_key.'),
  ('binding_constraint',
   'The measured funnel stage that limits revenue right now, with the stages nobody can measure '
   ||'listed rather than silently excluded. Call before proposing a reallocation of effort.',
   'read', 'rpc', 'fn_binding_constraint', '{*}', '{*}', 'advisory',
   '{"type":"object","properties":{"p_days":{"type":"integer","minimum":1,"maximum":365}},"additionalProperties":false}'::jsonb,
   15, 'degrade_with_caveat', true,
   'A stage with a zero denominator reports no_demand, never 0%.'),
  ('record_commercial_effect',
   'Record what a task is expected to be worth: causal KPI chain, leading indicator, outcome, cost, '
   ||'risk, measurement window, owner and review trigger — or that it has no commercial effect, with a reason.',
   'write', 'rpc', 'fn_task_commercial_effect', '{*}', '{*}', 'advisory',
   '{"type":"object","required":["task_id"],"properties":{"task_id":{"type":"integer"},"no_commercial_effect":{"type":"boolean"},"no_effect_reason":{"type":"string"},"causal_kpi_chain":{"type":"array","items":{"type":"string"}},"terminal_goal_key":{"type":"string"},"expected_leading_indicator":{"type":"string"},"expected_leading_value":{"type":"number"},"expected_outcome":{"type":"string"},"expected_outcome_value":{"type":"number"},"expected_outcome_unit":{"type":"string"},"expected_cost_aed":{"type":"number"},"risk":{"type":"string"},"measurement_window_days":{"type":"integer"},"owner_agent_key":{"type":"string"},"review_trigger":{"type":"string"},"review_date":{"type":"string"}},"additionalProperties":false}'::jsonb,
   15, 'fail_closed', true,
   'A partial claim is refused. Either it is complete or it is an explicit opt-out.')
on conflict (tool_id) do update set
  purpose = excluded.purpose, impl_target = excluded.impl_target,
  input_schema = excluded.input_schema, note = excluded.note, active = true;

commit;

-- Populate the cascade the routines above read. Outside the transaction on purpose: this executes
-- every stored measure_sql, and one bad measure must not roll back the schema.
select public.fn_cascade_refresh();
