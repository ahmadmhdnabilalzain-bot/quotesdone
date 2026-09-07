-- THE CHAIN HAS EDGES. WHAT IT DOES NOT HAVE IS A NUMBER AT TWO OF ITS FOUR LEVELS.
--
-- Measured on production 2026-08-11 17:47-18:10 UTC, before anything was built. The session brief
-- said employee KPIs were "effectively ZERO" and that departmental objectives had no link to
-- company goals. Both are wrong, and the counts prove it:
--
--   employee_kpi          124 rows · 123 active · 94 with measure_sql · 95 with serves_goal
--                         95 distinct employees · 0 active employees WITHOUT a KPI
--   department_objective   66 rows · 66 active · 25 of 25 active departments covered
--                         38 carrying a goal_key · 0 orphan goal_keys
--   fn_kpi_scoreboard()   EXISTS, executes every KPI's measure_sql live, returns attainment:
--                         49 NO DATA · 46 MISSED · 26 MET · 2 NEAR
--   fn_kpi_review()       EXISTS, on cron Mondays 04:00. Every MISSED KPI becomes an org_tasks row
--                         AND an outcome_record with a re-measure date. The learning loop is real.
--   fn_agent_context      already emits "# YOUR KPIs - this is how your work is measured",
--                         with target, unit, cadence and "serves company goal <key>".
--
-- So the layer the brief said to BUILD is built. The two defects that are real are narrower and
-- they are both the same defect: A LEVEL THAT CANNOT HOLD ITS OWN NUMBER.
--
--   department_objective  has NO target_value and NO measure_sql column at all.
--                         66 departmental objectives, of which 0 can ever be measured.
--                         A department cannot be told it is failing, so it cannot notice.
--   employee_kpi          has NO actual_value and NO measured_at column.
--                         94 KPIs carry a measure_sql and the number it produces is computed live
--                         by fn_kpi_scoreboard and then THROWN AWAY. Nothing stores it, so
--                         fn_agent_context shows every employee its TARGET and never its NUMBER,
--                         and no trend over time exists for any employee in the company.
--
-- os_objective got this right - actual_value + measured_at, refreshed by fn_os_objective_measure on
-- cron at 03:20 daily. The brief's own instruction is to copy that pattern. This file copies it
-- DOWNWARD to the two levels that lack it, rather than rebuilding anything that works.
--
-- WHY THE HOT PATH NEEDS THE STORED COLUMN AND NOT A LIVE CALL. fn_agent_context runs at 765 ms
-- against an 8-second PostgREST wall. Executing up to 8 arbitrary measure_sql statements per
-- employee prompt would put that wall back. A column refreshed on cron costs the prompt nothing.
--
-- SEPARATELY MEASURED AND NOT FIXED HERE (it is a data change, and it gets its own file):
-- department_objective.goal_key is a BULK STAMP, not a mapping. Every department that carries a
-- goal_key at all carries exactly ONE across all its objectives; 17 of 25 carry none. The exec
-- department's own objective "Reach AED 1M annual revenue" points at goal_key
-- 'autonomous_decision_rate'. sales has 4 objectives and no goal at all.

-- ---------------------------------------------------------------------------------------------
-- 1. THE TWO MISSING NUMBERS
-- ---------------------------------------------------------------------------------------------

alter table public.department_objective
  add column if not exists target_value numeric,
  add column if not exists unit         text,
  add column if not exists measure_sql  text,
  add column if not exists actual_value numeric,
  add column if not exists measured_at  timestamptz;

alter table public.employee_kpi
  add column if not exists actual_value numeric,
  add column if not exists measured_at  timestamptz;

comment on column public.department_objective.measure_sql is
  'Scalar SQL returning one numeric. Refreshed into actual_value by fn_dept_objective_measure on cron. Added 11 Aug 2026: 66 departmental objectives existed with no way to measure any of them.';
comment on column public.employee_kpi.actual_value is
  'Last measured value of measure_sql, refreshed by fn_employee_kpi_measure on cron. NULL means the measure failed or does not exist - never 0. Added 11 Aug 2026: the number was computed live by fn_kpi_scoreboard and discarded, so no employee could be shown its own current number and no trend existed.';

