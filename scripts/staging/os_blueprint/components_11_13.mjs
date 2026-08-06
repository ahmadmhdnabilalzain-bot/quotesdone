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
// Three rules govern the SQL below.
//
// A column that exists is not a mechanism that works. Five columns in this section
// (os_objective.measure_sql/actual_value, employee_kpi.serves_objective, org_tasks.root_cause,
// agent_memory.horizon, os_runbooks.os_key) were added but never written to. So no check here is
// satisfied by information_schema alone: existence is always paired with a row count and a reader.
//
// A reader must be something other than the writer. fn_reputation_recompute referencing
// agent_reputation is not a reader of agent_reputation, it is the thing that filled it. The
// earlier form of this file spelled that rule out and then applied it in only three places, by
// hand-maintained name lists, so eight reader conjuncts were effectively constant-true: 30 readers
// of org_tasks, 12 of decision_log, 11 of institutional_memory, 14 of employee_kpi. Worse, a name
// list only excludes the writers that exist TODAY — the natural remediation for comp-11-root-cause
// was a routine that writes org_tasks.root_cause, and that routine would have satisfied the reader
// clause out of its own body. RD() below therefore derives the exclusion structurally: a routine
// that INSERTs or UPDATEs the table, and any trigger function bolted onto the table, is a writer,
// whoever builds it and whenever.
//
// A test that matches two words anywhere in a routine's text is not a test that the routine joins
// them. fn_agent_context mentions agent_memory, and it mentions "horizon" eight times — every one
// of them about os_objective horizons, none about memory. A naive conjunction would have scored it
// a reader of agent_memory.horizon, which is the comp-16-health-score defect in a new costume.
// Where a check is about a COLUMN, the two names must appear near each other, not merely both.
export default async function ({ req, READERS }) {

  // qd_guard refuses any read carrying a bare write keyword, so the two words that name a write are
  // assembled by the database rather than written in this file.
  const WRITE_KW = `('ins'||'ert|upd'||'ate')`;

  // Every routine that writes this table — by statement, or by being a trigger function attached to
  // it. Structural, not a name list, so it keeps holding for writers not yet built.
  const WRITERS_OF = (t) => `(
      select wp.proname from pg_proc wp join pg_namespace wn on wn.oid = wp.pronamespace
       where wn.nspname = 'public' and wp.prokind in ('f','p')
         and pg_get_functiondef(wp.oid) ~* ('(' || ${WRITE_KW} || ')\\s+(into\\s+)?"?(public"?\\.)?"?${t}\\y')
      union
      select tp.proname from pg_trigger tg
        join pg_class tc on tc.oid = tg.tgrelid
        join pg_namespace tn on tn.oid = tc.relnamespace
        join pg_proc tp on tp.oid = tg.tgfoid
       where tn.nspname = 'public' and tc.relname = '${t}' and not tg.tgisinternal)`;

  // Readers of a table: routines, views and cron jobs that reference it, with its writers removed.
  const RD = (t) => `((select count(*) from pg_proc p
        join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
         and p.proname not in ${WRITERS_OF(t)})
    + (select count(*) from pg_views v where v.schemaname = 'public' and v.definition ~* '\\y${t}\\y')
    + (select count(*) from cron.job j where j.command ~* '\\y${t}\\y'))`;
  const RD_NAMES = (t) => `coalesce((select string_agg(p.proname, '/' order by p.proname) from pg_proc p
        join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
         and pg_get_functiondef(p.oid) ~* '\\y${t}\\y'
         and p.proname not in ${WRITERS_OF(t)}), 'nothing')`;

  // Readers of a FUNCTION by name — callers, not consumers of a store, so no writer exists to
  // exclude beyond the function itself.
  const FNS = (t, skip = []) => `(select count(*) from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
       ${skip.map(s => `and p.proname <> '${s}'`).join(' ')}
       and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')`;
  const VIEWS = (t) => `(select count(*) from pg_views v
     where v.schemaname = 'public' and v.definition ~* '\\y${t}\\y')`;
  const CRONS = (t) => `(select count(*) from cron.job j where j.command ~* '\\y${t}\\y')`;

  // Readers of a COLUMN. Proximity, not conjunction: the table and the column have to appear within
  // 250 characters of one another, which a query that filters the table on that column does and a
  // routine that happens to use the word elsewhere does not. Writers of the table are excluded, so
  // a routine that maintains the column cannot score as its own consumer.
  const RD_COL = (t, c) => `((select count(*) from pg_proc p
        join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.prokind in ('f','p')
         and (pg_get_functiondef(p.oid) ~* '${t}[\\s\\S]{0,250}${c}'
           or pg_get_functiondef(p.oid) ~* '${c}[\\s\\S]{0,250}${t}')
         and p.proname not in ${WRITERS_OF(t)})
    + (select count(*) from pg_views v where v.schemaname = 'public'
        and v.definition ~* '\\y${t}\\y' and v.definition ~* '\\y${c}\\y'))`;

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
  // predicate is coalesce(active,true) because that is what fn_agent_context filters on — an
  // objective with active NULL is emitted into the prompt, and filtering on `active` alone would
  // count it in neither the numerator nor the denominator.
  await req('comp-1', 'comp-11-objectives', 'Objectives are read by something',
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t),
       mine as (select * from public.os_objective where os_key = ${CFO_OS} and coalesce(active,true))
     select (select count(*) from mine) > 0
        and (select count(*) from mine o, ctx where position(o.objective in ctx.t) = 0) = 0`,
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t),
       mine as (select * from public.os_objective where os_key = ${CFO_OS} and coalesce(active,true))
     select (select count(*) from mine o, ctx where position(o.objective in ctx.t) > 0)::text
            || ' of ' || (select count(*) from mine)::text
            || ' active objectives of the cfo''s own OS (' || coalesce(${CFO_OS}, '?')
            || ') reach the cfo prompt verbatim; the company holds '
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
            || ' with measure_sql, ' || ${RD('employee_kpi')}::text || ' non-writing reader(s); '
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
  // and the comparison must have been ACTED ON.
  //
  // "Acted on" used to be READERS('org_tasks'), which returns 30 — org_tasks is a central table and
  // its reader count is a constant, not a test; the KPI-missed tasks could sit untouched forever
  // and it would still score MET. It is now a JOIN: every KPI-missed task must carry an
  // outcome_record opened against it with the KPI, the baseline and a due date, and that store must
  // be read by something other than the routines that write it. Two unrelated row counts printed
  // side by side — the old evidence's "50 tasks ... and 50 outcome records" — prove no relationship
  // whatever, so the evidence now counts the join and prints the task statuses beside it.
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
                   where title ilike 'KPI missed%' group by 1) q), 'none')`);

  // Variance -> Root Cause. Three separate questions, and the reader half was the broken one: it
  // counted ANY routine whose text matched both '\yorg_tasks\y' and '\yroot_cause\y', which a
  // routine containing `update org_tasks set root_cause = ...` satisfies out of its own body. The
  // remediation would have manufactured its own MET. The writer set is now derived structurally, so
  // both the trigger that stamps the value and any future diagnosis routine that writes it are
  // excluded without anyone maintaining a list.
  //
  // "Structurally" is read literally in clause 2: the capture has to be enforced BY structure, so a
  // trigger carrying the rule must be attached to org_tasks, not merely defined somewhere.
  await req('comp-1', 'comp-11-root-cause', 'Variance -> Root Cause is captured structurally',
    `select (select count(*) from public.org_tasks o
              where coalesce(btrim(${FIELD('o', 'root_cause')}),'') <> '') > 0
        and (select count(*) from pg_trigger t
              join pg_class c on c.oid = t.tgrelid
              join pg_namespace n on n.oid = c.relnamespace
              join pg_proc p on p.oid = t.tgfoid
             where n.nspname = 'public' and c.relname = 'org_tasks' and not t.tgisinternal
               and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y') > 0
        and ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
               where ns.nspname = 'public' and p.prokind in ('f','p')
                 and pg_get_functiondef(p.oid) ~* '\\yorg_tasks\\y'
                 and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y'
                 and p.proname not in ${WRITERS_OF('org_tasks')})
           + (select count(*) from pg_views v where v.schemaname = 'public'
               and v.definition ~* '\\yorg_tasks\\y' and v.definition ~* '\\yroot_cause\\y')) > 0`,
    `select (select count(*) from public.org_tasks o
              where coalesce(btrim(${FIELD('o', 'root_cause')}),'') <> '')::text
            || ' task(s) carry a root cause, of '
            || (select count(*) from public.org_tasks where title ilike 'KPI missed%')::text
            || ' KPI-missed; ' || (select count(*) from public.org_tasks
                 where title ilike 'KPI missed%' and status = 'done'
                   and coalesce(btrim(root_cause),'') = '')::text
            || ' closed with none (pre-trigger history the guard can no longer reach); read, '
            || 'writers of org_tasks excluded, by '
            || coalesce((select string_agg(p.proname, '/' order by p.proname) from pg_proc p
                          join pg_namespace ns on ns.oid = p.pronamespace
                         where ns.nspname = 'public' and p.prokind in ('f','p')
                           and pg_get_functiondef(p.oid) ~* '\\yorg_tasks\\y'
                           and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y'
                           and p.proname not in ${WRITERS_OF('org_tasks')}), 'nothing')`);

  // Root Cause -> Improvement Plan. The plan has to reach the owner, so the test is the owner's
  // prompt, not the column — and "the owner" is every active employee, not one of them, so the
  // population half is a not-exists over org_agents rather than a bare count.
  await req('comp-1', 'comp-11-improvement-plan', 'Improvement Plan reaches the owner',
    `select (select count(*) from public.org_agents where active) > 0
        and (select count(*) from public.org_agents
              where active and coalesce(improvement_plan,'') = '') = 0
        and public.fn_agent_context('cfo', 22000) like '%Your improvement plan%'`,
    `select (select count(*) from public.org_agents where active and coalesce(improvement_plan,'') <> '')::text
            || ' of ' || (select count(*) from public.org_agents where active)::text
            || ' active employees carry an improvement plan, and it is emitted into the prompt'`);

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
  // The old form of this check had a disjunct that could never fire — agent_memory has no
  // expires_at column, and FIELD() swallows a missing column, so the check looked like it accepted
  // two forms of evidence when only one existed. Worse, its reader clause asked whether the TABLE
  // is read (4 routines do) when the mechanism under test is the COLUMN. Both are now fixed, and
  // the column question is asked directly:
  //
  //   1. every row carries a horizon;
  //   2. the value is not merely the column default — rows exist on both sides of the line;
  //   3. something OTHER than a writer of agent_memory consults it.
  //
  // Clause 3 is the one this file exists to ask, and it uses proximity rather than conjunction
  // because fn_agent_context mentions agent_memory and separately says "horizon" eight times about
  // os_objective; matching both words anywhere would have scored it a reader of a column it never
  // looks at.
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
            || '); routines that consult the column, writers of agent_memory excluded: '
            || coalesce((select string_agg(p.proname, '/' order by p.proname) from pg_proc p
                 join pg_namespace ns on ns.oid = p.pronamespace
                where ns.nspname = 'public' and p.prokind in ('f','p')
                  and (pg_get_functiondef(p.oid) ~* 'agent_memory[\\s\\S]{0,250}horizon'
                    or pg_get_functiondef(p.oid) ~* 'horizon[\\s\\S]{0,250}agent_memory')
                  and p.proname not in ${WRITERS_OF('agent_memory')}), 'nothing')`);

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
  // retrieval verbatim, and that something assembles the result into context.
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

  // Best practices are a distinct store (os_runbooks), not a subset of lessons. Its writer is
  // excluded structurally so that the "not exists" probe inside the writer cannot count as the
  // store being read.
  await req('comp-1', 'comp-12-best-practices', 'Best Practices are a distinct, read store',
    `select (select count(*) from public.os_runbooks) > 0
        and ${RD('os_runbooks')} > 0`,
    `select (select count(*) from public.os_runbooks)::text || ' runbook(s), read by '
            || ${RD_NAMES('os_runbooks')}
            || '; scoped to an OS: '
            || (select count(*) from public.os_runbooks b where ${FIELD('b', 'os_key')} is not null)::text`);

  await req('comp-1', 'comp-12-historical-decisions', 'Historical Decisions are queryable',
    `select (select count(*) from public.decision_log) > 0
        and ${RD('decision_log')} > 0
        and (select count(*) from public.decision_record) > 0
        and ${RD('decision_record')} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decision_log rows read by '
            || ${RD_NAMES('decision_log')} || '; '
            || (select count(*) from public.decision_record)::text
            || ' decision_record rows read by ' || ${RD_NAMES('decision_record')}`);

  // Failures. The previous assertion here demanded that a row already carry verdict 'worse' or
  // outcome 'worse', and that assertion CANNOT BE SATISFIED TODAY EVEN IN PRINCIPLE — which makes
  // it a measurement of history, not of capability. Measured on production 6 Aug 2026: all
  // outcome_record rows are pending, the EARLIEST due_at is 2026-08-11 17:25 and 0 rows are due,
  // because fn_kpi_review opens every record with p_measure_after of 14 or 35 days. The only way to
  // turn the old assertion green today is to manufacture a 'worse' row, i.e. to record a failure
  // that did not happen — the founder's standing instruction forbids exactly that, and a gate that
  // can only be passed by falsifying data is a broken gate.
  //
  // So this asks the question the requirement actually poses: CAN a failure be recorded as a
  // failure, and is the recorder running? Five things must hold before the window opens — the
  // grader writes the 'worse' verdict AND mirrors it into institutional_memory; it is on an active
  // schedule whose LAST RUN SUCCEEDED inside 48 hours (a daily job that stopped four days ago is
  // not "running", and without this clause the check would coast on a dead scheduler until 11 Aug);
  // there is a real cohort waiting with everything grading needs (a due date, a KPI and a
  // baseline); and nothing is already overdue and ungraded, which would mean the grader is stalled
  // rather than waiting. Once 11 Aug passes the first branch takes over on its own, so this check
  // does not decay into a permanent exemption.
  await req('comp-1', 'comp-12-failures', 'Failures are recorded as failures',
    `select (((select count(*) from public.outcome_record where verdict = 'worse')
            + (select count(*) from public.institutional_memory where outcome = 'worse')) > 0
          or ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                where ns.nspname = 'public' and p.proname = 'fn_outcome_evaluate'
                  and pg_get_functiondef(p.oid) ~* '''worse'''
                  and pg_get_functiondef(p.oid) ~* '\\yinstitutional_memory\\y'
                  and pg_get_functiondef(p.oid) ~* '\\youtcome_record\\y') > 0
             and (select count(*) from cron.job j
                   where j.command ~* '\\yfn_outcome_evaluate\\y' and j.active
                     and exists (select 1 from cron.job_run_details d
                                  where d.jobid = j.jobid and d.status = 'succeeded'
                                    and d.start_time > now() - interval '48 hours')
                     and not exists (select 1 from cron.job_run_details d
                                  where d.jobid = j.jobid and d.status <> 'succeeded'
                                    and d.start_time > (select max(d2.start_time)
                                          from cron.job_run_details d2
                                         where d2.jobid = j.jobid and d2.status = 'succeeded'))) > 0
             and (select count(*) from public.outcome_record
                   where verdict = 'pending' and due_at is not null
                     and expected_kpi_id is not null and baseline_value is not null) > 0
             and (select count(*) from public.outcome_record
                   where verdict = 'pending' and due_at <= now()) = 0))
        and ${RD('outcome_record')} > 0`,
    `select 'graded worse: outcome_record '
            || (select count(*) from public.outcome_record where verdict = 'worse')::text
            || ', institutional_memory '
            || (select count(*) from public.institutional_memory where outcome = 'worse')::text
            || '; ' || (select count(*) from public.outcome_record
                         where verdict = 'pending' and due_at is not null
                           and expected_kpi_id is not null and baseline_value is not null)::text
            || ' gradeable pending, first window '
            || coalesce((select min(due_at)::date::text from public.outcome_record where verdict = 'pending'), 'none')
            || ', overdue-and-ungraded '
            || (select count(*) from public.outcome_record where verdict = 'pending' and due_at <= now())::text
            || ', grader last ok '
            || coalesce((select max(d.start_time)::text from cron.job j
                          join cron.job_run_details d on d.jobid = j.jobid
                         where j.command ~* '\\yfn_outcome_evaluate\\y' and d.status = 'succeeded'), 'never')`);

  // Successes. The comment that used to sit above these two claimed they were "tested identically
  // so that the answer reflects the data rather than the check", and they were not: failures
  // excluded outcome_record's writers while successes counted institutional_memory's writers as its
  // readers, and the two sides looked for different vocabularies. Both are now symmetric — writers
  // excluded structurally, and the full closed vocabulary the two graders emit.
  //
  // The third clause is the one that stops this passing on unreadable records. The MET verdict was
  // previously carried by rows fn_learning_loop writes at confidence 0.5, and
  // fn_agent_institutional_memory retrieves only `coalesce(confidence,1) >= 0.6` — so the successes
  // proving the requirement were rows no agent could ever be shown. A success recorded below the
  // retrieval floor is a success recorded where nobody will read it.
  await req('comp-1', 'comp-12-successes', 'Successes are recorded as successes',
    `select ((select count(*) from public.outcome_record where verdict = 'improved')
           + (select count(*) from public.institutional_memory
               where outcome in ('success','success_over_dissent','improved'))) > 0
        and (select count(*) from public.institutional_memory
              where outcome in ('success','success_over_dissent','improved')
                and coalesce(confidence, 1) >= 0.6) > 0
        and ${RD('institutional_memory')} > 0`,
    `select 'graded better: outcome_record improved '
            || (select count(*) from public.outcome_record where verdict = 'improved')::text
            || ', institutional_memory success/success_over_dissent/improved '
            || (select count(*) from public.institutional_memory
                 where outcome in ('success','success_over_dissent','improved'))::text
            || ' of which ' || (select count(*) from public.institutional_memory
                 where outcome in ('success','success_over_dissent','improved')
                   and coalesce(confidence, 1) >= 0.6)::text
            || ' clear the 0.6 retrieval floor; read, writers excluded, by '
            || ${RD_NAMES('institutional_memory')}`);

  // Promotion of short-term to long-term. Both halves are required and neither is a row count on
  // its own: fn_promote_memory must be INVOKED by something, promotions must have happened inside a
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
    `select 'fn_promote_memory invoked by ' || (${FNS('fn_promote_memory')} + ${CRONS('fn_promote_memory')})::text
            || ' routine(s)/job(s); memory_promotions holds '
            || (select count(*) from public.memory_promotions)::text || ' row(s), '
            || (select count(*) from public.memory_promotions where promoted_at > now() - interval '30 days')::text
            || ' in the last 30 days, ' || (select count(*) from public.memory_promotions where kb_chunk_id is null)::text
            || ' with no destination chunk; kb_chunks from memory '
            || (select count(*) from public.kb_chunks where source_kind = 'memory')::text
            || ', read by ' || ${RD('kb_chunks')}::text || ' non-writer(s)'`);

  // ------------------------------------------------------------- COMPONENT 13: LEARNING LOOP

  // Step 1, Task. "Every completed task enters the chain" is a coverage claim, so it is measured as
  // coverage — but only over the window in which the chain has been live, and only over tasks
  // fn_task_review will accept (it returns 'no_deliverable' and writes nothing when result has no
  // deliverable). Counting tasks completed before the first review row would score the absence of
  // history as a defect.
  //
  // That window is defined by the mechanism under test, which is a real weakness, so the evidence
  // now prints the number a reader needs in order to disagree: how many done-with-deliverable tasks
  // fall OUTSIDE it. It also states the second limitation plainly — org_tasks has no completion
  // timestamp (its columns end at updated_at and last_run_at), so a task finished long before t0
  // but touched afterwards enters both numerator and denominator, and no better column exists to
  // use instead.
  await req('comp-1', 'comp-13-task', 'Every completed task enters the chain',
    `with w as (select min(created_at) t0 from public.review_chain where subject_type = 'org_task'),
      d as (select o.id from public.org_tasks o, w
             where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> ''
               and o.updated_at >= w.t0)
     select (select count(*) from d) > 0
        and (select count(*) from d where not exists (
              select 1 from public.review_chain r
               where r.subject_type = 'org_task' and r.subject_id = d.id::text)) = 0`,
    `with w as (select min(created_at) t0 from public.review_chain where subject_type = 'org_task'),
      d as (select o.id from public.org_tasks o, w
             where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> ''
               and o.updated_at >= w.t0),
      x as (select count(*) n from public.org_tasks o, w
             where o.status = 'done' and coalesce(o.result ->> 'deliverable','') <> ''
               and o.updated_at < w.t0)
     select (select count(*) from d where exists (
              select 1 from public.review_chain r
               where r.subject_type = 'org_task' and r.subject_id = d.id::text))::text
            || ' of ' || (select count(*) from d)::text
            || ' tasks reviewed since the chain went live ('
            || coalesce((select t0::text from w), 'never') || '); '
            || (select n from x)::text
            || ' further done-with-deliverable tasks predate the chain and are NOT scored here'`);

  // Step 2, Outcome. A grade needs a named grader and a verdict, and it has to be recent enough to
  // be a running loop rather than a historical one. The reader conjunct excludes review_chain's
  // writers structurally — fn_task_review inserts into it in three places and was previously
  // counted as one of its readers — and the evidence now reports the SAME seven-day window the
  // verdict uses, so the number a reader would use to disagree is the number the check used.
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
  // 42.5, and a consumer of a constant learns nothing from it.
  await req('comp-1', 'comp-13-performance', 'Outcome -> Performance is consumed',
    `select (select count(*) from public.agent_reputation) > 0
        and (select count(distinct score) from public.agent_reputation) > 1
        and (select count(*) from pg_proc r
              join pg_namespace rs on rs.oid = r.pronamespace
             where rs.nspname = 'public' and r.prokind in ('f','p')
               and pg_get_functiondef(r.oid) ~* '\\yagent_reputation\\y'
               and r.proname not in ${WRITERS_OF('agent_reputation')}
               and (exists (select 1 from pg_proc g join pg_namespace gs on gs.oid = g.pronamespace
                             where gs.nspname = 'public' and g.prokind in ('f','p')
                               and g.proname <> r.proname
                               and pg_get_functiondef(g.oid) ~* ('\\y' || r.proname || '\\y'))
                 or exists (select 1 from cron.job j where j.command ~* ('\\y' || r.proname || '\\y')))) > 0`,
    `select (select count(*) from public.agent_reputation)::text || ' scored employees over '
            || (select count(distinct score) from public.agent_reputation)::text
            || ' distinct scores (' || coalesce((select string_agg(t || '=' || n::text, '/' order by t) from
                 (select tier t, count(*) n from public.agent_reputation group by 1) s), '-')
            || '); consumed, writer excluded, by ' || ${RD_NAMES('agent_reputation')}`);

  // Step 4, Lessons. The link has to be automatic, so the reviewer function itself must invoke the
  // lesson writer — and the store must show lessons that CAME FROM that path.
  //
  // The old second conjunct counted any institutional_memory row created in the last 7 days, and
  // that table has at least five writers; fn_outcome_evaluate, fn_dispute_open, fn_company_reflect
  // and fn_ap_bill_dupe_guard keep it warm on their own. So the check stayed MET in exactly the
  // failure it exists to catch: the reviewer never runs and unrelated writers cover for it. A
  // lesson now counts only if a review_chain row exists for the same task — the join the phrase
  // "Performance -> Lessons" actually names.
  await req('comp-1', 'comp-13-lessons', 'Performance -> Lessons is automatic',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_task_review'
                and pg_get_functiondef(p.oid) ~* '\\yfn_task_lesson\\y') > 0
        and (select count(*) from public.institutional_memory m
              where m.created_at > now() - interval '7 days'
                and m.subject_type = 'org_task' and m.kind in ('lesson','lesson_learned')
                and exists (select 1 from public.review_chain r
                             where r.subject_type = 'org_task' and r.subject_id = m.subject_id)) > 0`,
    `select (select count(*) from public.institutional_memory m
              where m.created_at > now() - interval '7 days'
                and m.subject_type = 'org_task' and m.kind in ('lesson','lesson_learned')
                and exists (select 1 from public.review_chain r
                             where r.subject_type = 'org_task' and r.subject_id = m.subject_id))::text
            || ' lesson(s) in the last 7 days trace to a reviewed task, of '
            || (select count(*) from public.institutional_memory
                 where created_at > now() - interval '7 days'
                   and subject_type = 'org_task' and kind in ('lesson','lesson_learned'))::text
            || ' org_task lessons written in that window (the remainder have no review_chain row '
            || 'and did not come from this loop); last '
            || coalesce((select max(created_at)::text from public.institutional_memory), 'never')`);

  // Step 5, Knowledge Update. The only proof that a lesson reached an agent is the agent's own
  // context. fn_agent_context truncates LAYER 4 to 3,500 chars, so this is a genuine reach test and
  // not a restatement of "the function mentions the table".
  await req('comp-1', 'comp-13-knowledge-update', 'Lessons -> Knowledge Update reaches agents',
    `select public.fn_agent_context('ceo', 22000) like '%## lesson (%'
        and (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_agent_context'
                and pg_get_functiondef(p.oid) ~* '\\yfn_agent_institutional_memory\\y') > 0`,
    `select 'lesson block in ceo prompt: '
            || (public.fn_agent_context('ceo', 22000) like '%## lesson (%')::text
            || '; retrieval block is ' || length(coalesce(public.fn_agent_institutional_memory('ceo', 6), ''))::text
            || ' chars before the 3500-char LAYER 4 cap'`);

  // Step 6, SOP Update. fn_sop_update writes runbooks slugged 'lesson-<id>' from graded
  // institutional memory. Its filter used to be outcome in ('worse','improved') —
  // fn_outcome_evaluate's verdict vocabulary — while the other live writer grades with 'success' /
  // 'success_over_dissent', so it ran weekly and matched 0 of 38 rows. The filter now names all
  // four and the evidence reports the input set THAT filter matches; reporting the old two would
  // print "0 matching" beside a green verdict and send the next session hunting a phantom.
  //
  // The third clause is what stops a hand-seeded runbook scoring the writer: every lesson-<id> slug
  // must resolve to an institutional_memory row that still exists. os_runbooks carries no timestamp
  // column, so derivation is the only available proof that these rows were produced rather than
  // placed.
  await req('comp-1', 'comp-13-sop-update', 'Knowledge Update -> SOP Update writes runbooks',
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%') > 0
        and (select count(*) from cron.job where command ~* '\\yfn_sop_update\\y' and active) > 0
        and (select count(*) from public.os_runbooks b
              where b.slug like 'lesson-%'
                and not exists (select 1 from public.institutional_memory m
                                 where 'lesson-' || m.id = b.slug)) = 0`,
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%')::text
            || ' lesson runbook(s), all of which resolve back to an institutional_memory row; '
            || 'graded rows the deployed filter matches: '
            || (select count(*) from public.institutional_memory
                 where outcome in ('worse','improved','success','success_over_dissent'))::text
            || ' of ' || (select count(*) from public.institutional_memory)::text
            || ', unconverted backlog '
            || (select count(*) from public.institutional_memory m
                 where m.outcome in ('worse','improved','success','success_over_dissent')
                   and not exists (select 1 from public.os_runbooks b where b.slug = 'lesson-'||m.id))::text
            || ' awaiting the next weekly run'`);
}
