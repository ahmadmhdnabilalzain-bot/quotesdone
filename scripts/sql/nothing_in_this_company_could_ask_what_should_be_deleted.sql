-- "WHAT SHOULD BE DELETED?" — spec #1 L363, and nothing in this company could ask it.
--
-- One of only two ABSENT verdicts in 62 claims of the architecture audit. The other was cost per
-- OS, which landed earlier tonight. fn_evolution_scan proposes ADDITIONS and IMPROVEMENTS only, so
-- the company could grow and never prune, and every session added to a codebase that already
-- carried redundant definitions, duplicate knowledge and dead configuration.
--
-- IT PROPOSES. IT NEVER DELETES. Every candidate becomes an agent_actions row with
-- kind='delete_proposal' and status='needs_review', which is the existing approval path, and each
-- proposal carries THE EXACT SQL THAT COUNTED IT so the reviewer can re-run the number rather than
-- trust it. A routine that deletes on its own judgement is not autonomy, it is data loss with a
-- schedule.
--
-- Measured on production 2026-08-12 before writing it, so the categories are real and not imagined:
--
--   96  model_policy_by_identity rows, scope='target_employee'   SUPERSEDED TONIGHT
--   37  company_goals: active, no measure_sql, no departmental objective
--   33  agent_expectations rows naming neither a real employee nor any cron job
--   19  employee_kpi rows: active, no measure_sql
--    1  org_agents row: inactive
--    0  scenario_library never touched · 0 cron jobs calling a function that does not exist
--
-- THE 96 ARE THE INTERESTING ONE. They were correctly left alone by two previous sessions while
-- they were merely inert. As of tonight they are SUPERSEDED: org_agents.routing_tier carries the
-- same four-role taxonomy against real employees, fn_ai_route reads it, and five of the seven models
-- those rows name do not exist in model_registry at all. That is the difference between "unused" and
-- "replaced", and only the second is a deletion case. The proposal says so and still asks first.

create or replace function public.fn_delete_proposer()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_n int; v_opened int := 0; v_found jsonb := '[]'::jsonb; v_owner text;
  CANDIDATES constant jsonb := jsonb_build_array(
    jsonb_build_object(
      'key','model_policy_by_identity_target_employee',
      'title','96 imported model-policy rows are superseded by org_agents.routing_tier',
      'owner','ai_director', 'risk','low',
      'sql', 'select count(*) from model_policy_by_identity where scope=''target_employee''',
      'why','Addressed to <department>-<role> text keys that resolve to no employee: 0 of 96 match an org_agents.agent_key. Five of the seven models they name are absent from model_registry, so honouring them would route employees to models this company cannot call. Their judgement - the four-role taxonomy - now lives on org_agents.routing_tier and is read by fn_ai_route. Superseded, not merely unused.'),
    jsonb_build_object(
      'key','decorative_company_goals',
      'title','Company goals that cannot be missed and cannot pull anything down',
      'owner','analytics_director', 'risk','medium',
      'sql', 'select count(*) from company_goals g where g.active and coalesce(g.measure_sql,'''')='''' and not exists (select 1 from department_objective d where d.goal_key=g.key and d.active)',
      'why','Active, no measure_sql, and no department has taken an objective for them. A goal that cannot be measured cannot be missed, so it cannot make any department accountable. Either give it a measure or retire it - leaving it active makes the goal list look fuller than the company is. RETIRE means active=false, not a row delete: the history is worth keeping.'),
    jsonb_build_object(
      'key','orphan_agent_expectations',
      'title','agent_expectations rows watching something that does not exist',
      'owner','it', 'risk','low',
      'sql', 'select count(*) from agent_expectations e where not exists (select 1 from org_agents a where a.agent_key=e.agent) and not exists (select 1 from cron.job j where j.jobname ilike ''%''||e.agent||''%'' or j.command ilike ''%''||e.agent||''%'')',
      'why','This table conflates employees with cron job names - the fourth identity vocabulary in this database. These rows name neither. Each one can raise a silence alarm about a thing that cannot run, which is how an employee gets dispatched to diagnose nothing.'),
    jsonb_build_object(
      'key','unmeasurable_employee_kpis',
      'title','Employee KPIs with a target and no way to measure it',
      'owner','analytics_director', 'risk','medium',
      'sql', 'select count(*) from employee_kpi k where k.active and coalesce(k.measure_sql,'''')=''''',
      'why','An employee is told it is judged on something nobody can score. Most of these need an instrument or demand that does not exist yet rather than deletion - the proposal is to decide deliberately per KPI, not to delete the set.'),
    jsonb_build_object(
      'key','inactive_org_agents',
      'title','Employees marked inactive and still on the books',
      'owner','hr_director', 'risk','low',
      'sql', 'select count(*) from org_agents where not coalesce(active,true)',
      'why','An inactive employee still resolves in manager chains and still appears in joins that do not filter on active. Either reactivate it or remove it deliberately.')
  );
begin
  -- as t(c): jsonb_array_elements returns a column called "value", and an alias after the function
  -- names the FROM item, not the column. `... ) c` therefore gives r.value, not r.c.
  for r in select c from jsonb_array_elements(CANDIDATES) as t(c) loop
    execute (r.c->>'sql') into v_n;
    v_found := v_found || jsonb_build_object('key', r.c->>'key', 'count', v_n);
    if coalesce(v_n,0) = 0 then continue; end if;

    -- One open proposal per category. A weekly routine that re-files the same finding is noise,
    -- and noise is how a real proposal gets ignored.
    if exists (select 1 from agent_actions
                where kind='delete_proposal' and target_id = (r.c->>'key')
                  and status in ('pending','needs_review')) then continue; end if;

    select agent_key into v_owner from org_agents where agent_key = (r.c->>'owner') and active;

    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail,
                              target_table, target_id)
    values (coalesce(v_owner, 'brief'), 'delete_proposal', 'needs_review', r.c->>'risk',
            v_n || ' — ' || (r.c->>'title'),
            'Decide deliberately: remove, retire (active=false), or keep with a stated reason. '
            || 'Do not close this without one of the three.',
            jsonb_build_object(
              'category',      r.c->>'key',
              'count',         v_n,
              'why',           r.c->>'why',
              'counted_by',    r.c->>'sql',
              'counted_at',    now(),
              'proposes',      'review for removal — this routine never deletes anything'),
            'delete_proposal', r.c->>'key');
    v_opened := v_opened + 1;
  end loop;

  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('delete_proposer', 'ok', jsonb_build_object('opened', v_opened, 'found', v_found),
          'Proposed ' || v_opened || ' removal review(s). This routine proposes only and has no delete statement in it.',
          now(), now());

  return jsonb_build_object('ok', true, 'opened', v_opened, 'found', v_found);
end $function$;

revoke all on function public.fn_delete_proposer() from public;
revoke all on function public.fn_delete_proposer() from anon;

-- Weekly, Mondays 03:50 — after the KPI measures and the goal decomposition, before the 04:00 KPI
-- review, so a proposal lands in the same cycle management already looks at.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
