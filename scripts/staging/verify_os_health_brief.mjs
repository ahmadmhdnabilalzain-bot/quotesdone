// Fixture gate for fn_os_health_brief — the reader that closes comp-16's seven dimensions.
//
// The claim being tested is not "a function exists". It is: every one of the seven figures
// fn_os_review writes into os_review.metrics now reaches the human who owns that OS. So this
// runs the function against real staging rows and then reads the effect back IN A SEPARATE
// STATEMENT — a single statement shares one snapshot and would report the pre-call state.
//
//   node scripts/staging/verify_os_health_brief.mjs
import { mgmtRead, mgmtWrite } from './qd_guard.mjs';
import { REF } from './demo_factory.mjs';

const ref = process.argv[2] || REF;
const rd = async (sql) => await mgmtRead(ref, sql);
const one = async (sql) => { const r = await rd(sql); return r[0] ? Object.values(r[0])[0] : null; };

let fail = 0;
const check = (name, ok, ev) => {
  if (!ok) fail++;
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(46)} ${ev}`);
};

console.log(`\nfn_os_health_brief fixture gate on ${ref}\n`);

// 1. RUN IT. Twice — the second run proves the delete-by-source keeps this idempotent instead of
//    growing one memory row per OS per week until the prompt is nothing but old health briefs.
const r1 = await mgmtWrite(ref, `select public.fn_os_health_brief() as out;`);
const r2 = await mgmtWrite(ref, `select public.fn_os_health_brief() as out;`);
console.log(`  run 1: ${JSON.stringify(r1[0].out)}`);
console.log(`  run 2: ${JSON.stringify(r2[0].out)}`);

// 2. One brief per active OS whose owner is an active employee.
const expected = await one(`select count(*)::text from public.operating_system o
  join public.org_agents a on a.agent_key = o.owner_agent and a.active
  join public.os_review r on r.os_key = o.os_key
                         and r.period = (select max(period) from public.os_review)
  where o.active`);
const got = await one(`select count(*)::text from public.agent_memory
  where source = 'fn_os_health_brief'`);
check('one brief per owned, reviewed, active OS', got === expected && Number(got) > 0,
  `${got} brief(s), ${expected} eligible OS — equal after two runs, so it is idempotent`);

// 3. Every one of the SEVEN comp-16 dimensions is named in every brief. Named, because a figure
//    the reader cannot identify is not a figure that was reported; the label is the payload.
const DIMS = ['open_risks', 'kpi_gaps', 'capacity_pct', 'stale_tasks', 'backlog_per_head',
              'review_pass_pct', 'budget_pct', 'needs_founder_pct'];
for (const d of DIMS) {
  const n = await one(`select count(*)::text from public.agent_memory
    where source='fn_os_health_brief' and content like '%${d} %'`);
  check(`every brief names ${d}`, n === got, `${n} of ${got}`);
}

// 4. It is a NUMBER, not the word. 'open_risks 3' — the label followed by a digit or a null-safe
//    'unmeasured'. A brief that says "open_risks" and no value reports nothing.
const numeric = await one(`select count(*)::text from public.agent_memory
  where source='fn_os_health_brief'
    and content ~ 'open_risks [0-9]' and content ~ 'kpi_gaps [0-9]'
    and content ~ 'backlog_per_head [0-9]' and content ~ 'stale_tasks [0-9]'
    and content ~ 'budget_pct [0-9]' and content ~ 'needs_founder_pct [0-9]'
    and content ~ '(capacity_pct ([0-9]|unmeasured))'
    and content ~ '(review_pass_pct ([0-9]|unmeasured))'`);
check('every dimension carries a value, not a label', numeric === got, `${numeric} of ${got}`);

// 5. THE POINT OF THE WHOLE THING: it reaches the employee. fn_agent_context is what an agent is
//    actually handed, and it only carries agent_memory at importance >= 5.
const owner = await one(`select o.owner_agent from public.operating_system o
  join public.agent_memory m on m.agent_key = o.owner_agent and m.source='fn_os_health_brief'
  where o.active order by o.num limit 1`);
const inPrompt = await one(`select public.fn_agent_context('${owner}', 22000) like '%OS HEALTH, week %'`);
check(`the brief reaches ${owner}'s prompt`, String(inPrompt) === 'true',
  `fn_agent_context('${owner}') carries it: ${inPrompt}`);

// 6. And it is a READER of os_review, live on a cron — which is what makes the figure "read"
//    rather than merely stored a second time.
const live = await one(`select (exists (select 1 from cron.job j
    where j.active and j.command ~* '\\yfn_os_health_brief\\y'))::text`);
check('scheduled on an active cron', String(live) === 'true', `cron.job active: ${live}`);

console.log(`\n${fail ? `FAILED — ${fail} check(s)` : 'ALL CHECKS PASSED'}\n`);
process.exit(fail ? 1 : 0);
