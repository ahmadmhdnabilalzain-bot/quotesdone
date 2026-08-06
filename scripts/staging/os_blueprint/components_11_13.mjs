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
// Two rules govern the SQL below.
//
// A column that exists is not a mechanism that works. Five columns in this section
// (os_objective.measure_sql/actual_value, employee_kpi.serves_objective, org_tasks.root_cause,
// agent_memory.horizon, os_runbooks.os_key) were added but never written to. So no check here is
// satisfied by information_schema alone: existence is always paired with a row count and a reader.
//
// A reader must be something other than the writer. fn_reputation_recompute referencing
// agent_reputation is not a reader of agent_reputation, it is the thing that filled it. Where the
// writer is known it is named and excluded, otherwise "0 readers" would be reported as 1.
export default async function ({ req, READERS }) {

  // Readers among routines, with the writers of the object excluded by name. The runner's READERS
  // only excludes a routine that shares the object's own name, which is enough for a function but
  // not for a table: a table's writer is always called something else.
  const FNS = (t, skip = []) => `(select count(*) from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind in ('f','p') and p.proname <> '${t}'
       ${skip.map(s => `and p.proname <> '${s}'`).join(' ')}
       and pg_get_functiondef(p.oid) ~* '\\y${t}\\y')`;
  const VIEWS = (t) => `(select count(*) from pg_views v
     where v.schemaname = 'public' and v.definition ~* '\\y${t}\\y')`;
  const CRONS = (t) => `(select count(*) from cron.job j where j.command ~* '\\y${t}\\y')`;
  // Reading a value out of a row without naming the column: the five columns above appeared
  // mid-measurement and could disappear the same way. to_jsonb(row)->>'col' is null both when the
  // column holds null and when it does not exist, which is exactly the claim being tested — the
  // field is not carrying a value — and it cannot raise "column does not exist" mid-run.
  const FIELD = (alias, col) => `to_jsonb(${alias}) ->> '${col}'`;

  // ---------------------------------------------------------------- COMPONENT 11: KPI ENGINE

  // The head of the KPI chain. os_objective held 50 rows (5 horizons x 10 OSes) whose only
  // reference was v_operating_manual, a view with no readers of its own — the definition of an
  // asset nobody consumes. The test is not "is the table referenced" but "does an objective's own
  // text come back out of the prompt an employee is actually handed".
  await req('comp-1', 'comp-11-objectives', 'Objectives are read by something',
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t)
     select (select count(*) from public.os_objective o, ctx
              where o.active and position(o.objective in ctx.t) > 0) > 0`,
    `with ctx as materialized (select public.fn_agent_context('cfo', 22000) t)
     select (select count(*) from public.os_objective o, ctx
              where o.active and position(o.objective in ctx.t) > 0)::text
            || ' of ' || (select count(*) from public.os_objective where active)::text
            || ' objectives reach the cfo prompt verbatim'`);

  // Objectives -> KPIs. A KPI without a measure_sql is a sentence, not a measure, so the check
  // fails if any active KPI lacks one rather than passing on a majority.
  await req('comp-1', 'comp-11-kpis', 'KPIs exist and are measurable',
    `select (select count(*) from public.employee_kpi where active) > 0
        and (select count(*) from public.employee_kpi where active and measure_sql is null) = 0
        and ${READERS('employee_kpi')} > 0`,
    `select (select count(*) from public.employee_kpi where active)::text || ' active KPIs, '
            || (select count(*) from public.employee_kpi where active and measure_sql is not null)::text
            || ' with measure_sql, ' || ${READERS('employee_kpi')}::text || ' reader(s)'`);

  // KPIs -> Actual Values. fn_kpi_scoreboard executes each measure_sql, but a number that is
  // computed and discarded is not an actual value the company holds. What proves it landed is
  // outcome_record rows carrying both the KPI id and the baseline the measure returned, in a table
  // read by routines other than the two that write it.
  await req('comp-1', 'comp-11-actual-values', 'KPIs -> Actual Values are computed',
    `select (select count(*) from public.outcome_record
              where expected_kpi_id is not null and baseline_value is not null) > 0
        and ${FNS('outcome_record', ['fn_outcome_open', 'fn_outcome_evaluate'])} > 0`,
    `select (select count(*) from public.outcome_record
              where expected_kpi_id is not null and baseline_value is not null)::text
            || ' KPI actuals persisted; last scoreboard run '
            || coalesce((select counts::text from public.agent_runs
                          where agent = 'kpi_review' order by finished_at desc limit 1), 'never')`);

  // Actual Values -> Variance. The scoreboard must return the comparison (attainment + verdict),
  // and the comparison must have produced work items that something reads.
  await req('comp-1', 'comp-11-variance', 'Variance is computed and acted on',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_kpi_scoreboard'
                and pg_get_function_result(p.oid) ~* 'attainment'
                and pg_get_function_result(p.oid) ~* 'verdict') > 0
        and (select count(*) from public.org_tasks where title ilike 'KPI missed%') > 0
        and ${READERS('org_tasks')} > 0`,
    `select (select count(*) from public.org_tasks where title ilike 'KPI missed%')::text
            || ' KPI-missed task(s) carrying target vs actual, '
            || (select count(*) from public.outcome_record where expected_kpi_id is not null)::text
            || ' outcome record(s) opened against them'`);

  // Variance -> Root Cause. org_tasks.root_cause now exists; the 50 KPI-missed tasks still only
  // ask an agent to "diagnose the cause" in prose. A structural capture means the field carries a
  // value AND some routine reads org_tasks and that field together — the one function in the
  // database mentioning root_cause reads p2c1_b7_case, an unrelated regression fixture, so the
  // reader test names both objects rather than matching the word anywhere.
  await req('comp-1', 'comp-11-root-cause', 'Variance -> Root Cause is captured structurally',
    `select (select count(*) from public.org_tasks o where ${FIELD('o', 'root_cause')} is not null) > 0
        and ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
               where ns.nspname = 'public' and p.prokind in ('f','p')
                 and pg_get_functiondef(p.oid) ~* '\\yorg_tasks\\y'
                 and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y')
           + (select count(*) from pg_views v where v.schemaname = 'public'
               and v.definition ~* '\\yorg_tasks\\y' and v.definition ~* '\\yroot_cause\\y')) > 0`,
    `select (select count(*) from public.org_tasks o where ${FIELD('o', 'root_cause')} is not null)::text
            || ' task(s) carry a root cause, of '
            || (select count(*) from public.org_tasks where title ilike 'KPI missed%')::text
            || ' KPI-missed; routines joining org_tasks to root_cause: '
            || ((select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
                  where ns.nspname = 'public' and p.prokind in ('f','p')
                    and pg_get_functiondef(p.oid) ~* '\\yorg_tasks\\y'
                    and pg_get_functiondef(p.oid) ~* '\\yroot_cause\\y'))::text`);

  // Root Cause -> Improvement Plan. The plan has to reach the owner, so the test is the owner's
  // prompt, not the column.
  await req('comp-1', 'comp-11-improvement-plan', 'Improvement Plan reaches the owner',
    `select (select count(*) from public.org_agents where coalesce(improvement_plan,'') <> '') > 0
        and public.fn_agent_context('cfo', 22000) like '%Your improvement plan%'`,
    `select (select count(*) from public.org_agents where coalesce(improvement_plan,'') <> '')::text
            || ' of ' || (select count(*) from public.org_agents)::text
            || ' employees carry an improvement plan, and it is emitted into the prompt'`);

  // The KPI Engine's stated schedule. A job row is a claim; a succeeded run is the fact. Both
  // KPI-engine jobs must exist, be active, and have completed at least once — kpi_review_weekly
  // has one attempt that died on a statement timeout, which is a schedule that has never run.
  await req('comp-1', 'comp-11-schedule', 'KPI Engine runs on its stated schedule',
    `with j as (select * from cron.job
                 where command ~* '\\y(fn_kpi_review|fn_improvement_plan_refresh)\\y')
     select (select count(*) from j) >= 2
        and (select count(*) from j where not j.active) = 0
        and (select count(*) from j where not exists (
              select 1 from cron.job_run_details d
               where d.jobid = j.jobid and d.status = 'succeeded')) = 0`,
    `with j as (select * from cron.job
                 where command ~* '\\y(fn_kpi_review|fn_improvement_plan_refresh)\\y')
     select coalesce(string_agg(j.jobname || ' succeeded=' ||
              (select count(*) from cron.job_run_details d
                where d.jobid = j.jobid and d.status = 'succeeded')::text
              || '/' || (select count(*) from cron.job_run_details d where d.jobid = j.jobid)::text,
              ', ' order by j.jobname), 'no KPI-engine cron job exists') from j`);

  // ------------------------------------------------------------- COMPONENT 12: MEMORY SYSTEM

  // Short-term memory has to be SEPARABLE from long-term, otherwise there is one undifferentiated
  // store and the distinction the blueprint draws is decorative. agent_memory.horizon exists now;
  // the question is whether a single row carries one.
  await req('comp-1', 'comp-12-short-term', 'Short-term memory is distinguishable',
    `select (select count(*) from public.agent_memory m
              where ${FIELD('m', 'horizon')} is not null
                 or ${FIELD('m', 'expires_at')} is not null) > 0
        and ${FNS('agent_memory', ['fn_promote_memory'])} > 0`,
    `select (select count(*) from public.agent_memory m where ${FIELD('m', 'horizon')} is not null)::text
            || ' of ' || (select count(*) from public.agent_memory)::text
            || ' memories carry a horizon; kinds present: '
            || coalesce((select string_agg(distinct kind, '/') from public.agent_memory), 'none')`);

  await req('comp-1', 'comp-12-long-term', 'Long-term memory exists and is read',
    `select (select count(*) from public.org_memory) > 0
        and ${FNS('org_memory')} > 0
        and (select count(*) from public.institutional_memory) > 0
        and ${FNS('institutional_memory')} > 0`,
    `select (select count(*) from public.org_memory)::text || ' org_memory rows / '
            || ${FNS('org_memory')}::text || ' readers; '
            || (select count(*) from public.institutional_memory)::text
            || ' institutional_memory rows / ' || ${FNS('institutional_memory')}::text || ' readers'`);

  // Lessons must be RETRIEVABLE, not merely stored: the retrieval function has to return something
  // for a real employee and has to be referenced by something that assembles context.
  await req('comp-1', 'comp-12-lessons', 'Lessons Learned are stored and retrieved',
    `select (select count(*) from public.institutional_memory
              where kind in ('lesson','lesson_learned')) > 0
        and length(coalesce(public.fn_agent_institutional_memory('ceo', 6), '')) > 0
        and ${FNS('fn_agent_institutional_memory')} > 0`,
    `select (select count(*) from public.institutional_memory
              where kind in ('lesson','lesson_learned'))::text || ' lesson row(s); retrieval returns '
            || length(coalesce(public.fn_agent_institutional_memory('ceo', 6), ''))::text
            || ' chars for ceo'`);

  // Best practices are a distinct store (os_runbooks), not a subset of lessons. Its writer
  // fn_sop_update is excluded so that the "not exists" probe inside the writer cannot count as
  // the store being read.
  await req('comp-1', 'comp-12-best-practices', 'Best Practices are a distinct, read store',
    `select (select count(*) from public.os_runbooks) > 0
        and (${FNS('os_runbooks', ['fn_sop_update'])} + ${VIEWS('os_runbooks')}
             + ${CRONS('os_runbooks')}) > 0`,
    `select (select count(*) from public.os_runbooks)::text || ' runbook(s), read by '
            || coalesce((select string_agg(p.proname, '/') from pg_proc p
                          join pg_namespace ns on ns.oid = p.pronamespace
                         where ns.nspname = 'public' and p.prokind in ('f','p')
                           and p.proname <> 'fn_sop_update'
                           and pg_get_functiondef(p.oid) ~* '\\yos_runbooks\\y'), 'nothing')
            || '; scoped to an OS: '
            || (select count(*) from public.os_runbooks b where ${FIELD('b', 'os_key')} is not null)::text`);

  await req('comp-1', 'comp-12-historical-decisions', 'Historical Decisions are queryable',
    `select (select count(*) from public.decision_log) > 0
        and ${FNS('decision_log')} > 0
        and (select count(*) from public.decision_record) > 0
        and ${FNS('decision_record')} > 0`,
    `select (select count(*) from public.decision_log)::text || ' decision_log rows / '
            || ${FNS('decision_log')}::text || ' readers; '
            || (select count(*) from public.decision_record)::text
            || ' decision_record rows / ' || ${FNS('decision_record')}::text || ' readers'`);

  // Failures. The previous assertion here demanded that a row already carry verdict 'worse' or
  // outcome 'worse', and that assertion CANNOT BE SATISFIED TODAY EVEN IN PRINCIPLE — which makes
  // it a measurement of history, not of capability. Measured on production 6 Aug 2026: all 50
  // outcome_record rows are pending, the EARLIEST due_at is 2026-08-11 17:25 and 0 rows are due,
  // because fn_kpi_review opens every record with p_measure_after of 14 or 35 days. The only way to
  // turn the old assertion green today is to manufacture a 'worse' row, i.e. to record a failure
  // that did not happen — the founder's standing instruction forbids exactly that, and a gate that
  // can only be passed by falsifying data is a broken gate.
  //
  // So this asks the question the requirement actually poses: CAN a failure be recorded as a
  // failure, and is the recorder running? Four things must hold before the window opens — the
  // grader writes the 'worse' verdict AND mirrors it into institutional_memory, it is on an active
  // schedule, there is a real cohort waiting with everything grading needs (a due date, a KPI and a
  // baseline), and nothing is already overdue and ungraded, which would mean the grader is stalled
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
             and (select count(*) from cron.job
                   where command ~* '\\yfn_outcome_evaluate\\y' and active) > 0
             and (select count(*) from public.outcome_record
                   where verdict = 'pending' and due_at is not null
                     and expected_kpi_id is not null and baseline_value is not null) > 0
             and (select count(*) from public.outcome_record
                   where verdict = 'pending' and due_at <= now()) = 0))
        and ${FNS('outcome_record', ['fn_outcome_open', 'fn_outcome_evaluate'])} > 0`,
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
            || (select count(*) from public.outcome_record where verdict = 'pending' and due_at <= now())::text`);

  await req('comp-1', 'comp-12-successes', 'Successes are recorded as successes',
    `select ((select count(*) from public.outcome_record where verdict = 'improved')
           + (select count(*) from public.institutional_memory where outcome = 'success')) > 0
        and ${FNS('institutional_memory')} > 0`,
    `select 'graded better: outcome_record improved '
            || (select count(*) from public.outcome_record where verdict = 'improved')::text
            || ', institutional_memory success '
            || (select count(*) from public.institutional_memory where outcome = 'success')::text
            || ' (read by ' || ${FNS('institutional_memory')}::text || ' routines)'`);

  // Promotion of short-term to long-term. fn_promote_memory exists and writes memory_promotions;
  // nothing invokes it and the table has never held a row. Both halves are required: a scheduled
  // function that has produced nothing is not a promotion path.
  await req('comp-1', 'comp-12-promotion', 'Short-term memory is promoted to long-term',
    `select (${FNS('fn_promote_memory')} + ${CRONS('fn_promote_memory')}) > 0
        and (select count(*) from public.memory_promotions) > 0`,
    `select 'fn_promote_memory invoked by ' || (${FNS('fn_promote_memory')} + ${CRONS('fn_promote_memory')})::text
            || ' routine(s)/job(s); memory_promotions holds '
            || (select count(*) from public.memory_promotions)::text || ' row(s)'`);

  // ------------------------------------------------------------- COMPONENT 13: LEARNING LOOP

  // Step 1, Task. "Every completed task enters the chain" is a coverage claim, so it is measured
  // as coverage — but only over the window in which the chain has been live, and only over tasks
  // fn_task_review will accept (it returns 'no_deliverable' and writes nothing when result has no
  // deliverable). Counting tasks completed before the first review row would score the absence of
  // history as a defect.
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
               and o.updated_at >= w.t0)
     select (select count(*) from d where exists (
              select 1 from public.review_chain r
               where r.subject_type = 'org_task' and r.subject_id = d.id::text))::text
            || ' of ' || (select count(*) from d)::text
            || ' tasks completed since the chain went live ('
            || coalesce((select t0::text from w), 'never') || ') were reviewed'`);

  // Step 2, Outcome. A grade needs a named grader and a verdict, and it has to be recent enough to
  // be a running loop rather than a historical one.
  await req('comp-1', 'comp-13-outcome', 'Task -> Outcome is graded by a reviewer',
    `select (select count(*) from public.review_chain
              where subject_type = 'org_task' and reviewer_agent is not null
                and decision is not null and created_at > now() - interval '7 days') > 0
        and ${FNS('review_chain', ['fn_review_submit'])} > 0`,
    `select coalesce((select string_agg(x, ', ' order by x) from (
              select decision || '=' || count(*)::text x from public.review_chain
               where subject_type = 'org_task' group by decision) s), 'no graded reviews')
            || '; last ' || coalesce((select max(created_at)::text from public.review_chain
                                       where subject_type = 'org_task'), 'never')`);

  // Step 3, Performance. agent_reputation is 66 scored employees. Its only reference in the whole
  // database is fn_reputation_recompute, which wrote them — so the writer is excluded by name.
  // Measured performance that changes nothing is a scoreboard, not a learning loop.
  await req('comp-1', 'comp-13-performance', 'Outcome -> Performance is consumed',
    `select (select count(*) from public.agent_reputation) > 0
        and (${FNS('agent_reputation', ['fn_reputation_recompute'])} + ${VIEWS('agent_reputation')}
             + ${CRONS('agent_reputation')}) > 0`,
    `select (select count(*) from public.agent_reputation)::text || ' scored employees; readers other than '
            || 'the writer: ' || (${FNS('agent_reputation', ['fn_reputation_recompute'])}
                                  + ${VIEWS('agent_reputation')} + ${CRONS('agent_reputation')})::text`);

  // Step 4, Lessons. The link has to be automatic, so the reviewer function itself must invoke the
  // lesson writer, and the store must show writes inside the live window.
  await req('comp-1', 'comp-13-lessons', 'Performance -> Lessons is automatic',
    `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname = 'public' and p.proname = 'fn_task_review'
                and pg_get_functiondef(p.oid) ~* '\\yfn_task_lesson\\y') > 0
        and (select count(*) from public.institutional_memory
              where created_at > now() - interval '7 days') > 0`,
    `select (select count(*) from public.institutional_memory
              where created_at > now() - interval '7 days')::text
            || ' lesson(s) written in the last 7 days, last '
            || coalesce((select max(created_at)::text from public.institutional_memory), 'never')`);

  // Step 5, Knowledge Update. The only proof that a lesson reached an agent is the agent's own
  // context. fn_agent_context truncates LAYER 4 to 3,500 chars, so this is a genuine reach test
  // and not a restatement of "the function mentions the table".
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
  // institutional memory. Its filter used to be outcome in ('worse','improved') — fn_outcome_evaluate's
  // verdict vocabulary — while the other writers of that table grade with 'success' /
  // 'success_over_dissent', so it ran weekly and matched 0 of 38 rows. The filter now names all four
  // and the evidence reports the input set THAT filter matches; reporting the old two would print
  // "0 matching" beside a green verdict and send the next session hunting a phantom.
  await req('comp-1', 'comp-13-sop-update', 'Knowledge Update -> SOP Update writes runbooks',
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%') > 0
        and (select count(*) from cron.job where command ~* '\\yfn_sop_update\\y' and active) > 0`,
    `select (select count(*) from public.os_runbooks where slug like 'lesson-%')::text
            || ' lesson runbook(s); graded institutional_memory rows the filter matches: '
            || (select count(*) from public.institutional_memory
                 where outcome in ('worse','improved','success','success_over_dissent'))::text
            || ' of ' || (select count(*) from public.institutional_memory)::text
            || ', unconverted backlog '
            || (select count(*) from public.institutional_memory m
                 where m.outcome in ('worse','improved','success','success_over_dissent')
                   and not exists (select 1 from public.os_runbooks b where b.slug = 'lesson-'||m.id))::text`);
}
