-- GOALS CARRY A DEADLINE PACE (autonomy audit, degrading gap 10).
--
-- MEASURED. company_goals has 63 active rows (31 with measure_sql, the other 32 honestly carry a
-- no_measure_reason), and the flagship revenue_annual goal carries a real deadline (2027-08-31, AED
-- 1,000,000). But nothing computes whether the company is ON PACE for a dated target — annual periods
-- reset each January with no cumulative trajectory, so a goal can drift toward its deadline unseen.
--
-- THIS FILE adds fn_goal_pace(): for every active goal that has a deadline, a target and a measure, it
-- computes the linear-ramp expected value at today's date, whether actual is behind that pace, and the
-- per-day run-rate now required to still hit the target by the deadline. Pure date math over
-- already-measured values, read-only, no LLM. It does NOT add company_goals.target_date — the deadline
-- column already IS the date, and a second column would split the source of truth. It surfaces the AED
-- 1M target's pace the moment anyone (the founder, or the exec meeting once wired) reads it.
--
--   node scripts/apply_sql.mjs scripts/sql/goals_carry_a_deadline_pace.sql --apply --ddl

begin;

create or replace function public.fn_goal_pace()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with g as (
    select cg.key, cg.goal, cg.target_value, cg.unit, coalesce(cg.direction,'at_least') dir, cg.owner_dept,
           cg.deadline, cg.created_at::date as anchor, gp.actual_value
      from public.company_goals cg
      left join public.goal_period gp
        on gp.goal_key = cg.key and gp.horizon = 'annual' and gp.period_label = to_char(now(),'YYYY')
     where cg.active and cg.deadline is not null and cg.target_value is not null and cg.measure_sql is not null),
  c as (
    select g.*, (g.deadline - g.anchor) as days_total, (current_date - g.anchor) as days_elapsed,
           greatest(g.deadline - current_date, 0) as days_remaining
      from g),
  p as (
    select c.*, least(1.0, greatest(0.0, c.days_elapsed::numeric / nullif(c.days_total,0))) as frac
      from c)
  select coalesce(jsonb_agg(jsonb_build_object(
      'goal_key', p.key, 'goal', p.goal, 'owner_dept', p.owner_dept,
      'target', p.target_value, 'unit', p.unit, 'actual', coalesce(p.actual_value,0),
      'deadline', p.deadline, 'days_remaining', p.days_remaining,
      'time_elapsed_pct', round(100.0 * p.frac, 1),
      'expected_at_pace', round(p.target_value * p.frac, 2),
      'attainment_pct', round(100.0 * coalesce(p.actual_value,0) / nullif(p.target_value,0), 1),
      'behind_pace', coalesce(p.actual_value,0) < p.target_value * p.frac,
      'required_run_rate_per_day',
        case when p.days_remaining > 0
             then round(greatest(p.target_value - coalesce(p.actual_value,0), 0) / p.days_remaining, 2)
             else null end)
      order by p.deadline), '[]'::jsonb)
    from p;
$function$;

revoke execute on function public.fn_goal_pace() from public;

commit;
