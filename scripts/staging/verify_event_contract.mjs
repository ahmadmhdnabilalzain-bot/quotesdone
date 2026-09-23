// THE CROSS-OS EVENT CONTRACT — links 2, 3, 4, 5 and 14, exercised rather than read.
//
// Everything asserted here is reachable ONLY at call time. The precedent is exact: a previous
// patch of this shape was applied by a DO block that rewrites pg_get_functiondef, reported
// success, and carried three errors that surfaced only when the function ran. So the fixture is
// built in the same change as the function, and it runs the real dispatcher against real rows.
//
//   node scripts/staging/verify_event_contract.mjs          # staging, zero model spend
import { mgmtRead, mgmtWrite } from '../lib/qd_guard.mjs';
import { REF as STAGE } from '../lib/demo_factory.mjs';

const checks = [];
const step = (name, ok, detail) => {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(58)} ${detail}`);
};
const one = (r) => (r && r[0]) ? Object.values(r[0])[0] : null;
const rd = async (sql) => one(await mgmtRead(STAGE, sql));
const wr = (sql, why) => mgmtWrite(STAGE, sql, why);

const TAG = 'qd_fixture_evt';
const EVT_UNDECLARED = 'qd.fixture.undeclared'; // one os_interface does not declare — comp-07 drift

// ── cleanup first, so a previous aborted run cannot make this one pass or fail for its reasons ──
async function cleanup() {
  await wr(`
    delete from event_assessment where event_id in
      (select id from company_event where actor = '${TAG}');
    delete from event_delivery where event_id in
      (select id from company_event where actor = '${TAG}');
    delete from org_tasks where decided_by = 'fn_event_dispatch'
      and title like '%${TAG}%';
    delete from org_tasks where dept_key in (select dept_key from org_departments)
      and detail like '%${TAG}%';
    delete from company_event where actor = '${TAG}';
    delete from event_subscription where reason = '${TAG}';`, 'clear event fixture');
}
await cleanup();

// ── pick the fixture from os_interface OUTWARDS, not from org_agents inwards ────────────────────
// The first cut of this gate picked any routable agent and hard-coded event_type='kpi.missed'. It
// resolved to the commercial OS, which does not declare kpi.missed as an input, so the severity
// check fell through its own "(none)" escape hatch and PASSED WITHOUT COMPARING ANYTHING. A check
// that cannot fail is worth nothing. The pair is therefore chosen so that a declared severity
// genuinely exists to be compared against.
const pair = await rd(`select a.agent_key || '|' || a.department || '|' || od.os_key || '|' || i.event_type
  from os_interface i
  join os_department od on od.os_key = i.os_key
  join org_agents a on a.department = od.dept_key and a.active
 where i.direction = 'input' and i.severity is not null and i.event_type is not null
 order by i.event_type, a.agent_key limit 1`);
if (!pair) { console.error('staging has no (declared input, OS, staffed department) triple'); process.exit(2); }
const [AGENT, DEPT, OS, EVT_DECLARED] = pair.split('|');
console.log(`\nfixture agent ${AGENT} · department ${DEPT} · OS ${OS} · declared input ${EVT_DECLARED}\n`);

// A subscription pointing at an employee who DOES NOT EXIST — the real 179-NULL case. No
// org_agents row is created for it on purpose: org_agents.department is NOT NULL, so "an agent
// with no department" is not a state this schema can hold, and a fixture that tried to build one
// would be testing a situation production cannot reach.
await wr(`insert into event_subscription (agent_key, event_type, reason, active) values
   ('${AGENT}', '${EVT_DECLARED}', '${TAG}', true),
   ('${AGENT}', '${EVT_UNDECLARED}', '${TAG}', true),
   ('${TAG}_orphan', '${EVT_DECLARED}', '${TAG}', true)
   on conflict (agent_key, event_type) do update set active = true, reason = '${TAG}'`, 'subs');

// ── DRAIN THE PRE-EXISTING BACKLOG BEFORE MEASURING ANYTHING ────────────────────────────────────
// The loop orders by event id, so it processes OLDEST first, and the batch cap is 50. Staging
// carries 278 events against 48 real subscriptions, so the first run of this gate spent its whole
// batch on the backlog and never reached the fixture — nine checks failed reporting "0 deliveries"
// for a dispatcher that was working correctly. That is the fixture being starved, not a defect,
// and a gate that cannot tell those apart is useless. Drain to empty first, then measure.
let drained = 0, guard = 0;
for (;;) {
  const r = JSON.parse(await rd(`select public.fn_event_dispatch()::text`));
  drained += r.delivered;
  if (r.delivered === 0 || ++guard > 60) break;
}
console.log(`  drained ${drained} pre-existing deliveries in ${guard} batch(es) before measuring\n`);
if (guard > 60) { console.error('backlog did not drain in 60 batches — investigate before trusting this gate'); process.exit(2); }

// ── 1. the column DEFAULT populates correlation_id with no writer changed ───────────────────────
// occurred_at is deliberately 30 DAYS OLD. Under the old body this event was permanently
// undeliverable: the loop filtered occurred_at > now() - 1440 minutes, so an event that missed its
// window could never be picked up again however long the subscription lived.
await wr(`insert into company_event (event_type, entity_type, entity_id, actor, payload, occurred_at)
  values ('${EVT_DECLARED}', 'fixture', '${TAG}-1', '${TAG}', '{"tag":"${TAG}"}'::jsonb, now() - interval '30 days'),
         ('${EVT_UNDECLARED}', 'fixture', '${TAG}-2', '${TAG}', '{"tag":"${TAG}"}'::jsonb, now() - interval '30 days')`,
  'fixture events');

const corr = await rd(`select count(*) from company_event where actor='${TAG}' and correlation_id is not null`);
step('correlation_id is set by the column DEFAULT, no writer touched', String(corr) === '2',
  `${corr}/2 fixture events carry a correlation_id`);

const distinctCorr = await rd(`select count(distinct correlation_id) from company_event where actor='${TAG}'`);
step('two unrelated events start two SEPARATE chains', String(distinctCorr) === '2',
  `${distinctCorr} distinct correlation_id across 2 events`);

// ── 2. an event raised INSIDE a dispatch context inherits the chain and names its cause ─────────
const rootId = await rd(`select id::text from company_event where actor='${TAG}' and entity_id='${TAG}-1'`);
const rootCorr = await rd(`select correlation_id::text from company_event where id=${rootId}`);
await wr(`select set_config('app.correlation_id', '${rootCorr}', false);
          select set_config('app.causation_event_id', '${rootId}', false);
          insert into company_event (event_type, entity_type, entity_id, actor, payload)
          values ('${EVT_DECLARED}', 'fixture', '${TAG}-child', '${TAG}', '{}'::jsonb);
          select set_config('app.correlation_id', '', false);
          select set_config('app.causation_event_id', '', false);`, 'caused event');

const inherited = await rd(`select (correlation_id::text = '${rootCorr}')::text || '/' || (causation_id = ${rootId})::text
  from company_event where actor='${TAG}' and entity_id='${TAG}-child'`);
step('an event caused by another inherits correlation AND names causation', inherited === 'true/true',
  `correlation matches / causation points at the root: ${inherited}`);

// ── 3. run the real dispatcher ──────────────────────────────────────────────────────────────────
const res = await rd(`select public.fn_event_dispatch()::text`);
console.log(`\n  fn_event_dispatch() -> ${res}\n`);
step('the dispatcher runs at all (call-time, not a DO-block success)', !!res && res.includes('delivered'), String(res).slice(0, 90));

// ── 4. xos-02: a 30-day-old event IS delivered now ──────────────────────────────────────────────
const delivered = await rd(`select count(*) from event_delivery d
  join company_event e on e.id = d.event_id where e.actor='${TAG}'`);
step('xos-02 a 30-day-old undelivered event is delivered (no time wall)', Number(delivered) >= 3,
  `${delivered} deliveries for fixture events (>=3 expected)`);

// ── 5. xos-03: the delivery names the OPERATING SYSTEM, not only the agent ──────────────────────
const withOs = await rd(`select count(*) from event_delivery d join company_event e on e.id=d.event_id
  where e.actor='${TAG}' and d.agent_key='${AGENT}' and d.os_key='${OS}'`);
step('xos-03 delivery resolves the subscriber to an Operating System', Number(withOs) >= 2,
  `${withOs} deliveries carry os_key=${OS}`);

// ── 6. xos-05: the unroutable subscriber says WHY, instead of a silent NULL task_id ─────────────
const unroutable = await rd(`select coalesce(max(unroutable_reason),'(none)') from event_delivery d
  join company_event e on e.id=d.event_id where e.actor='${TAG}' and d.agent_key='${TAG}_orphan'`);
step('xos-05 an unroutable subscriber records a reason, not a NULL', unroutable.includes('no org_agents row'),
  unroutable.slice(0, 70));

const orphanTask = await rd(`select count(*) from event_delivery d join company_event e on e.id=d.event_id
  where e.actor='${TAG}' and d.agent_key='${TAG}_orphan' and d.task_id is not null`);
step('xos-05 and it creates no task it cannot assign', String(orphanTask) === '0',
  `${orphanTask} tasks for the orphan (0 expected)`);

// ── 7. xos-04: impact assessed BEFORE acting, and it names a real responsibility ────────────────
const assessed = await rd(`select count(*) from event_assessment a join company_event e on e.id=a.event_id
  where e.actor='${TAG}'`);
step('xos-04 an impact assessment is written per (event, OS)', Number(assessed) >= 2,
  `${assessed} assessments`);

const sev = await rd(`select a.severity from event_assessment a join company_event e on e.id=a.event_id
  where e.actor='${TAG}' and e.event_type='${EVT_DECLARED}' limit 1`);
const declaredSev = await rd(`select coalesce(max(severity),'(none)') from os_interface
  where os_key='${OS}' and event_type='${EVT_DECLARED}' and direction='input'`);
// No "(none)" escape hatch: the pair was chosen precisely so a declared severity exists, so if
// os_interface has nothing to say here the fixture itself is broken and this MUST fail.
step('xos-04 severity is the OS\'s OWN declared reading of that input',
  declaredSev !== '(none)' && sev === declaredSev,
  `assessment=${sev} os_interface=${declaredSev}`);

// The assessment must name something the OS actually owns. Without this the impact string could be
// a fixed template and every check above would still pass.
const impactReal = await rd(`select count(*) from event_assessment a join company_event e on e.id=a.event_id
  where e.actor='${TAG}' and exists (
    select 1 from os_responsibility r where r.os_key=a.os_key and a.impact like '%'||r.responsibility||'%')`);
step('xos-04 the impact names a REAL os_responsibility row, not a template', Number(impactReal) >= 1,
  `${impactReal} assessments quote a real responsibility`);

const undeclared = await rd(`select coalesce(max(a.proposed_action),'(none)') from event_assessment a
  join company_event e on e.id=a.event_id where e.actor='${TAG}' and e.event_type='${EVT_UNDECLARED}'`);
step('comp-07 an UNDECLARED input is flagged as drift, not silently accepted',
  undeclared.includes('UNDECLARED INPUT'), undeclared.slice(0, 70));

// ── 8. the task still gets made, and carries the assessment ─────────────────────────────────────
const task = await rd(`select coalesce(max(t.detail),'(none)') from org_tasks t
  join event_delivery d on d.task_id = t.id join company_event e on e.id = d.event_id
  where e.actor='${TAG}' and d.agent_key='${AGENT}'`);
step('xos-05 the routable subscriber still gets its task', task !== '(none)', task.slice(0, 60));
step('xos-04 and the task text carries the assessed impact', task.includes('Assessed impact:'),
  task.includes('Assessed impact:') ? 'present in task detail' : 'MISSING from task detail');

// ── 9. the session must not leak a correlation after the loop ───────────────────────────────────
const leaked = await rd(`select coalesce(nullif(current_setting('app.correlation_id', true),''),'(clear)')`);
step('the dispatcher leaves no correlation bound to the session', leaked === '(clear)', leaked);

await cleanup();
const failed = checks.filter(c => !c.ok);
console.log(`\nEVENT CONTRACT on ${STAGE}: ${checks.length - failed.length}/${checks.length}`);
for (const f of failed) console.log(`  FAILED  ${f.name} — ${f.detail}`);
process.exit(failed.length ? 1 : 0);
