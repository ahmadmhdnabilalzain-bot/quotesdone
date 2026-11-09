// THE PR GATE, RUN FROM A WORKTREE (it_engineer, 26 Oct 2026).
//
// Founder, 26 Oct 2026: Ubicloud is stopped and no paid service runs CI, GitHub-hosted Actions minutes included,
// until the bugs are cleared; Claude sessions run the checks themselves. Every workflow is workflow_dispatch only.
// This runs the same commands the PR-gate jobs ran, from the files that define them:
//   checks.yml          checks, migration-lint, typecheck, deno-check, otp-race
//   project-parity.yml  parity, kernel-gate (both need SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token)
// and prints ONE PASS/FAIL table. Exit 1 on any FAIL. A step that cannot run (no token, no Postgres for the OTP
// race) is a FAIL, never a quiet pass; only a step named in --skip is left out, and the table says so.
//
//   npm run gate                                  # everything
//   npm run gate -- --pr 1601                     # and post the table on PR #1601 (gh api REST, works where GraphQL is blocked)
//   npm run gate -- --skip=otp-race,audit         # leave named steps out, shown as SKIPPED (named)
//   npm run gate -- --daily                       # also the daily-only step: every deployed function runs main
//   npm run gate -- --offline                     # only the steps that need no production credential; every
//                                                 # production step is listed as SKIPPED (offline), never PASS.
//                                                 # What `docker compose run --rm checks` runs (docs/runbooks/docker.md).
//
// Offline steps run in parallel; production steps run one after another (the management API's 429 budget, and
// the kernel gate's serial rule in project-parity.yml). Logs: <tmp>/qd-gate-<time>/<id>.log.
import { spawn, spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const arg = (name) => { const i = argv.findIndex((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  return i < 0 ? null : argv[i].includes('=') ? argv[i].split('=').slice(1).join('=') : (argv[i + 1] ?? ''); };
const PR = arg('pr');
if (PR !== null && !/^\d+$/.test(PR)) { console.error('--pr needs a pull request number'); process.exit(2); }
const SKIP = new Set((arg('skip') || '').split(',').map((s) => s.trim()).filter(Boolean));
const DAILY = argv.includes('--daily');
const OFFLINE = argv.includes('--offline');
const LOGS = join(tmpdir(), `qd-gate-${new Date().toISOString().replace(/[:.]/g, '-')}`);
mkdirSync(LOGS, { recursive: true });

// --offline treats the credential as absent even when one is present, so npm test stays an offline run too.
const TOKEN = !OFFLINE && (!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token')));
const DENO = 'deno test --no-lock --node-modules-dir=auto --allow-read=.';
const env = { DENO_NO_PACKAGE_JSON: '1' };   // checks.yml / project-parity.yml workflow env (12 Oct 2026)
// A production check that answers SKIP has asserted nothing; in the kernel gate that is a failure (project-parity.yml).
const SKIPPED = /^SKIP|^SKIPPED|NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL|# SKIPPED/m;

const migrations = () => (existsSync(join(REPO, 'supabase/migrations')) ? readdirSync(join(REPO, 'supabase/migrations')) : [])
  .filter((f) => f.endsWith('.sql') && !f.includes('_baseline_')).map((f) => `supabase/migrations/${f}`);

// [id, workflow job, name, command | () => command | null (nothing to run, passes with a note), opts]
const STEPS = [
  // With a token, npm test also runs every production check the CI job skipped, one at a time (the 429 budget), including every_seat_reads_its_verified_pack's live eval (up to 60 min): measured >90 min on 26 Oct.
  ['npm-test', 'checks', 'npm test: node --test over scripts/checks + the deno suite', 'npm test', { minutes: 180 }],
  ['ssrf', 'checks', 'the SSRF guard fires on a private address, file:// and metadata', 'node scripts/checks/ssrf_guard_refuses_private_addresses.mjs'],
  ['fetch-timeout', 'checks', 'no new outbound fetch without a deadline', 'node scripts/checks/every_outbound_fetch_has_a_timeout.mjs'],
  ['dwg', 'checks', 'a DWG is read into the same take-off as its DXF', `${DENO} --allow-net=raw.githubusercontent.com,registry.npmjs.org supabase/functions/_shared/doc_read/dwg_samples.check.ts`],
  ['redact-page', 'checks', 'a redacted drawing page covers every identity', `${DENO} --allow-net=deno.land supabase/functions/_shared/drawing_redact_page.check.ts`],
  ['scan-redact', 'checks', 'a scanned drawing is redacted by OCR, or held', `${DENO} --allow-env --allow-net=deno.land supabase/functions/_shared/scan_redact.check.ts`],
  ['scan-takeoff', 'checks', 'a scanned PDF set is counted by OCR to the hand count', `${DENO} --allow-env --allow-net=deno.land,esm.sh supabase/functions/_shared/scan_takeoff.check.ts`],
  ['migration-lint', 'migration-lint', 'lint migrations for locking operations (squawk)', () => { const f = migrations(); return f.length ? `npx squawk ${f.join(' ')}` : null; }],
  ['typecheck', 'typecheck', 'typecheck the app', 'npm run typecheck'],
  ['audit', 'typecheck', 'no HIGH or CRITICAL advisory in a production dependency', 'npm audit --omit=dev --audit-level=high'],
  ['deno-gated', 'deno-check', 'typecheck the gated edge functions', 'deno check --no-lock --node-modules-dir=auto '
    + ['ceo_agent', 'stripe_webhook', 'supplier_pay', 'customer_api', 'supplier_api', 'resend_inbound', 'supplier_catalog_ingest'].map((s) => `supabase/functions/${s}/index.ts`).join(' ')],
  ['deno-all', 'deno-check', 'typecheck every edge function', () => 'deno check --no-lock --node-modules-dir=auto '
    + readdirSync(join(REPO, 'supabase/functions')).filter((d) => existsSync(join(REPO, 'supabase/functions', d, 'index.ts'))).map((d) => `supabase/functions/${d}/index.ts`).join(' ')],
  ['otp-race', 'otp-race', 'a sign-in code survives 5 guesses and verifies once under a burst', 'deno test --no-lock --node-modules-dir=auto --allow-read --allow-write=node_modules --allow-env --allow-net supabase/functions/login_otp/verify_race.check.ts', { postgres: true }],
  // project-parity.yml, job parity: production, serial
  ['receipts', 'parity', 'a forwarded receipt is booked or owned by finance', 'node --test scripts/checks/receipts_never_wait_on_the_founder.test.mjs', { prod: true }],
  ['fn-owner', 'parity', 'every deployed function has exactly one owner', 'node scripts/checks/every_deployed_function_has_an_owner.mjs', { prod: true }],
  ['duty-clock', 'parity', 'complaints, short quotes, reveals and support replies each run on a clock', 'node --test scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs', { prod: true }],
  ['model-matrix', 'parity', 'every model class has a seat and a route in the founder\'s matrix', 'node --test scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs', { prod: true, env: { MATRIX_REQUIRE_LIVE: '1' } }],
  ['registry-sync', 'parity', 'the model catalogue sync is fresh and its rule holds', 'node --test scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs', { prod: true, env: { REGISTRY_SYNC_REQUIRE_LIVE: '1' } }],
  ['manifest', 'parity', 'one canonical file per routine, and it is what is deployed', 'node scripts/checks/canonical_routine_manifest.mjs --all', { prod: true, env: { QD_REQUIRE_GIT_HISTORY: '1' } }],
  ['deploy-parity', 'parity (daily)', 'every deployed edge function runs what main says', 'node scripts/verify_deploy_parity.mjs --all', { prod: true, daily: true }],
  ['export', 'parity', 'the schema export matches the committed schema', 'node scripts/checks/export_from_either_source_is_identical.mjs', { prod: true }],
  ['advisors', 'parity', 'no NEW Supabase security advisor finding since the baseline', 'node scripts/checks/security_advisors_match_the_baseline.mjs --refresh', { prod: true }],
  // exit 1 = a pattern was found and recorded (not this PR's fault, so a warning); exit 2 = the log was unreadable.
  ['edge-logs', 'parity', 'the edge logs show no attack pattern (and are readable)', 'node scripts/checks/edge_requests_show_no_attack_pattern.mjs --record', { prod: true, warnOn: [1] }],
  ['anon-definer', 'kernel-gate', 'anon cannot execute a SECURITY DEFINER routine', 'node scripts/checks/anon_cannot_execute_security_definer.test.mjs', { prod: true, noSkip: true }],
  ['alarms-quiet', 'kernel-gate', 'every alarm is quiet on a healthy day', 'node scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs', { prod: true, noSkip: true }],
].map(([id, job, name, cmd, o = {}]) => ({ id, job, name, cmd, ...o }));

const unknown = [...SKIP].filter((s) => !STEPS.some((x) => x.id === s));
if (unknown.length) { console.error(`--skip names no step: ${unknown.join(', ')}. Steps: ${STEPS.map((s) => s.id).join(', ')}`); process.exit(2); }

function run(step, extraEnv = {}) {
  const cmd = typeof step.cmd === 'function' ? step.cmd() : step.cmd;
  if (cmd === null) return Promise.resolve({ result: 'PASS', note: 'nothing to run (only generated baseline migrations)', secs: 0 });
  const log = join(LOGS, `${step.id}.log`); const t0 = Date.now();
  return new Promise((done) => {
    const p = spawn(cmd, { cwd: REPO, shell: true, detached: process.platform !== 'win32', env: { ...process.env, ...env, ...(step.env || {}), ...extraEnv } });
    let out = '';
    p.stdout.on('data', (d) => { out += d; }); p.stderr.on('data', (d) => { out += d; });
    // The whole tree: with shell: true, p is only the shell, and killing it alone leaves the command running.
    const minutes = step.minutes || 45;   // 45 = the longest job wall in the two workflows
    const kill = setTimeout(() => { if (process.platform === 'win32') spawnSync('taskkill', ['/pid', String(p.pid), '/T', '/F'], { stdio: 'ignore' }); else process.kill(-p.pid, 'SIGKILL'); }, minutes * 60_000);
    p.on('close', (code) => {
      clearTimeout(kill); writeFileSync(log, out);
      const secs = Math.round((Date.now() - t0) / 1000);
      if (step.noSkip && SKIPPED.test(out)) return done({ result: 'FAIL', note: 'skipped for want of a credential', secs, log, out });
      if (code === 0) return done({ result: 'PASS', secs, log });
      if (step.warnOn?.includes(code)) return done({ result: 'PASS', note: `exit ${code}: a pattern was found and recorded in security_events`, secs, log });
      done({ result: 'FAIL', note: code === null || (process.platform === 'win32' && Date.now() - t0 >= minutes * 60_000) ? `killed at ${minutes} min` : `exit ${code}`, secs, log, out });
    });
  });
}

// The OTP race needs a throwaway Postgres, never production. QD_OTP_RACE_PG wins; else docker starts postgres:16.
async function withPostgres(step) {
  if (process.env.QD_OTP_RACE_PG) return run(step, { QD_OTP_RACE_PG: process.env.QD_OTP_RACE_PG });
  if (spawnSync('docker', ['info'], { stdio: 'ignore', shell: true }).status !== 0)
    return { result: 'FAIL', note: 'no Postgres: set QD_OTP_RACE_PG or start Docker (or --skip=otp-race)', secs: 0 };
  const name = `qd-gate-otp-${process.pid}`;
  const up = spawnSync('docker', ['run', '-d', '--rm', '--name', name, '-e', 'POSTGRES_PASSWORD=race', '-p', '127.0.0.1:55432:5432', 'postgres:16'], { encoding: 'utf8', shell: true });
  if (up.status !== 0) return { result: 'FAIL', note: `docker could not start postgres:16: ${String(up.stderr).trim().slice(0, 120)}`, secs: 0 };
  try {
    for (let i = 0; i < 60 && spawnSync('docker', ['exec', name, 'pg_isready', '-U', 'postgres'], { stdio: 'ignore', shell: true }).status !== 0; i++) await new Promise((r) => setTimeout(r, 1000));
    return await run(step, { QD_OTP_RACE_PG: 'postgres://postgres:race@127.0.0.1:55432/postgres' });
  } finally { spawnSync('docker', ['rm', '-f', name], { stdio: 'ignore', shell: true }); }
}

const results = new Map();
const pick = (s) => {
  if (SKIP.has(s.id)) return { result: 'SKIPPED', note: 'named in --skip', secs: 0 };
  if (s.daily && !DAILY) return { result: 'SKIPPED', note: 'daily only (--daily)', secs: 0 };
  if (s.prod && OFFLINE) return { result: 'SKIPPED', note: 'production step, --offline', secs: 0 };
  if (s.prod && !TOKEN) return { result: 'FAIL', note: 'no SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token', secs: 0 };
  return null;
};
const head = execOut('git rev-parse --short=12 HEAD'); const branch = execOut('git rev-parse --abbrev-ref HEAD');
function execOut(c) { return String(spawnSync(c, { cwd: REPO, shell: true, encoding: 'utf8' }).stdout || '').trim(); }
const SLUG = execOut('git remote get-url origin').match(/github\.com[/:]([^/]+\/[^/.]+?)(?:\.git)?$/)?.[1];
// A PASS posted to a PR certifies that PR's code: refuse when the tree is dirty or HEAD is not the PR's head.
if (PR !== null) {
  // An offline run asserts nothing about production, so it never certifies a PR.
  if (OFFLINE) { console.error('--pr refused with --offline: an offline run does not certify a PR'); process.exit(2); }
  if (!SLUG) { console.error('--pr refused: could not read owner/repo from the origin remote'); process.exit(2); }
  if (execOut('git status --porcelain --untracked-files=no')) { console.error('--pr refused: the worktree has uncommitted changes'); process.exit(2); }
  // REST only (gh api), never `gh pr`: a cloud or phone session's proxy blocks GraphQL, so `gh pr ...` gets 403 there.
  const prHead = execOut(`gh api repos/${SLUG}/pulls/${PR} --jq .head.sha`);
  if (!prHead || prHead !== execOut('git rev-parse HEAD')) { console.error(`--pr refused: HEAD is not PR #${PR}'s head (${prHead || 'unreadable'})`); process.exit(2); }
}
console.log(`local gate on ${branch} @ ${head}; logs in ${LOGS}`);

// With a token, npm test is itself a production caller, so it runs FIRST in the one serial production chain:
// two callers sharing the management API's request budget is how 10 of 19 failures became 429s
// (scripts/checks/run.mjs). Review of #1597, 26 Oct 2026.
const serialFirst = TOKEN ? STEPS.filter((s) => s.id === 'npm-test') : [];
const offline = STEPS.filter((s) => !s.prod && !serialFirst.includes(s)); const prod = [...serialFirst, ...STEPS.filter((s) => s.prod)];
await Promise.all([
  ...offline.map(async (s) => { const r = pick(s) || await (s.postgres ? withPostgres(s) : run(s)); results.set(s.id, r); console.log(`${r.result.padEnd(7)} ${s.id}`); }),
  (async () => { for (const s of prod) { const r = pick(s) || await run(s); results.set(s.id, r); console.log(`${r.result.padEnd(7)} ${s.id}`); } })(),
]);

const fails = STEPS.filter((s) => results.get(s.id).result === 'FAIL');
const rows = STEPS.map((s) => { const r = results.get(s.id);
  return `| ${r.result === 'PASS' ? 'PASS' : r.result === 'FAIL' ? '**FAIL**' : 'SKIPPED'} | \`${s.id}\` | ${s.job} | ${s.name}${r.note ? ` (${r.note})` : ''} | ${r.secs}s |`; });
const offlineNote = OFFLINE ? ' (OFFLINE: production steps not run)' : '';
const table = [`### Local gate${offlineNote}: ${fails.length ? `${fails.length} FAILED` : 'all PASS'} on \`${branch}\` @ \`${head}\``,
  '', '| result | step | workflow job | what | time |', '|---|---|---|---|---|', ...rows, '',
  `Run with \`npm run gate\` (scripts/ci/local_gate.mjs). Founder, 26 Oct 2026: no paid CI until the bugs clear; this replaces checks.yml and project-parity.yml on a PR.`].join('\n');
console.log('\n' + table);
for (const s of fails) { const r = results.get(s.id); if (r.out) console.log(`\n--- ${s.id}: last lines (${r.log}) ---\n${r.out.split('\n').slice(-25).join('\n')}`); }

if (PR !== null) {
  // REST only (gh api), never `gh pr`: a cloud or phone session's proxy blocks GraphQL, so `gh pr comment` gets 403 there.
  const slug = execOut('git remote get-url origin').match(/github\.com[/:]([^/]+\/[^/.]+)/)?.[1];
  if (!slug) { console.error('could not read owner/repo from the origin remote'); process.exit(1); }
  const c = spawnSync('gh', ['api', '-X', 'POST', `repos/${SLUG}/issues/${PR}/comments`, '--input', '-'],
    { cwd: REPO, input: JSON.stringify({ body: table }), encoding: 'utf8' });
  if (c.status !== 0) { console.error(`could not comment on PR #${PR}: ${c.stderr}`); process.exit(1); }
  console.log(`posted to PR #${PR}`);
}
process.exit(fails.length ? 1 : 0);
