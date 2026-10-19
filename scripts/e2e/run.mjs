// scripts/e2e/run.mjs — ONE command: create demo identities, drive both portals, report, clean up.
// Assigned: ceo (it_engineer's tooling, carried out for the ceo). Documented in docs/e2e.md.
//
//   node scripts/e2e/run.mjs                 every journey (a-h)
//   node scripts/e2e/run.mjs --journey a,f   only these (the funnel's later journeys need a and b)
//   node scripts/e2e/run.mjs --keep          leave the run's rows in place (tear down later with --purge-tag <tag>)
//   node scripts/e2e/run.mjs --purge-tag <tag>
//
// Output: <reports>/<timestamp>/report.md + screenshots, where <reports> is QD_E2E_REPORTS or the main
// checkout's e2e-reports/ (git-ignored). The exit code is 0 only when nothing FAILED and nothing was left behind.
//
// SAFE TO RE-RUN, AND INCAPABLE OF REACHING A REAL PERSON. It refuses to start unless the database's
// demo capture (zzzz_notifications_demo_capture) and pairing guard are installed, every identity it makes
// is on a reserved domain and the reserved mobile block, it declares a rehearsal window so the
// failed-run watcher never pages the founder, and after the run it asserts that NOTHING it caused was
// dispatched and NOTHING it created survived.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, sweepStaleRuns, read, REF } from './fixtures.mjs';
import { launch, SITE, HARNESS_SIGNED_OUT } from './browser.mjs';
import { JOURNEYS } from './journeys.mjs';
import { runIsComplete } from './run_scope.mjs';
import { newRun, teardown, closeRehearsalWindow } from '../lib/demo_factory.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const KEEP = argv.includes('--keep');
// ONE list of journeys, in the order they run. h (the 21 Sep audit's presses) runs right after the
// funnel it needs (a quote, a TEST reveal) and BEFORE the crawl, which is the journey the deadline cuts.
const ORDER = ['a', 'b', 'c', 'd', 'e', 'h', 'f', 'g'];
const only = (val('--journey') || ORDER.join(',')).split(',').map((s) => s.trim()).filter(Boolean);

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const MAIN = REPO.replace(/[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$/, '');
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const DIR = join(process.env.QD_E2E_REPORTS || join(MAIN, 'e2e-reports'), stamp);

process.env.QD_FIXTURES = '1';

if (val('--purge-tag')) {
  const t = await teardown(newRun({ tag: val('--purge-tag'), quiet: true }));
  console.log('torn down:', t.summary);
  // a purged run is over: its window closes too (a run killed before its finally left one open)
  await closeRehearsalWindow(val('--purge-tag'));
  console.log('rehearsal window closed');
  process.exit(0);
}

// ---- the report --------------------------------------------------------------------------------
const steps = [];
const rep = {
  step(journey, name, status, detail, extra = {}) {
    steps.push({ journey, name, status, detail: String(detail ?? ''), ...extra });
    console.log(`${status.padEnd(4)} [${journey}] ${name} — ${String(detail ?? '').slice(0, 160)}`);
  },
};

// ---- preflight: refuse to run unless nothing can reach a real person ------------------------------
const guards = (await read(`select tgname from pg_trigger where not tgisinternal and tgname in
  ('zzzz_notifications_demo_capture','a01_inquiry_match_demo_and_real_never_pair','a01_quote_demo_and_real_never_pair')`)).map((r) => r.tgname);
if (guards.length !== 3) {
  console.error(`REFUSED: the demo guards are not installed on ${REF} (found ${guards.join(', ') || 'none'}). ` +
    'Apply scripts/sql/demo_identities_are_marked_and_never_reach_a_real_person.sql first - without it a fixture mobile could reach Twilio.');
  process.exit(2);
}

mkdirSync(DIR, { recursive: true });
const t0 = Date.now();
// A WALL CLOCK, BECAUSE THE JOB HAS ONE (17 Sep 2026, measured). The nightly workflow gives this
// harness a 30-minute job; nothing here was bounded against it. On 15/16 and 16/17 Sep the crawl
// spent 11.2 s on each nav item it could not click (8 s click timeout + retries) and the job was
// CANCELLED at the wall — which skips every remaining step, so teardown never ran and
// report_to_it_engineer.mjs never wrote the heartbeat. The visible consequences: the IT engineer
// raised duty:journey_heartbeat:no_run for three days while the test was in fact running nightly,
// and two runs' demo identities (tags 8a5b7ad5 and 414bbb3e — 6 leads, 2 customers) survived as
// duty:demo leftovers. A cancelled job reports nothing at all; a truncated run reports what it saw.
// So the harness stops STARTING new work at its own deadline and always reaches teardown and the
// report below. Skipped work is recorded as SKIP with the reason, never silently dropped.
//
// A MALFORMED VALUE MUST NOT SILENTLY RESTORE THE BUG (review). `Number('20m')` is NaN, and
// `Date.now() > NaN` is false forever — an unbounded harness again, with nothing in the log to say
// so. A deadline that can be switched off by a typo in a workflow file is not a deadline.
const DEADLINE_MS = Number(process.env.QD_E2E_DEADLINE_MS || 20 * 60 * 1000);
if (!Number.isFinite(DEADLINE_MS) || DEADLINE_MS <= 0) {
  console.error(`REFUSED: QD_E2E_DEADLINE_MS=${JSON.stringify(process.env.QD_E2E_DEADLINE_MS)} is not a positive number of milliseconds. ` +
    'Running without a deadline is what let the job be cancelled mid-crawl, taking teardown and the heartbeat with it.');
  process.exit(2);
}
const DEADLINE = t0 + DEADLINE_MS;
// TRUNCATION IS A FACT THE REPORT MUST CARRY, NOT A DETAIL IN A STRING. fn_it_journey_ingest hands
// the failing steps to fn_it_duty_settle, which CLOSES every open duty:journey:% finding that is
// not in this run's failing set — "the journey duty no longer finds it". A run that stopped early
// did not look at those steps, so settling on it would close real, unverified defects: the exact
// "could not look read as all clear" fault the duty engine was built to avoid. So the harness says
// plainly whether it looked at everything, and the ingest only settles when it did.
const state = { truncated: false };
const outOfTime = () => { if (Date.now() <= DEADLINE) return false; state.truncated = true; return true; };
// Ledger 1247: no spend limit on tests (USD 15 = the CHECK maximum). Measured: avg 0.146, max 0.431 per run (13 runs, 30 days to 18 Oct 2026).
const run = await openRun({ keep: KEEP });
const ctx = { run, rep, dir: DIR, consoleErrors: [], fx: {}, deadline: DEADLINE, outOfTime };
let browser = null, closed = null, fatal = null;
// Set when the harness's OWN session died mid-run (browser.mjs HarnessSignedOut). It is kept apart
// from `fatal` because it says something different: not "the run broke" but "the run's evidence is
// not about the product". It makes the run INCOMPLETE below, so no finding may be closed on it.
let harnessDead = null;
// What the run did per journey. `attempted` = started, not cut by the deadline or a dead harness;
// `finished` = returned without throwing. COMPLETE needs every journey asked for attempted
// (run_scope.mjs); the ingest settles ONLY the keys of finished journeys (run.json journeys), so a
// crash or a --journey subset never closes a finding of a journey that did not run to its end.
const attempted = new Set(), finished = new Set();
try {
  // Runs that are OVER still holding fixtures go first, by their exact tags (fixtures.mjs staleRunTags):
  // on 22 Sep two such runs' ZZ DEMO suppliers took all three routing slots for this run's request.
  // A sweep that throws is reported and the run goes on; the routing step then names whose fixtures
  // took the slots.
  const swept = await sweepStaleRuns().catch((e) => ({ error: String(e.message).slice(0, 200) }));
  rep.step('fixtures', 'fixtures of runs that are over are removed before this run starts', swept.error ? 'FAIL' : 'PASS',
    swept.error || (swept.length ? swept.map((s) => `${s.tag}: ${s.summary}`).join(' | ') : 'none left behind'));
  // Identities: one customer, three suppliers (A holds then releases, B quotes two options, C is complete).
  ctx.fx.customer = await makeDemoCustomer(run, { label: 'Customer' });
  const c = ctx.fx.customer.row;
  rep.step('fixtures', 'demo customer complete (name, 18+ DOB, email+mobile verified, current terms signed)',
    c.full_name && c.date_of_birth && c.email_verified && c.phone_verified && c.tos_version === c.current_terms && c.is_demo ? 'PASS' : 'FAIL',
    `is_demo=${c.is_demo} dob=${c.date_of_birth} email_verified=${c.email_verified} phone_verified=${c.phone_verified} terms=${c.tos_version}/${c.current_terms} signed=${c.signed}`);
  ctx.fx.suppliers = [];
  for (const label of ['A', 'B', 'C']) {
    const s = await makeDemoSupplier(run, { label, trade: 'aluminium' });
    ctx.fx.suppliers.push(s);
    const r = s.row;
    rep.step('fixtures', `demo supplier ${label} has the mandatory six`,
      r.company_name && r.phone && r.license_doc_path && r.company_profile_doc_path && r.trade_license_no && r.products && r.accepted_terms_version === r.current_terms && r.is_demo && r.approval_status === 'approved' && r.missing?.length === 0 ? 'PASS' : 'FAIL',
      `is_demo=${r.is_demo} approval=${r.approval_status} missing=${JSON.stringify(r.missing)} licence=${r.license_doc_path ? 'uploaded' : 'none'} profile=${r.company_profile_doc_path ? 'uploaded' : 'none'} agreement=${r.accepted_terms_version}/${r.current_terms} signed=${r.signed}`);
  }
  browser = await launch();
  ctx.browser = browser;
  for (const k of ORDER) {
    if (!only.includes(k)) continue;
    if (outOfTime()) { rep.step(`${k}`, 'journey not started', 'SKIP', `the ${Math.round((DEADLINE - t0) / 60000)}-minute harness deadline passed before this journey; teardown and the report run so the heartbeat still reaches the IT engineer`); continue; }
    attempted.add(k);
    try { await JOURNEYS[k](ctx); finished.add(k); }
    catch (e) {
      // A DEAD HARNESS SESSION IS NOT A PRODUCT DEFECT, AND MUST NOT BE COUNTED AS ONE. Folded into
      // "journey crashed" it becomes one more FAIL in a tally that is read as N defects — the same
      // mislabelling browser.mjs throws HarnessSignedOut to stop, undone at the last step. It is
      // named separately here, and it stops the run: every later journey shares this browser and
      // would only reproduce the same failure, each one adding noise on top of the real cause.
      if (e && e.name === 'HarnessSignedOut') {
        harnessDead = String(e.message).split('\n')[0];
        rep.step(`${k}`, `${HARNESS_SIGNED_OUT} — this run proves nothing about the product`, 'FAIL', harnessDead);
        break;
      }
      rep.step(`${k}`, 'journey crashed', 'FAIL', String(e.stack || e.message).split('\n').slice(0, 3).join(' | '));
    }
  }

  // Nothing this run caused was dispatched.
  const ids = (s) => [...s].map((x) => `'${x}'`).join(',') || 'null';
  const out = await read(`select status, channel, count(*)::int n from public.notifications
     where to_email like 'qd-${run.tag}-%' or lead_id::text in (${ids(run.ids.leads)}) or inquiry_id::text in (${ids(run.ids.inquiries)}) or quote_id::text in (${ids(run.ids.quotes)})
     group by 1, 2 order by 1, 2`);
  const sent = out.filter((r) => ['sent', 'queued', 'pending'].includes(r.status)).reduce((a, r) => a + r.n, 0);
  rep.step('safety', 'nothing the run caused was dispatched', sent === 0 ? 'PASS' : 'FAIL',
    out.map((r) => `${r.channel}/${r.status}: ${r.n}`).join(', ') || 'no notification rows');
} catch (e) {
  fatal = e;
  rep.step('run', 'fixture setup failed', 'FAIL', String(e.stack || e.message).split('\n').slice(0, 3).join(' | '));
} finally {
  if (browser) await browser.close().catch(() => {});
  closed = await closeRun(run, { keep: KEEP }).catch((e) => ({ error: String(e.message) }));
  if (KEEP) rep.step('cleanup', 'run kept', 'SKIP', `tear down later: node scripts/e2e/run.mjs --purge-tag ${run.tag}`);
  else if (closed?.error) rep.step('cleanup', 'teardown', 'FAIL', closed.error);
  else rep.step('cleanup', 'zero leftovers', closed.leftovers.total === 0 ? 'PASS' : 'FAIL',
    `removed: ${closed.removed.summary}; leftovers: ${JSON.stringify(closed.leftovers)}`);
}

// ---- write the report --------------------------------------------------------------------------
const count = (s) => steps.filter((x) => x.status === s).length;
const secs = Math.round((Date.now() - t0) / 1000);
const md = [
  `# QuotesDone e2e run ${stamp}`, '',
  `Site ${SITE} · project ${REF} · run tag \`${run.tag}\` · ${secs}s · journeys ${only.join(',')}${KEEP ? ' · KEPT' : ''}`, '',
  `**${count('PASS')} passed · ${count('FAIL')} failed · ${count('HELD')} held by the model hold · ${count('SKIP')} skipped**`, '',
  '| # | journey | step | result | detail | ms |', '|---|---|---|---|---|---|',
  ...steps.map((s, i) => `| ${i + 1} | ${s.journey} | ${s.name.replace(/\|/g, '/')} | ${s.status} | ${s.detail.replace(/\|/g, '/').replace(/\n/g, ' ').slice(0, 300)} | ${s.ms ?? ''} |`),
  '', '## Console errors', '', ...(ctx.consoleErrors.length ? [...new Set(ctx.consoleErrors)].slice(0, 80).map((e) => `- ${e.replace(/\n/g, ' ')}`) : ['none']),
  '', '## Screenshots', '', ...steps.filter((s) => s.shot).map((s) => `- ${s.name}: ${s.shot.split(/[\\/]/).pop()}`),
];
writeFileSync(join(DIR, 'report.md'), md.join('\n'));
writeFileSync(join(DIR, 'steps.json'), JSON.stringify(steps, null, 1));
// A STABLE RESULT FOR WHOEVER RUNS THIS UNATTENDED (14 Sep 2026): the nightly it_engineer duty reads
// this file, hands each FAIL to the seat that owns it, and re-runs to verify. The shape is a contract:
// add fields, never rename or remove one.
// COMPLETE = this run looked at everything it is supposed to look at. False when the deadline cut
// it short, and false when --journey asked for only part of the funnel: in both cases the steps it
// did not reach say nothing about the defects they would have found, so nothing may be closed on
// their silence. `ok` carries it too — a truncated run that happened to fail nothing is not a pass.
// A run whose own session died is INCOMPLETE for the same reason a truncated one is: the steps after
// it stopped say nothing about the defects they would have found, so nothing may be closed on their
// silence — and here the steps BEFORE it are suspect too, which is why it is reported, not hidden.
const COMPLETE = runIsComplete({ truncated: state.truncated, harnessDead, only, attempted });
const RAN = ORDER.filter((k) => finished.has(k));
const result = {
  version: 1, ok: count('FAIL') === 0 && !fatal && COMPLETE, complete: COMPLETE, truncated: state.truncated,
  harness_signed_out: harnessDead,
  tag: run.tag, site: SITE, project: REF, started: stamp, seconds: secs,
  journeys: only, kept: KEEP, pass: count('PASS'), fail: count('FAIL'), held: count('HELD'), skip: count('SKIP'),
  report: join(DIR, 'report.md'), purge: KEEP ? `node scripts/e2e/run.mjs --purge-tag ${run.tag}` : null,
  steps: steps.map((s) => ({ journey: s.journey, name: s.name, status: s.status, detail: s.detail, ms: s.ms ?? null })),
};
writeFileSync(join(DIR, 'result.json'), JSON.stringify(result, null, 1));
if (argv.includes('--json')) console.log(JSON.stringify({ ...result, steps: undefined, result: join(DIR, 'result.json') }));
// Read by scripts/e2e/report_to_it_engineer.mjs, which hands this run to the IT engineer.
writeFileSync(join(DIR, 'run.json'), JSON.stringify({ tag: run.tag, kept: KEEP, leftovers: closed?.leftovers ?? null, complete: COMPLETE, journeys: RAN, harness_signed_out: harnessDead }));
console.log(`\nE2E ${count('PASS')} passed, ${count('FAIL')} failed, ${count('HELD')} held, ${count('SKIP')} skipped - report ${join(DIR, 'report.md')}`);
// The same verdict result.ok carries, so the two cannot drift apart: a truncated run is not a pass,
// whoever is reading. (The nightly workflow runs this step with continue-on-error, because a failed
// STEP is the finding and the report below it must still run — so this exit code is for a human.)
process.exitCode = result.ok ? 0 : 1;