-- ---------------------------------------------------------------------------------------------
-- 2. ORG_TASKS GETS AN OWNER
--
-- Measured: org_tasks carries dept_key on 839 of 839 and has no employee column. fn_kpi_review -
-- the routine that turns a missed KPI into work - HAS the owning employee in hand (r.agent_key)
-- and writes it into free prose: 'Owner: '||r.agent_key inside detail. 143 of 839 rows carry that
-- string. So the owner was known at write time and thrown into text nothing can query or index.
--
-- org_tasks.objective_id is NOT the missing link and must not be backfilled with objectives.
-- Measured: it is FK'd to org_objectives(id) ON DELETE CASCADE, and org_objectives holds 0 rows.
-- Reading its columns (objective, raw_input, created_by default 'founder', status, priority,
-- outcome) it is the FOUNDER'S OWN objective intake, not the OS objective layer. It is NULL on all
-- 839 rows because the founder has never entered an objective - a feature nobody used, not an
-- unfinished writer. Pointing it at os_objective ids would violate the foreign key.
-- ---------------------------------------------------------------------------------------------

alter table public.org_tasks
  add column if not exists assigned_agent text references public.org_agents(agent_key);

create index if not exists org_tasks_assigned_agent_idx
  on public.org_tasks (assigned_agent) where assigned_agent is not null;

comment on column public.org_tasks.assigned_agent is
  'The employee who owns this task. Added 11 Aug 2026. Before it, a task belonged to a department and no employee owned anything, so "report results back to management" had no subject. Backfilled from the Owner: prose fn_kpi_review had already been writing into detail.';

-- Backfill: only where the owner was recorded in prose AND still resolves to a real employee.
-- No guessing from dept_key - a department has up to 12 employees and picking one would be
-- inventing an assignment the company never made.
update public.org_tasks t
   set assigned_agent = m.k
  from (select id, substring(detail from 'Owner: ([a-z0-9_]+)') as k from public.org_tasks
         where detail ~ 'Owner: ' and assigned_agent is null) m
 where t.id = m.id
   and m.k is not null
   and exists (select 1 from public.org_agents a where a.agent_key = m.k);

-- ---------------------------------------------------------------------------------------------
-- 3. THE MEASURE ROUTINES - the fn_os_objective_measure pattern, copied down two levels
--
-- Both write NULL on failure, never 0. A 0 that means "the measurement broke" is the defect that
-- put 97.7% attainment in the founder's email on a zero-revenue day.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_dept_objective_measure()
returns table(measured integer, failed integer)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v numeric; n_ok int := 0; n_bad int := 0;
begin
  for r in select id, measure_sql from department_objective
            where coalesce(active,true) and coalesce(measure_sql,'') <> '' loop
    begin
      execute r.measure_sql into v;
      update department_objective set actual_value = v, measured_at = now() where id = r.id;
      n_ok := n_ok + 1;
    exception when others then
      update department_objective set actual_value = null, measured_at = null where id = r.id;
      n_bad := n_bad + 1;
    end;
  end loop;
  return query select n_ok, n_bad;
end $function$;

revoke all on function public.fn_dept_objective_measure() from public;

-- The employee KPI measure reuses fn_kpi_scoreboard rather than re-implementing the execute loop:
-- the scoreboard ALREADY runs every measure_sql, already traps its own errors and already returns
-- NULL for a failure. Two loops that must agree is how sec()/J() ended up with 8 and 11 variants.
create or replace function public.fn_employee_kpi_measure()
returns table(measured integer, failed integer)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare n_ok int := 0; n_bad int := 0;
begin
  with s as (select kpi_id, actual from fn_kpi_scoreboard())
  update employee_kpi k
     set actual_value = s.actual,
         measured_at  = case when s.actual is null then null else now() end
    from s where s.kpi_id = k.id;

  select count(*) filter (where measured_at is not null),
         count(*) filter (where measured_at is null and coalesce(measure_sql,'') <> '')
    into n_ok, n_bad
    from employee_kpi where active;
  return query select n_ok, n_bad;
end $function$;

revoke all on function public.fn_employee_kpi_measure() from public;

-- ---------------------------------------------------------------------------------------------
-- 4. ON CRON, beside the objective measure that already runs at 03:20
-- ---------------------------------------------------------------------------------------------

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

