-- THE GOAL LEDGER WAS STUCK IN JULY, AND EVERY UNMEASURED GOAL WAS SCORING 100%.
--
-- MEASURED 11 Aug 2026:
--   goal_period horizons/periods present ... monthly 2026-07, quarterly 2026-Q3, annual 2026
--   rows per horizon ....................... 61
--   rows with a measured actual ............ 5 of 61
--   company_goals with a measure_sql ....... 8 of 63
--   company_goals.direction values ......... at_least 43, at_most 19, up 1
--
-- Three defects, and they compound into one wrong number in the founder's daily email.
--
-- 1. THE PERIOD NEVER ROLLS. fn_goal_period_refresh only ever UPDATEs rows that already exist. The
--    rows were seeded once with period_label '2026-07'. It is 11 August. Everything reading
--    "monthly" has been reading July for eleven days, and would have read July all year.
--
-- 2. THE DIRECTION BRANCH IS UNREACHABLE. The function tests `coalesce(direction,'up') = 'down'`
--    while company_goals stores 'at_least' and 'at_most' — 19 goals are at_most and not one of them
--    can ever take that branch. "Bad debt below 1%", "Break-even within 3 months" and "Average
--    supplier response under 24 hours" were all being scored as though a bigger number were better.
--
-- 3. least(100.0, NULL) IS 100.0. This is the one that produced the number. fn_founder_brief scores
--    attainment as `least(100.0, 100.0*actual/nullif(target,0))`, and PostgreSQL's least() IGNORES
--    nulls rather than propagating them — so all 56 goals with no measured actual scored a perfect
--    100%, and the two that WERE measured (revenue 0.0%, quote conversion 57.2%) were averaged in
--    with them. The founder's brief this morning read "Monthly goal attainment: 97.7% against
--    target" on a day the company recognised AED 0 of revenue against an AED 83,333 monthly target.
--
-- The fix makes the number HARDER, not softer: unmeasured is null and is excluded from the average,
-- the average is stated with the denominator it was computed from, and at_most goals are scored the
-- right way up. Attainment will read materially worse than 97.7% tomorrow. That is the correction.

begin;

-- ROUTINE REMOVED 7 September 2026. public.fn_goal_period_refresh was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ATTAINMENT, AS ONE FUNCTION SO EVERY READER GETS THE SAME ANSWER. fn_founder_brief computed it
-- inline; so would the board report and the period report if they ever carried it. One definition,
-- direction-aware, unmeasured excluded, and it returns the denominator so a caller cannot quote the
-- percentage without saying what it is a percentage OF.
create or replace function public.fn_goal_attainment(p_horizon text default 'monthly')
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with p as (
    select case p_horizon
             when 'monthly'   then to_char(now(),'YYYY-MM')
             when 'quarterly' then to_char(now(),'YYYY')||'-Q'||extract(quarter from now())::int
             else to_char(now(),'YYYY') end as label),
  s as (
    select g.actual_value, g.target_value, coalesce(cg.direction,'at_least') dir
      from goal_period g
      left join company_goals cg on cg.key = g.goal_key
      cross join p
     where g.horizon = p_horizon and g.period_label = p.label and g.target_value is not null)
  select jsonb_build_object(
    'horizon', p_horizon,
    'period', (select label from p),
    'goals_total', count(*),
    'goals_measured', count(*) filter (where actual_value is not null),
    'pct', round(avg(case
        -- NOT least(100, ...): least() ignores nulls, so an unmeasured goal scored 100%.
        when actual_value is null then null
        when dir in ('at_most','down')
          then least(100.0, case when actual_value = 0 then 100.0
                                 else 100.0 * target_value / nullif(actual_value,0) end)
        else least(100.0, 100.0 * actual_value / nullif(target_value,0)) end), 1))
  from s;
$function$;

revoke all on function public.fn_goal_attainment(text) from public;
revoke all on function public.fn_goal_attainment(text) from anon;
grant execute on function public.fn_goal_attainment(text) to service_role;
grant execute on function public.fn_goal_attainment(text) to authenticated;

commit;
