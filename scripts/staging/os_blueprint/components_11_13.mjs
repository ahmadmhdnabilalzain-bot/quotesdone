// Spec file #2, components 11-13 — the KPI Engine, the Memory System, the Learning Loop.
//
// 21 requirements. Every one of them asks the same three questions in the same order, because
// this section is where the "built, populated, verified, read by nothing" failure has bitten
// hardest: os_objective was 50 rows nobody read, memory_promotions is a table with a writer and
// no rows, agent_reputation is 66 scored employees whose only reference is the function that
// wrote them.
//
//   1. does the mechanism EXIST?
//   2. is it POPULATED, and does it RUN?
//   3. does anything READ its output?
//
// Five rules govern the SQL below. Rules 4 and 5 are new in round 3 and each one closes a way
// this file was proved to manufacture a MET verdict on 6 Aug 2026.
//
// A column that exists is not a mechanism that works. Five columns in this section
// (os_objective.measure_sql/actual_value, employee_kpi.serves_objective, org_tasks.root_cause,
// agent_memory.horizon, os_runbooks.os_key) were added but never written to. So no check here is
// satisfied by information_schema alone: existence is always paired with a row count and a reader.
//
// A reader must be something other than the writer. fn_reputation_recompute referencing
// agent_reputation is not a reader of agent_reputation, it is the thing that filled it. RD() below
// derives the exclusion structurally: a routine that INSERTs or UPDATEs the table, and any trigger
// function bolted onto the table, is a writer, whoever builds it and whenever.
//
// A test that matches two words anywhere in a routine's text is not a test that the routine joins
// them. fn_agent_context mentions agent_memory, and it mentions "horizon" eight times — every one
// of them about os_objective horizons, none about memory. A naive conjunction would have scored it
// a reader of agent_memory.horizon, which is the comp-16-health-score defect in a new costume.
// Where a check is about a COLUMN, the two names must appear near each other, not merely both —
// and RD_COL applies that to VIEWS as well now, where it previously used the naive conjunction it
// forbids for routines.
//
// RULE 4: writing through a helper is still writing. The earlier exclusion matched only a direct
// `insert into <t>` in the routine's own body, so fn_event_consolidate — which writes
// institutional_memory by calling fn_task_lesson and carries no insert statement of its own —
// scored as a READER of the table it fills. WRITERS_OF now also excludes any routine that calls a
// direct writer, which is what makes the structural claim true rather than nearly true.
//
// RULE 5: a reader nothing calls is not a reader. comp-13-performance asked that question and no
// other check in this file did, so eight reader conjuncts accepted dead code. RD() now requires
// every routine it counts to be named by another routine or to sit on an ACTIVE cron job. That is
// one level of reachability, deliberately: a cron-rooted closure would score fn_agent_context —
// the most-called function in the system — as dead, because the app calls it over PostgREST and
// nothing in the database calls it at all. Where the chain of callers itself dead-ends in code
// only an edge function reaches, the evidence prints the chain instead of asserting a verdict SQL
// cannot reach.
//
// pg_proc holds one row per OVERLOAD (fn_agent_context has two on production), so every count here
// counts DISTINCT proname. A helper counted twice is a reader inflated by 100%.
export default async function ({ req, READERS }) {

  // qd_guard refuses any read carrying a bare write keyword, so the two words that name a write are
  // assembled by the database rather than written in this file.
  const WRITE_KW = `('ins'||'ert|upd'||'ate')`;

  // Every routine that writes this table by a statement in its OWN body, plus every trigger
  // function attached to the table.
  const DIRECT_WRITERS = (t) => `select wp.proname from pg_proc wp join pg_namespace wn on wn.oid = wp.pronamespace
       where wn.nspname = 'public' and wp.prokind in ('f','p')
         and pg_get_functiondef(wp.oid) ~* ('(' || ${WRITE_KW} || ')\\s+(into\\s+)?"?(public"?\\.)?"?${t}\\y')
      union
      select tp.proname from pg_trigger tg
        join pg_class tc on tc.oid = tg.tgrelid
        join pg_namespace tn on tn.oid = tc.relnamespace
        join pg_proc tp on tp.oid = tg.tgfoid
       where tn.nspname = 'public' and tc.relname = '${t}' and not tg.tgisinternal`;

  // ...and everything that writes THROUGH one of those. One hop is enough to catch the measured
  // case (fn_event_consolidate -> fn_task_lesson -> institutional_memory) and stops the remediation
  // pattern of moving the insert into a helper to reclaim reader status.
  const WRITERS_OF = (t) => `(${DIRECT_WRITERS(t)}
      union
      select cp.proname from pg_proc cp join pg_namespace cn on cn.oid = cp.pronamespace
       where cn.nspname = 'public' and cp.prokind in ('f','p')
         and exists (select 1 from (${DIRECT_WRITERS(t)}) dw(proname)
                      where pg_get_functiondef(cp.oid) ~* ('\\y' || dw.proname || '\\s*\\(')))`;

  // Is this routine reachable at all? Called by another routine, or scheduled on an ACTIVE job.
  // `\s*\(` and not a bare mention: a commented-out reference is not a call.
  const REACHABLE = (a) => `(exists (select 1 from pg_proc g join pg_namespace gs on gs.oid = g.pronamespace
          where gs.nspname = 'public' and g.prokind in ('f','p') and g.proname <> ${a}.proname
            and pg_get_functiondef(g.oid) ~* ('\\y' || ${a}.proname || '\\s*\\('))
     or exists (select 1 from cron.job j where j.active and j.command ~* ('\\y' || ${a}.proname || '\\y')))`;

  // Readers of a table: LIVE routines, views and ACTIVE cron jobs that reference it, writers
  // removed. One row per name, so an overloaded reader counts once.
  const RD_PROCS = (t) => `select distinct p.proname from pg_proc p
        join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
         and p.proname not in ${WRITERS_OF(t)}
         and ${REACHABLE('p')}`;
  const RD = (t) => `((select count(*) from (${RD_PROCS(t)}) r)
    + (select count(*) from pg_views v where v.schemaname = 'public' and v.definition ~* '\\y${t}\\y')
    + (select count(*) from cron.job j where j.active and j.command ~* '\\y${t}\\y'))`;
  // The evidence names exactly the population the verdict counted — same filters, same helper.
  const RD_NAMES = (t) => `coalesce((select string_agg(r.proname, '/' order by r.proname)
      from (${RD_PROCS(t)}) r), 'nothing')`;
  // Who calls those readers. Printed, not asserted: it is the number a reader of this scorecard
  // needs in order to disagree with the reader count above it.
  const RD_CALLERS = (t) => `coalesce((select string_agg(x, '; ' order by x) from (
      select r.proname || ' <- ' || coalesce((select string_agg(distinct g.proname, ',')
               from pg_proc g join pg_namespace gs on gs.oid = g.pronamespace
              where gs.nspname = 'public' and g.prokind in ('f','p') and g.proname <> r.proname
                and pg_get_functiondef(g.oid) ~* ('\\y' || r.proname || '\\s*\\(')),
             (select string_agg(j.jobname, ',') from cron.job j
               where j.active and j.command ~* ('\\y' || r.proname || '\\y')), 'nothing') x
        from (${RD_PROCS(t)}) r) s), 'no live reader')`;

  // Callers of a FUNCTION by name. `\s*\(` is a call; a mention in a comment is not.
  const FNS = (t, skip = []) => `(select count(*) from (select distinct p.proname from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
       ${skip.map(s => `and p.proname <> '${s}'`).join(' ')}
       and pg_get_functiondef(p.oid) ~* '\\y${t}\\s*\\(') q)`;
  const CRONS = (t) => `(select count(*) from cron.job j where j.active and j.command ~* '\\y${t}\\y')`;

  // A cron job that is ACTIVE, has SUCCEEDED inside the window, and has not failed since its last
  // success. "A job row is a claim; a succeeded run is the fact" — stated once, applied everywhere
  // a schedule is scored, rather than restated per check and forgotten in two of them.
  const CRON_OK = (rx, days) => `(select count(*) from cron.job j
       where j.command ~* '\\y${rx}\\y' and j.active
         and exists (select 1 from cron.job_run_details d
                      where d.jobid = j.jobid and d.status = 'succeeded'
                        and d.start_time > now() - interval '${days} days')
         and not exists (select 1 from cron.job_run_details d
                          where d.jobid = j.jobid and d.status <> 'succeeded'
                            and d.start_time > (select max(d2.start_time) from cron.job_run_details d2
                                                 where d2.jobid = j.jobid and d2.status = 'succeeded'))) > 0`;

  // Readers of a COLUMN. Proximity, not conjunction: the table and the column have to appear within
  // 250 characters of one another, which a query that filters the table on that column does and a
  // routine that happens to use the word elsewhere does not. Word boundaries on BOTH terms, so
  // agent_memory_id / time_horizon no longer match agent_memory / horizon. Views are held to the
  // same proximity rule as routines.
  const RD_COL_PROCS = (t, c) => `select distinct p.proname from pg_proc p
        join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.prokind in ('f','p')
         and (pg_get_functiondef(p.oid) ~* '\\y${t}\\y[\\s\\S]{0,250}\\y${c}\\y'
           or pg_get_functiondef(p.oid) ~* '\\y${c}\\y[\\s\\S]{0,250}\\y${t}\\y')
         and p.proname not in ${WRITERS_OF(t)}
         and ${REACHABLE('p')}`;
  const RD_COL = (t, c) => `((select count(*) from (${RD_COL_PROCS(t, c)}) r)
    + (select count(*) from pg_views v where v.schemaname = 'public'
        and (v.definition ~* '\\y${t}\\y[\\s\\S]{0,250}\\y${c}\\y'
          or v.definition ~* '\\y${c}\\y[\\s\\S]{0,250}\\y${t}\\y')))`;
  const RD_COL_NAMES = (t, c) => `coalesce((select string_agg(r.proname, '/' order by r.proname)
      from (${RD_COL_PROCS(t, c)}) r), 'nothing')`;

  // Reading a value out of a row without naming the column: the five columns above appeared
  // mid-measurement and could disappear the same way. to_jsonb(row)->>'col' is null both when the
  // column holds null and when it does not exist, which is exactly the claim being tested — the
  // field is not carrying a value — and it cannot raise "column does not exist" mid-run.
  const FIELD = (alias, col) => `to_jsonb(${alias}) ->> '${col}'`;

  // The one employee this file interrogates belongs to exactly ONE operating system, because
  // fn_agent_context resolves org_agents.department -> os_department -> operating_system and stops
  // at the first row. Any "does it reach the prompt" coverage test has to use that OS as its
  // denominator; comparing against all ten scores a ceiling result as a 90% failure.
  const CFO_OS = `(select o.os_key from public.org_agents a
                     join public.os_department d on d.dept_key = a.department
                     join public.operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
                    where a.agent_key = 'cfo' limit 1)`;

  // ---------------------------------------------------------------- COMPONENT 11: KPI ENGINE

  // The head of the KPI chain. os_objective held 50 rows (5 horizons x 10 OSes) whose only
  // reference was v_operating_manual, a view with no readers of its own — the definition of an
  // asset nobody consumes. The test is not "is the table referenced" but "does an objective's own
  // text come back out of the prompt an employee is actually handed".
  //
  // It is a COVERAGE test, not an existence test: every one of the employee's own OS objectives
  // must arrive, so one objective surviving a truncation cap cannot carry the requirement. The
  // predicate is coalesce(active,true) because that is what fn_agent_context filters on.
  //
  // The blank guard is not decoration: position('' in anything) returns 1, so an empty objective
  // scored as "delivered verbatim", and a NULL one returned NULL and was dropped by the WHERE —
  // counted in neither the failing set nor the evidence. Both now fail, which is what an objective
  // with no text is: not delivered.
  await req('comp-1', 'comp-11-objectives', 'Objectives are read by something',
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t),
       mine as (select * from public.os_objective where os_key = ${CFO_OS} and coalesce(active,true))
     select (select count(*) from mine) > 0
        and (select count(*) from mine o, ctx
              where coalesce(o.objective,'') = '' or position(o.objective in ctx.t) = 0) = 0`,
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t),
       mine as (select * from public.os_objective where os_key = ${CFO_OS} and coalesce(active,true))
     select (select count(*) from mine o, ctx
              where coalesce(o.objective,'') <> '' and position(o.objective in ctx.t) > 0)::text
            || ' of ' || (select count(*) from mine)::text
            || ' active objectives of the cfo''s own OS (' || coalesce(${CFO_OS}, '?')
            || ') reach the cfo prompt verbatim, '
            || (select count(*) from mine where coalesce(objective,'') = '')::text
            || ' carry no text at all; the company holds '
            || (select count(*) from public.os_objective where coalesce(active,true))::text
            || ' active across all ten OSes, which no single employee is ever shown'`);

  // Objectives -> KPIs. A KPI without a measure_sql is a sentence, not a measure, so the check
  // fails if any active KPI lacks one rather than passing on a majority. "KPIs exist" is also a
  // per-employee claim: a global count > 0 lets one KPI anywhere in the company stand in for 66
  // employees, so the third clause names the employees who have none.
  await req('comp-1', 'comp-11-kpis', 'KPIs exist and are measurable',
    `select (select count(*) from public.employee_kpi where active) > 0
        and (select count(*) from public.employee_kpi where active and measure_sql is null) = 0
        and (select count(*) from public.org_agents a where a.active
              and not exists (select 1 from public.employee_kpi k
                               where k.agent_key = a.agent_key and k.active)) = 0
        and ${RD('employee_kpi')} > 0`,
    `select (select count(*) from public.employee_kpi where active)::text || ' active KPIs, '
            || (select count(*) from public.employee_kpi where active and measure_sql is not null)::text
            || ' with measure_sql, live non-writing reader(s): ' || ${RD_NAMES('employee_kpi')} || '; '
            || (select count(*) from public.org_agents a where a.active
                 and not exists (select 1 from public.employee_kpi k
                                  where k.agent_key = a.agent_key and k.active))::text
            || ' of ' || (select count(*) from public.org_agents where active)::text
            || ' active employees have no active KPI'`);

  // KPIs -> Actual Values. fn_kpi_scoreboard executes each measure_sql, but a number that is
  // computed and discarded is not an actual value the company holds. What proves it landed is
  // outcome_record rows carrying both the KPI id and the baseline the measure returned, in a table
  // read by routines other than the ones that write it.
  //
  // A row count alone would let one backfilled record score the mechanism forever, so the second
  // clause bounds recency: the weekly scoreboard must have COMPLETED inside the last 14 days — one
  // missed Monday is tolerated, a dead scheduler is not.
  await req('comp-1', 'comp-11-actual-values', 'KPIs -> Actual Values are computed',
    `select (select count(*) from public.outcome_record
              where expected_kpi_id is not null and baseline_value is not null) > 0
        and (select count(*) from public.agent_runs
              where agent = 'kpi_review' and status = 'ok'
                and finished_at > now() - interval '14 days') > 0
        and ${RD('outcome_record')} > 0`,
    `select (select count(*) from public.outcome_record
              where expected_kpi_id is not null and baseline_value is not null)::text
            || ' KPI actuals persisted; last ok scoreboard run '
            || coalesce((select finished_at::date::text || ' ' || counts::text from public.agent_runs
                          where agent = 'kpi_review' and status = 'ok'
                          order by finished_at desc limit 1), 'never')
            || '; outcome_record read, writers excluded, by ' || ${RD_NAMES('outcome_record')}`);

  // Actual Values -> Variance. The scoreboard must return the comparison (attainment + verdict),
  // the comparison must be RECORDED against the task it produced, and the task must be ACTED ON.
  //
  // The third clause is the join: every KPI-missed task carries an outcome_record opened against it
  // with the KPI, the baseline and a due date. That was the whole check, and it measured only that
  // the variance was WRITTEN DOWN — on production 51 of 51 tasks had their record while 30 of them
  // had sat untouched at 'assigned' for nine days, which is not what "acted on" means in any
  // reading of the phrase.
  //
  // Clause 4 is the action bar, and it is deliberately generous and deliberately dated: a KPI-miss
  // task older than 14 days must have reached a terminal state (done, or escalated to someone who
  // can act). The oldest open KPI-miss tasks on production were opened 2026-07-28, so this clause
  // is not binding today and goes red on 2026-08-11 if those 30 are still open. It is stated now,
  // in the run where it is honest, rather than after the date passes.
  await req('comp-1', 'comp-11-variance', 'Variance is computed and acted on',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_kpi_scoreboard'
                and pg_get_function_result(p.oid) ~* 'attainment'
                and pg_get_function_result(p.oid) ~* 'verdict') > 0
        and (select count(*) from public.org_tasks where title ilike 'KPI missed%') > 0
        and (select count(*) from public.org_tasks t
              where t.title ilike 'KPI missed%'
                and not exists (select 1 from public.outcome_record o
                                 where o.subject_type = 'org_task' and o.subject_id = t.id::text
                                   and o.expected_kpi_id is not null and o.baseline_value is not null
                                   and o.due_at is not null)) = 0
        and (select count(*) from public.org_tasks t
              where t.title ilike 'KPI missed%'
                and t.created_at < now() - interval '14 days'
                and t.status not in ('done','escalated')) = 0
        and ${RD('outcome_record')} > 0`,
    `select (select count(*) from public.org_tasks t
              where t.title ilike 'KPI missed%'
                and exists (select 1 from public.outcome_record o
                             where o.subject_type = 'org_task' and o.subject_id = t.id::text
                               and o.expected_kpi_id is not null and o.baseline_value is not null
                               and o.due_at is not null))::text
            || ' of ' || (select count(*) from public.org_tasks where title ilike 'KPI missed%')::text
            || ' KPI-missed tasks carry a measurable outcome record joined to them; task status '
            || coalesce((select string_agg(s || '=' || n::text, '/' order by s) from
                 (select status s, count(*) n from public.org_tasks
                   where title ilike 'KPI missed%' group by 1) q), 'none')
            || '; open past 14 days (must be 0): '
            || (select count(*) from public.org_tasks t
                 where t.title ilike 'KPI missed%' and t.created_at < now() - interval '14 days'
                   and t.status not in ('done','escalated'))::text
            || ', oldest still open '
            || coalesce((select min(created_at)::date::text from public.org_tasks
                          where title ilike 'KPI missed%' and status not in ('done','escalated')), 'none')`);

  // Variance -> Root Cause. Three separate questions, and two of them were broken.
  //
  // Clause 1 was `(count where root_cause <> '') > 0` — nine rows out of a 51-task population made
  // "Variance -> Root Cause is captured structurally" permanently green. It is now the coverage
  // form its two siblings in this file already used: EVERY closed KPI-miss task carries a cause.
  // Open tasks are not counted — a diagnosis that has not been written yet is work in progress, not
  // a missing mechanism — and that is exactly the population the trigger governs.
  //
  // Clause 3 counted ANY routine whose text matched both '\yorg_tasks\y' and '\yroot_cause\y'
  // anywhere in the body, which is the naive conjunction this file's own header forbids for column
  // checks. It uses RD_COL now, so the two names have to be within 250 characters of each other,
  // and the trigger function that stamps the value is excluded as a writer.
  await req('comp-1', 'comp-11-root-cause', 'Variance -> Root Cause is captured structurally',
    `select (select count(*) from public.org_tasks o
              where coalesce(btrim(${FIELD('o', 'root_cause')}),'') <> '') > 0
        and (select count(*) from public.org_tasks o
              where o.title ilike 'KPI missed%' and o.status = 'done'
                and coalesce(btrim(${FIELD('o', 'root_cause')}),'') = '') = 0
        and (select count(*) from pg_trigger t
              join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
              join pg_proc p on p.oid = t.tgfoid
             where n.nspname = 'public' and c.relname = 'org_tasks' and not t.tgisinternal
               and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y') > 0
        and ${RD_COL('org_tasks', 'root_cause')} > 0`,
    `select (select count(*) from public.org_tasks o
              where o.title ilike 'KPI missed%' and o.status = 'done'
                and coalesce(btrim(${FIELD('o', 'root_cause')}),'') <> '')::text
            || ' of ' || (select count(*) from public.org_tasks
                           where title ilike 'KPI missed%' and status = 'done')::text
            || ' CLOSED KPI-miss tasks carry a root cause ('
            || (select count(*) from public.org_tasks o
                 where coalesce(btrim(${FIELD('o', 'root_cause')}),'') <> '')::text
            || ' across all tasks, of ' || (select count(*) from public.org_tasks
                                             where title ilike 'KPI missed%')::text
            || ' KPI-missed in total, ' || (select count(*) from public.org_tasks
                 where title ilike 'KPI missed%' and status <> 'done')::text
            || ' still open and not scored here); the column is read, writers of org_tasks '
            || 'excluded, by ' || ${RD_COL_NAMES('org_tasks', 'root_cause')}`);

  // Root Cause -> Improvement Plan. The plan has to reach the owner, so the test is the owner's
  // prompt, not the column — and "the owner" is every active employee, not one of them, so the
  // population half is a not-exists over org_agents rather than a bare count.
  //
  // The evidence used to END with the literal string "and it is emitted into the prompt", which is
  // clause 3 restated as prose: it printed identically on a MISSING row, pointing the next session
  // at the population count while the prompt was the thing that had broken. It computes it now.
  await req('comp-1', 'comp-11-improvement-plan', 'Improvement Plan reaches the owner',
    `select (select count(*) from public.org_agents where active) > 0
        and (select count(*) from public.org_agents
              where active and coalesce(improvement_plan,'') = '') = 0
        and public.fn_agent_context('cfo', 22000) like '%Your improvement plan%'`,
    `select (select count(*) from public.org_agents where active and coalesce(improvement_plan,'') <> '')::text
            || ' of ' || (select count(*) from public.org_agents where active)::text
            || ' active employees carry an improvement plan; the block reaches the cfo prompt: '
            || (public.fn_agent_context('cfo', 22000) like '%Your improvement plan%')::text`);

  // The KPI Engine's stated schedule. A job row is a claim; a succeeded run is the fact. Both
  // KPI-engine jobs must exist, be active, and have completed at least once.
  //
  // The fourth clause is the non-regression bar and the one that keeps this honest over time: a job
  // whose MOST RECENT outcome is a failure scores MISSING even though an older run succeeded.
  // kpi_review_weekly died on a statement timeout on 3 Aug and has since completed; if next
  // Monday's run dies again this check goes red that morning, which "has ever succeeded" would not.
  await req('comp-1', 'comp-11-schedule', 'KPI Engine runs on its stated schedule',
    `with j as (select * from cron.job
                 where command ~* '\\y(fn_kpi_review|fn_improvement_plan_refresh)\\y')
     select (select count(*) from j) >= 2
        and (select count(*) from j where not j.active) = 0
        and (select count(*) from j where not exists (
              select 1 from cron.job_run_details d
               where d.jobid = j.jobid and d.status = 'succeeded')) = 0
        and (select count(*) from j where exists (
              select 1 from cron.job_run_details d
               where d.jobid = j.jobid and d.status <> 'succeeded'
                 and d.start_time > (select max(d2.start_time) from cron.job_run_details d2
                                      where d2.jobid = j.jobid and d2.status = 'succeeded'))) = 0`,
    `with j as (select * from cron.job
                 where command ~* '\\y(fn_kpi_review|fn_improvement_plan_refresh)\\y')
     select coalesce(string_agg(j.jobname || ' ok=' ||
              (select count(*) from cron.job_run_details d
                where d.jobid = j.jobid and d.status = 'succeeded')::text
              || '/' || (select count(*) from cron.job_run_details d where d.jobid = j.jobid)::text
              || ' last-ok ' || coalesce((select max(d.start_time)::date::text from cron.job_run_details d
                                           where d.jobid = j.jobid and d.status = 'succeeded'), '-')
              || ' last-fail ' || coalesce((select max(d.start_time)::date::text from cron.job_run_details d
                                             where d.jobid = j.jobid and d.status <> 'succeeded'), '-'),
              ', ' order by j.jobname), 'no KPI-engine cron job exists') from j`);

  // ------------------------------------------------------------- COMPONENT 12: MEMORY SYSTEM

  // Short-term memory has to be SEPARABLE from long-term, otherwise there is one undifferentiated
  // store and the distinction the blueprint draws is decorative.
  //
  //   1. every row carries a horizon;
  //   2. the value is not merely the column default — rows exist on both sides of the line;
  //   3. something OTHER than a writer of agent_memory consults it, and that something is alive.
  //
  // Clause 3 is the one this file exists to ask. It uses proximity rather than conjunction because
  // fn_agent_context mentions agent_memory and separately says "horizon" eight times about
  // os_objective; matching both words anywhere would have scored it a reader of a column it never
  // looks at. Measured 6 Aug 2026 this check was MISSING and the finding was real: the only routine
  // that consulted the column was fn_promote_memory_sweep, which also sets it, so the distinction
  // was maintained by its own maintainer and consumed by nobody. fn_promote_memory now refuses to
  // promote a memory that is already long-term, which is the one moment in the system where short
  // and long have to mean different things.
  await req('comp-1', 'comp-12-short-term', 'Short-term memory is distinguishable',
    `select (select count(*) from public.agent_memory) > 0
        and (select count(*) from public.agent_memory m where ${FIELD('m', 'horizon')} is null) = 0
        and (select count(distinct ${FIELD('m', 'horizon')}) from public.agent_memory m) > 1
        and ${RD_COL('agent_memory', 'horizon')} > 0`,
    `select (select count(*) from public.agent_memory m where ${FIELD('m', 'horizon')} is not null)::text
            || ' of ' || (select count(*) from public.agent_memory)::text
            || ' memories carry a horizon ('
            || coalesce((select string_agg(h || '=' || n::text, '/' order by h) from
                 (select coalesce(${FIELD('m', 'horizon')},'null') h, count(*) n
                    from public.agent_memory m group by 1) s), 'none')
            || '); live routines that consult the column, writers of agent_memory excluded: '
            || ${RD_COL_NAMES('agent_memory', 'horizon')}`);

  await req('comp-1', 'comp-12-long-term', 'Long-term memory exists and is read',
    `select (select count(*) from public.org_memory) > 0
        and ${RD('org_memory')} > 0
        and (select count(*) from public.institutional_memory) > 0
        and ${RD('institutional_memory')} > 0`,
    `select (select count(*) from public.org_memory)::text || ' org_memory rows read by '
            || ${RD_NAMES('org_memory')} || '; '
            || (select count(*) from public.institutional_memory)::text
            || ' institutional_memory rows read by ' || ${RD_NAMES('institutional_memory')}`);

  // Lessons must be RETRIEVABLE, not merely stored. "Returns something" is too weak — the function
  // emits a header regardless — so the test is that a lesson's OWN headline comes back out of the
  // retrieval verbatim, and that something CALLS the retrieval (a mention is not a call).
  await req('comp-1', 'comp-12-lessons', 'Lessons Learned are stored and retrieved',
    `select (select count(*) from public.institutional_memory
              where kind in ('lesson','lesson_learned')) > 0
        and (select count(*) from public.institutional_memory m
              where coalesce(m.headline,'') <> ''
                and position(m.headline in public.fn_agent_institutional_memory('ceo', 6)) > 0) > 0
        and ${FNS('fn_agent_institutional_memory')} > 0`,
    `select (select count(*) from public.institutional_memory
              where kind in ('lesson','lesson_learned'))::text || ' lesson row(s); '
            || (select count(*) from public.institutional_memory m
                 where coalesce(m.headline,'') <> ''
                   and position(m.headline in public.fn_agent_institutional_memory('ceo', 6)) > 0)::text
            || ' stored headline(s) come back verbatim in the ceo retrieval, '
            || length(coalesce(public.fn_agent_institutional_memory('ceo', 6), ''))::text || ' chars'`);

  // Best practices are a DISTINCT store, not a subset of lessons — and that word was in the comment
  // and in no clause. `count(os_runbooks) > 0` was equally true when every row in the library had
  // been written out of institutional_memory by fn_sop_update, which is 21 of the 31 rows measured
  // on 6 Aug. Clause 2 asks the question the sentence makes: the library holds standing practice
  // that is NOT lesson-derived.
  //
  // Clause 3 is the one column of the five named in this file's header that this section owns and
  // that no check asserted: os_runbooks.os_key was 0 of 31 while the writer had the value in hand
  // (institutional_memory.os_key) and dropped it into `category` instead. It is asserted over the
  // rows fn_sop_update produces, because those are the rows a writer under this file's control can
  // scope; the ten hand-written incident runbooks are printed, not judged.
  //
  // The reader clause is RD(), so the reader must at least be called by something. The chain it
  // certifies is printed in full by RD_CALLERS: on production it terminates at fn_os_selftest, and
  // the honest reader of os_runbooks is supabase/functions/os_incidents, an edge function that
  // reaches it by RPC. No SQL predicate can see that, and a rule strict enough to fail here would
  // also fail fn_agent_context, which nothing in the database calls either.
  await req('comp-1', 'comp-12-best-practices', 'Best Practices are a distinct, read store',
    `select (select count(*) from public.os_runbooks) > 0
        and (select count(*) from public.os_runbooks where slug not like 'lesson-%') > 0
        and (select count(*) from public.os_runbooks b
              where b.slug like 'lesson-%'
                and not exists (select 1 from public.operating_system o
                                 where o.os_key = ${FIELD('b', 'os_key')})) = 0
        and ${RD('os_runbooks')} > 0`,
    `select (select count(*) from public.os_runbooks)::text || ' runbook(s), '
            || (select count(*) from public.os_runbooks where slug not like 'lesson-%')::text
            || ' written as standing practice and '
            || (select count(*) from public.os_runbooks where slug like 'lesson-%')::text
            || ' derived from graded lessons, of which '
            || (select count(*) from public.os_runbooks b where b.slug like 'lesson-%'
                 and exists (select 1 from public.operating_system o
                              where o.os_key = ${FIELD('b', 'os_key')}))::text
            || ' carry an os_key that resolves to an operating system; read by '
            || ${RD_NAMES('os_runbooks')} || ' (' || ${RD_CALLERS('os_runbooks')} || ')'`);

  await req('comp-1', 'comp-12-historical-decisions', 'Historical Decisions are queryable',
    `select (select count(*) from public.decision_log) > 0
        and ${RD('decision_log')} > 0
        and (select count(*) from public.decision_record) > 0
        and ${RD('decision_record')} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decision_log rows read by '
            || ${RD_NAMES('decision_log')} || '; '
            || (select count(*) from public.decision_record)::text
            || ' decision_record rows read by ' || ${RD_NAMES('decision_record')}`);

  // Failures. The assertion that a 'worse' row must already exist cannot be satisfied today even in
  // principle — fn_outcome_evaluate first grades on 2026-08-11, every outcome_record is pending and
  // the earliest due_at is 2026-08-11 17:25 — and the only way to turn it green is to manufacture a
  // failure that did not happen. So the check asks whether a failure CAN be recorded and whether
  // the recorder is running.
  //
  // What round 2 refuted was the SHAPE of that answer, not its content: the previous form was
  // `(a 'worse' row exists) OR (the grader is wired, scheduled, succeeded in 48h, has a gradeable
  // cohort and nothing overdue)`, so the first 'worse' row ever written would short-circuit every
  // liveness clause behind it, permanently. The strict half is now a CONJUNCT — the grader must be
  // alive and nothing may be overdue-and-ungraded whatever the history holds — and the OR is
  // reduced to the one thing that legitimately has two forms: either failures have actually been
  // graded recently, or a real cohort is waiting for the window to open.
  //
  // Overdue is measured with 24 hours of slack because the grader is a DAILY job: a record due at
  // 10:00 is not evidence of a stalled grader until the next 03:30 sweep has been and gone.
  await req('comp-1', 'comp-12-failures', 'Failures are recorded as failures',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_outcome_evaluate'
                and pg_get_functiondef(p.oid) ~* '''worse'''
                and pg_get_functiondef(p.oid) ~* '\\yinstitutional_memory\\y'
                and pg_get_functiondef(p.oid) ~* '\\youtcome_record\\y') > 0
        and ${CRON_OK('fn_outcome_evaluate', 2)}
        and (select count(*) from public.outcome_record
              where verdict = 'pending' and due_at <= now() - interval '24 hours') = 0
        and (((select count(*) from public.outcome_record
                where verdict = 'worse' and coalesce(observed_at, created_at) > now() - interval '90 days')
            + (select count(*) from public.institutional_memory
                where outcome = 'worse' and created_at > now() - interval '90 days')) > 0
          or (select count(*) from public.outcome_record
               where verdict = 'pending' and due_at is not null
                 and expected_kpi_id is not null and baseline_value is not null) > 0)
        and ${RD('outcome_record')} > 0`,
    `select 'graded worse in 90d: outcome_record '
            || (select count(*) from public.outcome_record
                 where verdict = 'worse' and coalesce(observed_at, created_at) > now() - interval '90 days')::text
            || ', institutional_memory '
            || (select count(*) from public.institutional_memory
                 where outcome = 'worse' and created_at > now() - interval '90 days')::text
            || '; ' || (select count(*) from public.outcome_record
                         where verdict = 'pending' and due_at is not null
                           and expected_kpi_id is not null and baseline_value is not null)::text
            || ' gradeable pending, first window '
            || coalesce((select min(due_at)::date::text from public.outcome_record where verdict = 'pending'), 'none')
            || ', overdue-and-ungraded by more than a day '
            || (select count(*) from public.outcome_record
                 where verdict = 'pending' and due_at <= now() - interval '24 hours')::text
            || ', grader active and succeeded within 48h with no failure since: '
            || (${CRON_OK('fn_outcome_evaluate', 2)})::text
            || ', last ok '
            || coalesce((select max(d.start_time)::text from cron.job j
                          join cron.job_run_details d on d.jobid = j.jobid
                         where j.command ~* '\\yfn_outcome_evaluate\\y' and d.status = 'succeeded'), 'never')`);

  // Successes. The comment above these two used to claim they were symmetric with failures and they
  // were not: failures demanded an active grader that had succeeded inside 48 hours, successes
  // demanded nothing about anything running — three bare '> 0' clauses that 81 historical rows
  // satisfied permanently. Every grader in the company could stop tonight and this stayed MET.
  //
  // Symmetric now: the same grader-liveness conjunct, and a recency bound on the successes
  // themselves. The 0.6 clause stays and is the one that stops this passing on unreadable records —
  // fn_agent_institutional_memory retrieves only `coalesce(confidence,1) >= 0.6`, so a success
  // recorded below the floor is a success recorded where nobody will read it.
  //
  // ROUND 3, and the reason this was a SYSTEM defect rather than an instrument one: every clause
  // above was carried by labels nothing had graded. fn_task_lesson's p_outcome='event_closed'
  // branch set 'success' with confidence 0.6 for EVERY closed event-bus task — 58 of the 81 rows in
  // window — so the requirement was MET on a writer that could not record anything else, with the
  // grader's heartbeat standing in as proof. That branch now grades against the row (the reviewer's
  // verdict where there was one, the executor's recorded error, and 'no_change' at 0.4 when the
  // task closed having recorded nothing), and institutional_memory carries 7 'worse' rows inside
  // the window where it had never carried one.
  //
  // Clause 4 is what the finding needs and no more: at least one success in the window must be
  // attested by a REVIEW rather than auto-stamped by the bus. It is not "more than one distinct
  // outcome" — a month in which every task genuinely succeeded is a healthy month, and a check no
  // healthy system can satisfy is the over-hardening this file has to refuse.
  await req('comp-1', 'comp-12-successes', 'Successes are recorded as successes',
    `select ((select count(*) from public.outcome_record where verdict = 'improved')
           + (select count(*) from public.institutional_memory
               where outcome in ('success','success_over_dissent','improved'))) > 0
        and (select count(*) from public.institutional_memory
              where outcome in ('success','success_over_dissent','improved')
                and coalesce(confidence, 1) >= 0.6
                and created_at > now() - interval '30 days') > 0
        and (select count(*) from public.institutional_memory
              where outcome in ('success','success_over_dissent','improved')
                and coalesce(confidence, 1) >= 0.6
                and created_at > now() - interval '30 days'
                and evidence_ref like 'review_chain:%') > 0
        and ${CRON_OK('fn_outcome_evaluate', 2)}
        and ${RD('institutional_memory')} > 0`,
    `select 'graded better: outcome_record improved '
            || (select count(*) from public.outcome_record where verdict = 'improved')::text
            || ', institutional_memory success/success_over_dissent/improved '
            || (select count(*) from public.institutional_memory
                 where outcome in ('success','success_over_dissent','improved'))::text
            || ' of which ' || (select count(*) from public.institutional_memory
                 where outcome in ('success','success_over_dissent','improved')
                   and coalesce(confidence, 1) >= 0.6
                   and created_at > now() - interval '30 days')::text
            || ' were written in the last 30 days and clear the 0.6 retrieval floor, '
            || (select count(*) from public.institutional_memory
                 where outcome in ('success','success_over_dissent','improved')
                   and coalesce(confidence, 1) >= 0.6
                   and created_at > now() - interval '30 days'
                   and evidence_ref like 'review_chain:%')::text
            || ' of those attested by a review rather than auto-stamped by the bus; the same store '
            || 'holds ' || (select count(*) from public.institutional_memory
                 where outcome = 'worse' and created_at > now() - interval '30 days')::text
            || ' graded worse and ' || (select count(*) from public.institutional_memory
                 where outcome = 'no_change' and created_at > now() - interval '30 days')::text
            || ' no_change in the same window, so the recorder discriminates; grader alive: '
            || (${CRON_OK('fn_outcome_evaluate', 2)})::text
            || '; read, writers excluded, by ' || ${RD_NAMES('institutional_memory')}`);

  // Promotion of short-term to long-term. Both halves are required and neither is a row count on
  // its own: fn_promote_memory must be CALLED by something, promotions must have happened inside a
  // bounded window (a weekly sweep that last ran in June is not a promotion path), and the promoted
  // memory must have LANDED somewhere long-term that a non-promoter reads — memory_promotions is a
  // ledger of the act, kb_chunks is the destination, and a ledger row whose kb_chunk_id is null
  // records a promotion that went nowhere.
  await req('comp-1', 'comp-12-promotion', 'Short-term memory is promoted to long-term',
    `select (${FNS('fn_promote_memory')} + ${CRONS('fn_promote_memory')}) > 0
        and (select count(*) from public.memory_promotions
              where promoted_at > now() - interval '30 days') > 0
        and (select count(*) from public.memory_promotions where kb_chunk_id is null) = 0
        and (select count(*) from public.kb_chunks where source_kind = 'memory') > 0
        and ${RD('kb_chunks')} > 0`,
    `select 'fn_promote_memory called by ' || (${FNS('fn_promote_memory')} + ${CRONS('fn_promote_memory')})::text
            || ' routine(s)/job(s); memory_promotions holds '
            || (select count(*) from public.memory_promotions)::text || ' row(s), '
            || (select count(*) from public.memory_promotions where promoted_at > now() - interval '30 days')::text
            || ' in the last 30 days, ' || (select count(*) from public.memory_promotions where kb_chunk_id is null)::text
            || ' with no destination chunk; kb_chunks from memory '
            || (select count(*) from public.kb_chunks where source_kind = 'memory')::text
            || ', read by ' || ${RD('kb_chunks')}::text || ' live non-writer(s)'`);

  // ------------------------------------------------------------- COMPONENT 13: LEARNING LOOP

  // Step 1, Task. "Every completed task enters the chain" is a coverage claim measured as coverage.
  //
  // The window used to be `since the first review_chain row`, which is the mechanism under test
  // defining its own denominator: on 6 Aug that admitted 14 tasks and excluded 95, so the
  // requirement was scored on 13% of its own population, and truncating review_chain and inserting
  // one row would have reset the denominator to 1 and scored it green. The window is now a fixed
  // seven days, which nothing in the chain controls.
  //
  // The population is still restricted to tasks fn_task_review will accept — it returns
  // 'no_deliverable' and writes nothing when result carries no deliverable — and org_tasks has no
  // completion timestamp (its columns end at updated_at and last_run_at), so a task finished earlier
  // but touched inside the window counts. The evidence prints the all-time backlog beside it.
  await req('comp-1', 'comp-13-task', 'Every completed task enters the chain',
    `with d as (select o.id from public.org_tasks o
                 where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> ''
                   and o.updated_at > now() - interval '7 days')
     select (select count(*) from d) > 0
        and (select count(*) from d where not exists (
              select 1 from public.review_chain r
               where r.subject_type = 'org_task' and r.subject_id = d.id::text)) = 0`,
    `with d as (select o.id from public.org_tasks o
                 where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> ''
                   and o.updated_at > now() - interval '7 days'),
      a as (select o.id from public.org_tasks o
             where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> '')
     select (select count(*) from d where exists (
              select 1 from public.review_chain r
               where r.subject_type = 'org_task' and r.subject_id = d.id::text))::text
            || ' of ' || (select count(*) from d)::text
            || ' tasks completed with a deliverable in the last 7 days have a review_chain row; '
            || 'all time ' || (select count(*) from a where exists (
                 select 1 from public.review_chain r
                  where r.subject_type = 'org_task' and r.subject_id = a.id::text))::text
            || ' of ' || (select count(*) from a)::text
            || '; first chain row ' || coalesce((select min(created_at)::text from public.review_chain
                                                  where subject_type = 'org_task'), 'never')`);

  // Step 2, Outcome. A grade needs a named grader and a verdict, and it has to be recent enough to
  // be a running loop rather than a historical one. The reader conjunct excludes review_chain's
  // writers structurally — fn_task_review inserts into it in three places and was previously
  // counted as one of its readers — and the evidence reports the SAME seven-day window the verdict
  // uses, so the number a reader would use to disagree is the number the check used.
  await req('comp-1', 'comp-13-outcome', 'Task -> Outcome is graded by a reviewer',
    `select (select count(*) from public.review_chain
              where subject_type = 'org_task' and reviewer_agent is not null
                and decision is not null and created_at > now() - interval '7 days') > 0
        and ${RD('review_chain')} > 0`,
    `select coalesce((select string_agg(x, ', ' order by x) from (
              select decision || '=' || count(*)::text x from public.review_chain
               where subject_type = 'org_task' and reviewer_agent is not null
                 and created_at > now() - interval '7 days' group by decision) s),
              'no graded reviews in the last 7 days')
            || '; last ' || coalesce((select max(created_at)::text from public.review_chain
                                       where subject_type = 'org_task'), 'never')
            || '; read, writers excluded, by ' || ${RD_NAMES('review_chain')}`);

  // Step 3, Performance. agent_reputation is 66 scored employees whose only reference for weeks was
  // fn_reputation_recompute, which wrote them. Three clauses, because a scoreboard can fail in
  // three ways: nobody reads it, the reader itself is dead code, or the scores do not discriminate.
  // The last one matters — with four of five sub-scores null every employee scored an identical
  // 42.5, and a consumer of a constant learns nothing from it. The reader-is-alive test that was
  // written out by hand here is now RD()'s behaviour for every table in this file.
  await req('comp-1', 'comp-13-performance', 'Outcome -> Performance is consumed',
    `select (select count(*) from public.agent_reputation) > 0
        and (select count(distinct score) from public.agent_reputation) > 1
        and ${RD('agent_reputation')} > 0`,
    `select (select count(*) from public.agent_reputation)::text || ' scored employees over '
            || (select count(distinct score) from public.agent_reputation)::text
            || ' distinct scores (' || coalesce((select string_agg(t || '=' || n::text, '/' order by t) from
                 (select tier t, count(*) n from public.agent_reputation group by 1) s), '-')
            || '); consumed, writer excluded, by ' || ${RD_NAMES('agent_reputation')}
            || ' (' || ${RD_CALLERS('agent_reputation')} || ')'`);

  // Step 4, Lessons. The link has to be automatic, so the reviewer function itself must invoke the
  // lesson writer — and the store must show lessons that CAME FROM that path.
  //
  // "Came from" was a join on subject_id alone: a lesson counted if ANY review_chain row existed for
  // the same task, in either order, written by anyone. institutional_memory has five writers, so an
  // unrelated writer's lesson about a task that happened to be reviewed satisfied it. The link is
  // now the one fn_task_lesson actually writes — evidence_ref = 'review_chain:org_task:<id>' — plus
  // the ordering the word "automatic" implies: the review has to precede the lesson it produced.
  // Measured 6 Aug: 12 of the 70 org_task lessons in the window carry it, and the other 58 carry
  // 'event_delivery:...' — they came from the event bus, not from this loop, and the old join
  // counted them.
  //
  // ROUND 3: that left the verdict a bare `> 0` on a requirement whose own title is "automatic",
  // and one lesson a week kept it green. fn_task_review calls fn_task_lesson inside
  // `begin ... exception when others then null`, so a lesson that fails to write is lost silently
  // and PERMANENTLY — nothing ever came back for it. Measured before the repair: 4 of the 18
  // org_tasks reviewed in the window (49, 50, 51, 157) carried no lesson at all, and no mechanism
  // existed that would ever produce one. So this is now the per-row NOT EXISTS form comp-13-task
  // uses two checks earlier, over the REVIEWED population, and fn_learning_loop_sweep (cron
  // learning_loop_sweep_hourly) is the retry that makes it satisfiable: it re-writes any lesson
  // that never landed, from the reviewer's own verdict in review_chain.
  //
  // The population is the stages fn_review_submit/fn_task_review write — published, cos_review,
  // dept_review. stage='approval' is NOT in it, and that is a decision rather than an oversight:
  // those 162 rows are fn_task_approve routing a task ONTO an approval path before anyone works it
  // (it sets status='assigned'), not a verdict on completed work, and fn_task_approve does not call
  // the lesson writer. Demanding a lesson for a task nobody has done yet is a requirement no future
  // work can satisfy. The evidence prints that excluded count so the choice is auditable.
  await req('comp-1', 'comp-13-lessons', 'Performance -> Lessons is automatic',
    `with rev as (select distinct c.subject_id sid from public.review_chain c
                   where c.subject_type = 'org_task'
                     and c.stage in ('published','cos_review','dept_review')
                     and c.created_at > now() - interval '7 days'
                     and exists (select 1 from public.org_tasks o where o.id::text = c.subject_id))
     select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_task_review'
                and pg_get_functiondef(p.oid) ~* '\\yfn_task_lesson\\s*\\(') > 0
        and (select count(*) from rev) > 0
        and (select count(*) from rev v where not exists (
              select 1 from public.institutional_memory m
               where m.subject_type = 'org_task' and m.subject_id = v.sid
                 and m.kind in ('lesson','lesson_learned')
                 and m.evidence_ref = 'review_chain:org_task:' || m.subject_id
                 and exists (select 1 from public.review_chain r
                              where r.subject_type = 'org_task' and r.subject_id = m.subject_id
                                and r.created_at <= m.created_at))) = 0`,
    `with rev as (select distinct c.subject_id sid from public.review_chain c
                   where c.subject_type = 'org_task'
                     and c.stage in ('published','cos_review','dept_review')
                     and c.created_at > now() - interval '7 days'
                     and exists (select 1 from public.org_tasks o where o.id::text = c.subject_id))
     select (select count(*) from rev v where exists (
              select 1 from public.institutional_memory m
               where m.subject_type = 'org_task' and m.subject_id = v.sid
                 and m.kind in ('lesson','lesson_learned')
                 and m.evidence_ref = 'review_chain:org_task:' || m.subject_id
                 and exists (select 1 from public.review_chain r
                              where r.subject_type = 'org_task' and r.subject_id = m.subject_id
                                and r.created_at <= m.created_at)))::text
            || ' of ' || (select count(*) from rev)::text
            || ' task(s) reviewed in the last 7 days carry a lesson citing that review and written '
            || 'after it; ' || (select count(distinct c.subject_id) from public.review_chain c
                 where c.subject_type = 'org_task' and c.stage = 'approval'
                   and c.created_at > now() - interval '7 days')::text
            || ' further task(s) were only routed onto an approval path and are outside this '
            || 'population; the window holds '
            || (select count(*) from public.institutional_memory
                 where created_at > now() - interval '7 days'
                   and subject_type = 'org_task' and kind in ('lesson','lesson_learned'))::text
            || ' org_task lessons in all (sources: '
            || coalesce((select string_agg(e || '=' || n::text, '/' order by e) from
                 (select coalesce(split_part(evidence_ref, ':', 1), '-') e, count(*) n
                    from public.institutional_memory
                   where created_at > now() - interval '7 days'
                     and subject_type = 'org_task' and kind in ('lesson','lesson_learned')
                   group by 1) q), 'none')
            || '); last ' || coalesce((select max(created_at)::text from public.institutional_memory), 'never')`);

  // Step 5, Knowledge Update. The only proof that a lesson reached an agent is the agent's own
  // context. fn_agent_context truncates LAYER 4 to 3,500 chars, so this is a genuine reach test and
  // not a restatement of "the function mentions the table".
  await req('comp-1', 'comp-13-knowledge-update', 'Lessons -> Knowledge Update reaches agents',
    `select public.fn_agent_context('ceo', 22000) like '%## lesson (%'
        and (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_agent_context'
                and pg_get_functiondef(p.oid) ~* '\\yfn_agent_institutional_memory\\s*\\(') > 0`,
    `select 'lesson block in ceo prompt: '
            || (public.fn_agent_context('ceo', 22000) like '%## lesson (%')::text
            || '; retrieval block is ' || length(coalesce(public.fn_agent_institutional_memory('ceo', 6), ''))::text
            || ' chars before the 3500-char LAYER 4 cap'`);

  // Step 6, SOP Update. fn_sop_update writes runbooks slugged 'lesson-<id>' from graded
  // institutional memory.
  //
  // Clause 2 was `a cron.job row exists with active = true` — a flag, with no run history at all,
  // on the one check in this file whose sibling states the house rule ("a job row is a claim; a
  // succeeded run is the fact"). Every future weekly run could die and this stayed MET. It is
  // CRON_OK now: active, succeeded inside 14 days — one missed Monday tolerated on a weekly job —
  // and no failure since that success.
  //
  // Clause 3 is what stops a hand-seeded runbook scoring the writer: every lesson-<id> slug must
  // resolve to an institutional_memory row that still exists. os_runbooks carries no timestamp
  // column, so derivation is the only available proof that these rows were produced rather than
  // placed. The evidence used to ASSERT that clause in prose ("all of which resolve back to an
  // institutional_memory row") — it printed on MISSING rows too, so the number that refutes the
  // verdict was the one number the evidence would not print. It counts the orphans now.
  await req('comp-1', 'comp-13-sop-update', 'Knowledge Update -> SOP Update writes runbooks',
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%') > 0
        and ${CRON_OK('fn_sop_update', 14)}
        and (select count(*) from public.os_runbooks b
              where b.slug like 'lesson-%'
                and not exists (select 1 from public.institutional_memory m
                                 where 'lesson-' || m.id = b.slug)) = 0`,
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%')::text
            || ' lesson runbook(s), of which '
            || (select count(*) from public.os_runbooks b
                 where b.slug like 'lesson-%'
                   and not exists (select 1 from public.institutional_memory m
                                    where 'lesson-' || m.id = b.slug))::text
            || ' no longer resolve to an institutional_memory row; writer active and succeeded '
            || 'within 14 days with no failure since: ' || (${CRON_OK('fn_sop_update', 14)})::text
            || ', last ok ' || coalesce((select max(d.start_time)::date::text from cron.job j
                                          join cron.job_run_details d on d.jobid = j.jobid
                                         where j.command ~* '\\yfn_sop_update\\y'
                                           and d.status = 'succeeded'), 'never')
            || '; graded rows the deployed filter matches: '
            || (select count(*) from public.institutional_memory
                 where outcome in ('worse','improved','success','success_over_dissent'))::text
            || ' of ' || (select count(*) from public.institutional_memory)::text
            || ', unconverted backlog '
            || (select count(*) from public.institutional_memory m
                 where m.outcome in ('worse','improved','success','success_over_dissent')
                   and not exists (select 1 from public.os_runbooks b where b.slug = 'lesson-'||m.id))::text
            || ' awaiting the next weekly run'`);
}
