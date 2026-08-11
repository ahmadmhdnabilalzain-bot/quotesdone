-- THE GOAL KEY ON A DEPARTMENTAL OBJECTIVE WAS A BULK STAMP, NOT A DECOMPOSITION.
--
-- Measured on production 2026-08-11 18:05 UTC, per department:
--
--   dept_key            objectives   distinct goal_keys
--   exec                    8            1   ('autonomous_decision_rate' on ALL EIGHT)
--   procurement             7            1   ('rfq_completion_rate' on all seven)
--   customer_success        4            1
--   finance                 4            1
--   it / knowledge / legal / marketing   4/4/3/4   1 each
--   the other 17 departments             0 goal_keys - sales among them
--
-- Every department that carries a goal_key carries exactly ONE, applied to all of its objectives
-- regardless of what they say. The proof it is a stamp and not a judgement is exec: its own
-- objective "Reach AED 1M annual revenue" carries goal_key 'autonomous_decision_rate', as do
-- "Keep the company cash-flow positive" and "Expand supplier coverage across all 84 categories".
--
-- So the AED 1M goal had FOUR departmental objectives pointing at it (all four in finance) and the
-- executive objective that names it in its own text pointed somewhere else.
--
-- THE FOUNDER'S INSTRUCTION IS THAT THE TARGET MUST DECOMPOSE BY ROUTINE, NOT BY HAND. This file
-- is that routine. It does the part that is genuinely derivable - a company goal is owned by a
-- department, so that department must hold an objective for it, carrying the goal's own target and
-- the goal's own measure - and it repairs the exec stamp, which is demonstrably wrong rather than
-- merely unmapped.
--
-- BOUNDARY, STATED PLAINLY: this routine can only decompose the 8 company goals that carry a
-- measure_sql. The other 55 carry a target and no measure, so there is nothing to hand down; they
-- are named in the report below and are the next build order, not a silent omission.

-- ---------------------------------------------------------------------------------------------
-- 1. REPAIR THE EXEC STAMP
--
-- Not a delete. Each of the eight is re-pointed at the goal its own text names, or set to NULL
-- where no company goal matches - an honest NULL beats a wrong link, because a wrong link is what
-- made the revenue goal look owned when it was not.
-- ---------------------------------------------------------------------------------------------

update public.department_objective set goal_key = 'revenue_annual'
 where dept_key='exec' and objective ilike '%AED 1M annual revenue%';

update public.department_objective set goal_key = 'supplier_coverage_10x86'
 where dept_key='exec' and objective ilike '%supplier coverage across all 84 categories%';

update public.department_objective set goal_key = 'human_intervention'
 where dept_key='exec' and objective ilike '%bottleneck%';

-- These three genuinely are about autonomous decision-making and keep the key they have:
--   "Ensure every department achieves at least 90% of its KPIs"
--   "Align all departments with company goals"
--   "Ensure cross-department collaboration"
-- and "Keep the company cash-flow positive" has no matching company goal with a measure, so it is
-- set to NULL rather than left pointing at a decision-rate metric it has nothing to do with.
update public.department_objective set goal_key = null
 where dept_key='exec' and objective ilike '%cash-flow positive%';

-- ---------------------------------------------------------------------------------------------
-- 2. THE DECOMPOSITION ROUTINE
--
-- For every active, measurable company goal whose owning department is active: that department
-- must hold an active objective for that goal, carrying the goal's target, unit and measure. An
-- objective that already exists for the pair is ADOPTED (given the measure it lacked) rather than
-- duplicated - the four finance objectives already pointing at revenue_annual are not replaced.
--
-- Idempotent by construction: running it twice changes nothing the second time.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_goal_decompose()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record;
  v_created int := 0;
  v_adopted int := 0;
  v_id bigint;
  v_unmeasurable int;
begin
  for r in
    select g.key, g.goal, g.target_value, g.unit, g.measure_sql, g.owner_dept, g.horizon
      from company_goals g
      join org_departments d on d.dept_key = g.owner_dept and d.active
     where g.active and coalesce(g.measure_sql,'') <> ''
  loop
    -- Adopt the existing objective for this (department, goal) pair if there is one.
    select id into v_id from department_objective
     where dept_key = r.owner_dept and goal_key = r.key and active
     order by sort, id limit 1;

    if v_id is not null then
      update department_objective
         set target_value = coalesce(target_value, r.target_value),
             unit         = coalesce(unit,         r.unit),
             measure_sql  = coalesce(measure_sql,  r.measure_sql),
             updated_at   = now()
       where id = v_id
         and (measure_sql is null or target_value is null or unit is null);
      if found then v_adopted := v_adopted + 1; end if;
    else
      insert into department_objective
        (dept_key, objective, horizon, goal_key, target_value, unit, measure_sql, status, active)
      values
        (r.owner_dept, r.goal, coalesce(r.horizon,'year_1'), r.key,
         r.target_value, r.unit, r.measure_sql, 'active', true);
      v_created := v_created + 1;
    end if;
  end loop;

  select count(*) into v_unmeasurable from company_goals where active and coalesce(measure_sql,'')='';

  return jsonb_build_object(
    'created', v_created,
    'adopted', v_adopted,
    'company_goals_without_a_measure', v_unmeasurable,
    'note', 'A goal with no measure_sql cannot be handed down. Those '||v_unmeasurable||
            ' goals are the same defect one level up.');
end $function$;

revoke all on function public.fn_goal_decompose() from public;

-- Weekly, before the Monday KPI review at 04:00, so a department that gained an objective is
-- measured by the 03:25 sweep and reviewed in the same cycle.
select cron.unschedule('goal_decompose_weekly')
 where exists (select 1 from cron.job where jobname='goal_decompose_weekly');
select cron.schedule('goal_decompose_weekly', '10 3 * * 1',
                     $$select public.fn_goal_decompose();$$);
