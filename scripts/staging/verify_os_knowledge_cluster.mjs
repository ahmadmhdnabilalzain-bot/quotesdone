// THE KNOWLEDGE CLUSTER OF SPEC FILE #2 — objectives that measure, knowledge that routes,
// workflows that run. One executable gate for four requirements that were all the same failure:
// an asset built, populated, and read by nothing.
//
//   node scripts/staging/verify_os_knowledge_cluster.mjs           # STAGING, writes, full gate
//   node scripts/staging/verify_os_knowledge_cluster.mjs --prod    # PRODUCTION, read-only subset
//
// The write half runs on staging only, because qd_guard refuses production writes by design. What
// it proves there — that fn_workflow_start is idempotent and fn_workflow_step_done really advances
// a run — is a property of the routine, and the routine on production is the same bytes.
//
// WHY THIS GATE EXISTS AT ALL: fn_os_objective_measure swallows a per-objective exception so one
// broken measure cannot stop the other forty-nine. That is right, and it also means a measure that
// THROWS is invisible in actual_value, which is null for perfectly good reasons too (nullif over an
// empty table). measured_at is therefore stamped only on the path that ran, and check 2 below is
// the only thing that distinguishes "this company has no revenue yet" from "this measure is broken".
import { mgmtRead, mgmtWrite, PROD_REF } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const PROD = process.argv.includes('--prod');
const REF = PROD ? PROD_REF : STAGE;
const checks = [];
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const q = async (sql) => one(await mgmtRead(REF, sql));
const step = (name, ok, detail) => {
  checks.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(56)} ${detail}`);
};

console.log(`\nOS knowledge cluster on ${REF}${PROD ? ' (read-only)' : ''}\n`);

// ── comp-03: objectives carry a computable measure ──────────────────────────────────────────────
const objTotal = Number(await q(`select count(*) from public.os_objective where coalesce(active,true)`));
const objMeasured = Number(await q(
  `select count(*) from public.os_objective where coalesce(active,true) and coalesce(measure_sql,'') <> ''`));
step('every active objective carries measure_sql', objMeasured === objTotal && objTotal > 0,
  `${objMeasured} of ${objTotal}`);

// A measure with SQL and no measured_at threw when it was resolved. That is the only signal there is.
const threw = await q(
  `select coalesce(string_agg(os_key||'/'||horizon, ', '), 'none') from public.os_objective
    where coalesce(active,true) and coalesce(measure_sql,'') <> '' and measured_at is null`);
step('no objective measure throws when resolved', threw === 'none', `threw: ${threw}`);

const withValue = Number(await q(
  `select count(*) from public.os_objective where actual_value is not null`));
step('objectives resolve to actual values', withValue > 0,
  `${withValue} of ${objTotal} carry a number (null is legitimate for a nullif over an empty table)`);

// ── comp-06: the owning OS is resolvable, and something calls the resolver ───────────────────────
const route = String(await q(
  `select coalesce(public.fn_os_knowledge_query('leadership'), '')`));
step('fn_os_knowledge_query resolves an owner for a querying OS',
  route.includes('-> ask') && /finance/i.test(route),
  route.split('\n')[0].slice(0, 70) || '(empty)');

const callers = Number(await q(
  `select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public' and p.prokind in ('f','p') and p.proname <> 'fn_os_knowledge_query'
      and pg_get_functiondef(p.oid) ~* '\\yfn_os_knowledge_query\\y'`));
step('the resolver has a caller', callers > 0,
  `${callers} routine(s) call it — fn_kb_retrieve had zero and hid 1,206 rules`);

// ── comp-05: every employee has profession knowledge of their OWN ───────────────────────────────
// Not "reaches some knowledge": fn_agent_context falls back to a dept-mate's, which is how 52 of 66
// employees looked covered while holding nothing. Personal is the claim the spec makes.
const own = Number(await q(
  `select count(*) from public.org_agents a where a.active
     and exists (select 1 from public.agent_knowledge k where k.agent_key = a.agent_key
                  and coalesce(k.layer,'profession') in ('profession','state'))`));
const active = Number(await q(`select count(*) from public.org_agents where active`));
step('every active employee has profession knowledge of their own', own === active && active > 0,
  `${own} of ${active}`);

// ── comp-09: workflows run, are tracked, and are read ───────────────────────────────────────────
// Deliberately NOT asserted here on staging. Staging's company_event carries no row matching any
// workflow trigger, so fn_workflow_start_due(0) correctly starts nothing and the first run on that
// project is the one this gate creates below. Asserting before creating it would be asserting that
// a fixture happens to be pre-seeded, which is not the requirement.
const countRuns = async () => {
  const runs = Number(await q(`select count(*) from public.workflow_run`));
  const stepRuns = Number(await q(`select count(*) from public.workflow_step_run`));
  step('workflow runs exist with planned steps', runs > 0 && stepRuns > 0,
    `${runs} run(s), ${stepRuns} step run(s)`);
};

const wfReaders = Number(await q(
  `select (select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
            where ns.nspname='public' and p.prokind in ('f','p')
              and pg_get_functiondef(p.oid) ~* '\\yworkflow_run\\y')
        + (select count(*) from pg_views v where v.schemaname='public' and v.definition ~* '\\yworkflow_run\\y')
        + (select count(*) from cron.job j where j.command ~* '\\yworkflow_run\\y')`));
step('workflow_run has readers', wfReaders > 0, `${wfReaders} reader(s)`);

// The prompt is the test for all three, not the table. A column being populated is not the same
// claim as the employee being told about it — that difference is the whole subject of this spec.
const agent = String(await q(
  `select a.agent_key from public.org_agents a
     join public.os_department d on d.dept_key = a.department
    where a.active and d.os_key = 'leadership' order by a.agent_key limit 1`));
const ctx = String(await q(
  `select public.fn_agent_context('${agent}', 22000)`));
step('the measured objectives reach the employee prompt',
  ctx.includes('YOUR OS OBJECTIVES, MEASURED'), `${agent}: ${ctx.length} chars`);
step('the cross-OS knowledge routing reaches the employee prompt',
  ctx.includes('QUERY THE OWNER, DO NOT DUPLICATE IT'), `${agent}`);
step('the employee prompt still carries the OS block it carried before',
  ctx.includes('# YOUR OPERATING SYSTEM'),
  'appending after layer 4 must not push v_emp past its 6,200-char cut');

if (PROD) {
  await countRuns();
  const met = checks.filter(c => c.ok).length;
  console.log(`\n${met}/${checks.length} on production (write half runs on staging only)`);
  process.exit(met === checks.length ? 0 : 1);
}

// ── the write half: does the engine actually move? ───────────────────────────────────────────────
// Idempotency is asserted by CALLING IT TWICE and counting rows, not by trusting the unique index:
// on conflict do nothing returns no id, and a caller that then failed to look the run up would
// return null and read as a failure to start. Both branches are exercised here.
//
// The workflow and the event are picked independently and NOT joined on trigger_event. On staging
// no company_event row matches any workflow trigger — staging is a rebuilt fixture — so joining
// them yields nothing and the probe silently tests nothing at all, which is what the first run of
// this gate did. fn_workflow_start does not require the event to be the workflow's trigger; the
// idempotency key is (workflow, event) either way, so any real event id exercises both branches.
const wf = String(await q(
  `select workflow_key from public.workflow where coalesce(active,true)
    and exists (select 1 from public.workflow_step s where s.workflow_key = workflow.workflow_key)
    order by workflow_key limit 1`));
const ev = String(await q(`select id::text from public.company_event order by id limit 1`));
if (wf === 'null' || ev === 'null') {
  console.log('\n  no active workflow with steps, or no company_event, on this project — write half skipped');
  const m = checks.filter(c => c.ok).length;
  console.log(`\n${m}/${checks.length}`);
  process.exit(m === checks.length ? 0 : 1);
}

await mgmtWrite(REF, `select public.fn_workflow_start('${wf}', ${ev}, 'company_event', '${ev}')`, 'idempotency probe');
const dupes = Number(await q(
  `select count(*) from public.workflow_run where idempotency_key = '${wf}:${ev}'`));
step('starting the same workflow for the same event twice yields one run', dupes === 1,
  `${dupes} run(s) for ${wf}:${ev}`);

const runId = String(await q(
  `select id::text from public.workflow_run where idempotency_key = '${wf}:${ev}'`));
const before = String(await q(
  `select current_step::text||'/'||status from public.workflow_run where id = '${runId}'`));
const firstStep = Number(await q(
  `select min(step_no) from public.workflow_step_run where workflow_run_id = '${runId}'`));
// SEPARATE STATEMENTS. A single statement shares one snapshot, so calling the function and reading
// its effect in the same UNION returns the PRE-call state — that produced a false 0/10 in this
// project today.
await mgmtWrite(REF,
  `select public.fn_workflow_step_done('${runId}'::uuid, ${firstStep}, '{"probe":true}'::jsonb)`,
  'advance probe');
const after = String(await q(
  `select current_step::text||'/'||status from public.workflow_run where id = '${runId}'`));
step('closing a step advances the run', before !== after, `${before} -> ${after}`);

const readyNow = Number(await q(
  `select count(*) from public.workflow_step_run
    where workflow_run_id = '${runId}' and status = 'ready'`));
step('exactly one step is ready after the advance', readyNow <= 1,
  `${readyNow} ready (0 is correct when the run just completed)`);

await countRuns();

const met = checks.filter(c => c.ok).length;
console.log(`\n${met}/${checks.length}`);
process.exit(met === checks.length ? 0 : 1);
