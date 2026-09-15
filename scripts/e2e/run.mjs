// scripts/e2e/run.mjs — ONE command: create demo identities, drive both portals, report, clean up.
// Assigned: ceo (it_engineer's tooling, carried out for the ceo). Documented in docs/e2e.md.
//
//   node scripts/e2e/run.mjs                 every journey (a-f)
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
import { openRun, closeRun, makeDemoCustomer, makeDemoSupplier, read, REF } from './fixtures.mjs';
import { launch, SITE } from './browser.mjs';
import { JOURNEYS } from './journeys.mjs';
import { newRun, teardown } from '../staging/demo_factory.mjs';

const argv = process.argv.slice(2);
const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const KEEP = argv.includes('--keep');
const only = (val('--journey') || 'a,b,c,d,e,f,g').split(',').map((s) => s.trim()).filter(Boolean);

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');
const MAIN = REPO.replace(/[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$/, '');
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const DIR = join(process.env.QD_E2E_REPORTS || join(MAIN, 'e2e-reports'), stamp);

process.env.QD_FIXTURES = '1';

if (val('--purge-tag')) {
  const t = await teardown(newRun({ tag: val('--purge-tag'), quiet: true }));
  console.log('torn down:', t.summary);
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
const run = await openRun({ keep: KEEP });
const ctx = { run, rep, dir: DIR, consoleErrors: [], fx: {} };
let browser = null, closed = null, fatal = null;
try {
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
      r.company_name && r.phone && r.license_doc_path && r.trade_license_no && r.products && r.accepted_terms_version === r.current_terms && r.is_demo && r.approval_status === 'approved' ? 'PASS' : 'FAIL',
      `is_demo=${r.is_demo} approval=${r.approval_status} licence=${r.license_doc_path ? 'uploaded' : 'none'} agreement=${r.accepted_terms_version}/${r.current_terms} signed=${r.signed}`);
  }
  browser = await launch();
  ctx.browser = browser;
  for (const k of ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
    if (!only.includes(k)) continue;
    try { await JOURNEYS[k](ctx); }
    catch (e) { rep.step(`${k}`, 'journey crashed', 'FAIL', String(e.stack || e.message).split('\n').slice(0, 3).join(' | ')); }
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
  `**${count('PASS')} passed · ${count('FAIL')} failed · ${count('SKIP')} skipped**`, '',
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
const result = {
  version: 1, ok: count('FAIL') === 0 && !fatal, tag: run.tag, site: SITE, project: REF, started: stamp, seconds: secs,
  journeys: only, kept: KEEP, pass: count('PASS'), fail: count('FAIL'), skip: count('SKIP'),
  report: join(DIR, 'report.md'), purge: KEEP ? `node scripts/e2e/run.mjs --purge-tag ${run.tag}` : null,
  steps: steps.map((s) => ({ journey: s.journey, name: s.name, status: s.status, detail: s.detail, ms: s.ms ?? null })),
};
writeFileSync(join(DIR, 'result.json'), JSON.stringify(result, null, 1));
if (argv.includes('--json')) console.log(JSON.stringify({ ...result, steps: undefined, result: join(DIR, 'result.json') }));
// Read by scripts/e2e/report_to_it_engineer.mjs, which hands this run to the IT engineer.
writeFileSync(join(DIR, 'run.json'), JSON.stringify({ tag: run.tag, kept: KEEP, leftovers: closed?.leftovers ?? null }));
console.log(`\nE2E ${count('PASS')} passed, ${count('FAIL')} failed, ${count('SKIP')} skipped - report ${join(DIR, 'report.md')}`);
process.exitCode = count('FAIL') === 0 && !fatal ? 0 : 1;
