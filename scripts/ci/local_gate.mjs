// THE PR GATE, RUN FROM A WORKTREE (it_engineer, 26 Oct 2026).
//
// Founder, 26 Oct 2026: Ubicloud is stopped and no paid service runs CI, GitHub-hosted Actions minutes included,
// until the bugs are cleared; Claude sessions run the checks themselves. Every workflow is workflow_dispatch only.
// This runs the same commands the PR-gate jobs ran, from the files that define them:
//   checks.yml          checks, migration-lint, typecheck, deno-check, otp-race
//   project-parity.yml  parity, kernel-gate (both need SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token)
// plus, since 11 Nov 2026, what no workflow ran: node-tree, next-build and tree-unchanged (the tree that ships; below).
// and prints ONE PASS/FAIL table. Exit 1 on any FAIL or NOT RUN. A step that cannot run (no token, no Postgres for
// the OTP race) is a FAIL, and a step whose host the network refuses is NOT RUN; neither is ever a quiet pass. Only a
// step named in --skip is left out, and the table says so.
//
//   npm run gate                                  # everything
//   npm run gate -- --pr 1601                     # and post the table on PR #1601 (gh api REST, works where GraphQL is blocked)
//   npm run gate -- --skip=otp-race,audit         # leave named steps out, shown as SKIPPED (named)
//   npm run gate -- --daily                       # also the daily-only step: every deployed function runs main
//   npm run gate -- --offline                     # only the steps that need no production credential; every
//                                                 # production step is listed as SKIPPED (offline), never PASS.
//                                                 # What `docker compose run --rm checks` runs (docs/runbooks/docker.md).
//
// Offline steps run in parallel, the heavy ones on memory-sized lanes; production steps run one after another (the
// management API's 429 budget, and the kernel gate's serial rule in project-parity.yml).
// Logs and summary.md: <tmp>/qd-gate-<time>-<random>/, one folder per run.
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir, homedir, totalmem, freemem } from 'node:os';
import { fileURLToPath } from 'node:url';
import { DENO_NPM_FLAGS, denoNpmCache } from '../lib/deno_npm.mjs';
import { fingerprint, treeFindings } from '../lib/lockfile_tree.mjs';
import { edgeDynamicImports } from '../lib/edge_dynamic_imports.mjs';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const arg = (name) => { const i = argv.findIndex((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  return i < 0 ? null : argv[i].includes('=') ? argv[i].split('=').slice(1).join('=') : (argv[i + 1] ?? ''); };
const PR = arg('pr');
if (PR !== null && !/^\d+$/.test(PR)) { console.error('--pr needs a pull request number'); process.exit(2); }
const SKIP = new Set((arg('skip') || '').split(',').map((s) => s.trim()).filter(Boolean));
const DAILY = argv.includes('--daily');
const OFFLINE = argv.includes('--offline');
// One folder per run (mkdtemp adds a random suffix), so two gates run at once never write each other's logs or summary.
const T0 = Date.now();
const LOGS = mkdtempSync(join(tmpdir(), `qd-gate-${new Date(T0).toISOString().replace(/[:.]/g, '-')}-`));

// --offline treats the credential as absent even when one is present, so npm test stays an offline run too.
const TOKEN = !OFFLINE && (!!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token')));
// THE GATE CERTIFIES THE TREE THAT SHIPS (11 Nov 2026, TD-24, TD-25). Three rules, each with its own step:
//   node-tree       node_modules is exactly package-lock.json (what Vercel installs): npm's layout, every locked
//                   version, nothing extra. Build one by hard links with scripts/ci/node_modules_from_lockfile.mjs.
//   next-build      the site is built (`next build`) on that tree, as Vercel builds it; tsc and oxlint alone passed
//                   while the gate's tree was Deno's layout with 13 packages at other versions.
//   tree-unchanged  no step rewrote node_modules while the gate ran (its fingerprint before = after).
// Every Deno call runs with --node-modules-dir=none (scripts/lib/deno_npm.mjs): npm packages come from Deno's global
// cache and ./node_modules is never written. Until today the Deno steps used =auto, which relinked the tree to the
// versions the Deno imports name. A runtime file read inside a package (tesseract's .wasm) is granted on the cache.
// (The old NM_LINK read grant, for a worktree whose node_modules linked to the main checkout's, is gone with =auto:
// none never reads node_modules, and node-tree refuses a linked tree.)
const DENO_ARGS = DENO_NPM_FLAGS.join(' ');
const DENO = `deno test ${DENO_ARGS} --allow-read=.,${denoNpmCache()}`;
const env = { DENO_NO_PACKAGE_JSON: '1' };   // checks.yml / project-parity.yml workflow env (12 Oct 2026)
// A production check that answers SKIP has asserted nothing; in the kernel gate that is a failure (project-parity.yml).
const SKIPPED = /^SKIP|^SKIPPED|NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL|# SKIPPED/m;

const migrations = () => (existsSync(join(REPO, 'supabase/migrations')) ? readdirSync(join(REPO, 'supabase/migrations')) : [])
  .filter((f) => f.endsWith('.sql') && !f.includes('_baseline_')).map((f) => `supabase/migrations/${f}`);

// Can this machine reach the host at all? curl exits non-zero when the network (or a session's egress proxy) refuses
// the connection; any HTTP answer, even a 404, means it is reachable. Probed once per host per run.
const reach = new Map();
function reachable(host) {
  if (!reach.has(host)) reach.set(host, spawnSync('curl', ['-sS', '-o', process.platform === 'win32' ? 'NUL' : '/dev/null', '--max-time', '15', `https://${host}/`], { stdio: 'ignore' }).status === 0);
  return reach.get(host);
}

// [id, workflow job, name, command | () => command | () => {cmd, note} | null (nothing to run, passes with a note), opts]
// heavy: a step that holds 1-4 GB (tsc, deno check, the OCR suites). Run all at once they exceeded a cloud
// container's 13.4 GB memory cgroup and the kernel killed scan-redact and scan-takeoff mid-test (27 Oct 2026,
// dmesg: "Memory cgroup out of memory: Killed process (deno)"; scan-takeoff alone peaks at 3.0 GB and passes).
// hosts: what its --allow-net reaches. A host the network refuses makes the step NOT RUN (a failing verdict),
// never a FAIL that looks like the code's fault and never a PASS.
const STEPS = [
  // With a token, npm test also runs every production check the CI job skipped, one at a time (the 429 budget), including every_seat_reads_its_verified_pack's live eval (up to 60 min): measured >90 min on 26 Oct.
  ['npm-test', 'checks', 'npm test: node --test over scripts/checks + the deno suite', 'npm test', { minutes: 180, heavy: true }],
  // The Deno half of npm test on its own (12 Nov 2026): `--skip=npm-test` skipped it with the node checks, and #1953 reached
  // main with two red Deno tests. It passes with a note when npm-test itself runs, so the suite is never run twice.
  // alone: it runs after every other offline step has finished. Several of its tests hold a CPU budget (a dense drawing
  // measured "inside the edge budget"); beside next-build and deno check on two lanes that one took 1,654 ms and failed
  // (first run of this step, 12 Nov), and passes alone. A step that fails on the gate's own load teaches people to ignore it.
  ['deno-suite', 'checks', 'every edge function test (the Deno half of npm test)',
    () => (SKIP.has('npm-test') ? 'node scripts/checks/run.mjs --deno-only' : { cmd: 'node -e ""', note: 'the Deno suite runs inside npm-test' }), { minutes: 40, alone: true }],
  ['ssrf', 'checks', 'the SSRF guard fires on a private address, file:// and metadata', 'node scripts/checks/ssrf_guard_refuses_private_addresses.mjs'],
  ['fetch-timeout', 'checks', 'no new outbound fetch without a deadline', 'node scripts/checks/every_outbound_fetch_has_a_timeout.mjs'],
  ['dwg', 'checks', 'a DWG is read into the same take-off as its DXF', `${DENO} --allow-net=raw.githubusercontent.com,registry.npmjs.org supabase/functions/_shared/doc_read/dwg_samples.check.ts`, { heavy: true, hosts: ['raw.githubusercontent.com', 'registry.npmjs.org'] }],
  ['redact-page', 'checks', 'a redacted drawing page covers every identity', `${DENO} --allow-net=deno.land supabase/functions/_shared/drawing_redact_page.check.ts`, { heavy: true, hosts: ['deno.land'] }],
  // 17 Nov 2026: one 2600 px sheet through the real drawing_redact handler, each worker held to a CPU budget inside the edge's
  // (the live set died "CPU Time exceeded" on every sheet). A CPU budget: run alone of other heavy steps, like deno-suite.
  ['redact-budget', 'checks', 'a drawing sheet is redacted within the edge CPU budget', `${DENO} --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-net=deno.land,esm.sh supabase/functions/drawing_redact/a_sheet_is_redacted_within_the_edge_budget.check.ts`, { heavy: true, alone: true, hosts: ['deno.land', 'esm.sh'] }],
  // 17 Nov 2026: every drawing_boq 'lengths' request customer_api makes (a sheet each, then the merge) through the real handler,
  // each in a fresh process of its own, held to a CPU budget inside the edge's (the whole-set request answered 500 on
  // production and left the duct without metres). A CPU budget: run alone of other heavy steps, like redact-budget.
  ['lengths-budget', 'checks', 'every duct-length request is measured within the edge CPU budget', `${DENO} --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-run supabase/functions/drawing_boq/a_duct_run_is_measured_sheet_by_sheet.check.ts`, { heavy: true, alone: true }],
  ['scan-redact', 'checks', 'a scanned drawing is redacted by OCR, or held', `${DENO} --allow-env --allow-net=deno.land supabase/functions/_shared/scan_redact.check.ts`, { heavy: true, hosts: ['deno.land'] }],
  ['scan-takeoff', 'checks', 'a scanned PDF set is counted by OCR to the hand count', `${DENO} --allow-env --allow-net=deno.land,esm.sh supabase/functions/_shared/scan_takeoff.check.ts`, { heavy: true, hosts: ['deno.land', 'esm.sh'] }],
  ['migration-lint', 'migration-lint', 'lint migrations for locking operations (squawk)', () => { const f = migrations(); return f.length ? `npx squawk ${f.join(' ')}` : null; }],
  ['lint', 'typecheck', 'lint the website (oxlint; warnings are counted debt, errors fail)', 'npm run lint'],
  ['typecheck', 'typecheck', 'typecheck the app', 'npm run typecheck', { heavy: true }],
  ['audit', 'typecheck', 'no HIGH or CRITICAL advisory in a production dependency, except a named one with no fix yet (scripts/ci/audit_exceptions.json)', 'node scripts/ci/audit_production.mjs'],
  // In-process, not a command: the findings are the note (the first three), so a red row says what differs.
  ['node-tree', 'build', 'node_modules is exactly package-lock.json (what Vercel installs)', () => {
    const f = treeFindings(REPO);
    return f.length ? { result: 'FAIL', note: `${f.length} difference(s): ${f.slice(0, 3).join('; ')}; rebuild it: node scripts/ci/node_modules_from_lockfile.mjs package-lock.json <store> node_modules` } : { result: 'PASS', note: 'lockfile-exact' };
  }, { inProcess: true }],
  // NODE_PATH: the PostCSS worker runs from the build directory, so with .next linked to tmpfs (disk is short in a cloud
  // session; the output is ~400 MB) it could not find @tailwindcss/postcss. Harmless when .next is a plain directory.
  ['next-build', 'build', 'build the site as Vercel does (next build)', 'npm run build', { heavy: true, env: { NODE_PATH: join(REPO, 'node_modules'), NEXT_TELEMETRY_DISABLED: '1' } }],
  ['deno-gated', 'deno-check', 'typecheck the gated edge functions', `deno check ${DENO_ARGS} `
    + ['ceo_agent', 'stripe_webhook', 'supplier_pay', 'customer_api', 'supplier_api', 'resend_inbound', 'supplier_catalog_ingest'].map((s) => `supabase/functions/${s}/index.ts`).join(' '), { heavy: true }],
  // cdn.jsdelivr.net needs no substitute here (#1653): ml_embed.ts carries @ts-types from npm, so deno check reads no +esm.
  // 12 Nov 2026 (final audit F3): plus every literal dynamic import's target as a root. deno check passes a dynamic
  // import whose target is missing (resilience_ping's supportVoice step: "Module not found" 115 times); as a root it fails.
  ['deno-all', 'deno-check', 'typecheck every edge function and every module one imports dynamically', () => `deno check ${DENO_ARGS} `
    + readdirSync(join(REPO, 'supabase/functions')).filter((d) => existsSync(join(REPO, 'supabase/functions', d, 'index.ts'))).map((d) => `supabase/functions/${d}/index.ts`)
      .concat(edgeDynamicImports(REPO).roots).join(' '), { heavy: true }],
  // One throwaway Postgres for both races: the sign-in code, and an approval that never waits on another transaction's
  // founding-rank lock (10 Nov 2026: a services confirm timed out twice behind it). No --allow-write=node_modules any
  // more: with none, Deno writes nothing there.
  ['otp-race', 'otp-race', 'a sign-in code survives 5 guesses and verifies once under a burst; an approval never waits on the rank lock', `deno test ${DENO_ARGS} --allow-read --allow-env --allow-net supabase/functions/login_otp/verify_race.check.ts supabase/functions/_shared/founding_rank_race.check.ts`, { postgres: true }],
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
  // Read after every other step has finished; see TREE_BEFORE below.
  ['tree-unchanged', 'build', 'no step rewrote node_modules while the gate ran', null, { post: true }],
].map(([id, job, name, cmd, o = {}]) => ({ id, job, name, cmd, ...o }));

const unknown = [...SKIP].filter((s) => !STEPS.some((x) => x.id === s));
if (unknown.length) { console.error(`--skip names no step: ${unknown.join(', ')}. Steps: ${STEPS.map((s) => s.id).join(', ')}`); process.exit(2); }

function run(step, extraEnv = {}) {
  if (step.inProcess) { const t0 = Date.now(); const r = step.cmd(); return Promise.resolve({ ...r, secs: Math.round((Date.now() - t0) / 1000) }); }
  const c = typeof step.cmd === 'function' ? step.cmd() : step.cmd;
  if (c === null) return Promise.resolve({ result: 'PASS', note: 'nothing to run (only generated baseline migrations)', secs: 0 });
  const cmd = typeof c === 'object' ? c.cmd : c; const why = typeof c === 'object' ? c.note : undefined;
  const noted = (r) => (why ? { ...r, note: [why, r.note].filter(Boolean).join('; ') } : r);
  const log = join(LOGS, `${step.id}.log`); const t0 = Date.now();
  return new Promise((done) => {
    const p = spawn(cmd, { cwd: REPO, shell: true, detached: process.platform !== 'win32', env: { ...process.env, ...env, ...(OFFLINE ? { QD_OFFLINE: '1', SUPABASE_ACCESS_TOKEN: '' } : {}), ...(step.env || {}), ...extraEnv } });
    let out = ''; let timedOut = false;
    p.stdout.on('data', (d) => { out += d; }); p.stderr.on('data', (d) => { out += d; });
    // The whole tree: with shell: true, p is only the shell, and killing it alone leaves the command running.
    const minutes = step.minutes || 45;   // 45 = the longest job wall in the two workflows
    const kill = setTimeout(() => { timedOut = true; if (process.platform === 'win32') spawnSync('taskkill', ['/pid', String(p.pid), '/T', '/F'], { stdio: 'ignore' }); else process.kill(-p.pid, 'SIGKILL'); }, minutes * 60_000);
    p.on('close', (code, signal) => {
      clearTimeout(kill); writeFileSync(log, out);
      const secs = Math.round((Date.now() - t0) / 1000);
      if (step.noSkip && SKIPPED.test(out)) return done(noted({ result: 'FAIL', note: 'skipped for want of a credential', secs, log, out }));
      if (code === 0) return done(noted({ result: 'PASS', secs, log }));
      if (step.warnOn?.includes(code)) return done(noted({ result: 'PASS', note: `exit ${code}: a pattern was found and recorded in security_events`, secs, log }));
      // A kill the gate did not send (the shell reports 137 = 128 + SIGKILL, deno prints "Killed") is the kernel's:
      // on 27 Oct 2026 it was the memory cgroup's out-of-memory killer, not a timeout and not an assertion.
      const note = timedOut ? `killed at ${minutes} min`
        : signal || code === 137 || /^\S.*\.\.\.Killed$|^Killed$/m.test(out) ? `killed by ${signal || 'SIGKILL'}, not by the gate (an out-of-memory kill? see dmesg)` : `exit ${code}`;
      done(noted({ result: 'FAIL', note, secs, log, out }));
    });
  });
}

// The OTP race needs a throwaway Postgres, never production. QD_OTP_RACE_PG wins; else docker starts postgres:16;
// else (a cloud container has no Docker daemon, 27 Oct 2026) a throwaway cluster from the local Postgres binaries.
async function withPostgres(step) {
  if (process.env.QD_OTP_RACE_PG) return run(step, { QD_OTP_RACE_PG: process.env.QD_OTP_RACE_PG });
  if (spawnSync('docker', ['info'], { stdio: 'ignore', shell: true }).status !== 0) {
    const local = await withLocalPostgres(step);
    return local || { result: 'FAIL', note: 'no Postgres: set QD_OTP_RACE_PG, start Docker, or install the Postgres server binaries (initdb, pg_ctl)', secs: 0 };
  }
  const name = `qd-gate-otp-${process.pid}`;
  // Docker Hub answers 429 to cloud sessions (measured 9-10 Nov 2026); Google's public mirror of the same official image
  // does not. Docker Hub first, the mirror second; QD_OTP_RACE_IMAGE overrides both.
  const images = process.env.QD_OTP_RACE_IMAGE ? [process.env.QD_OTP_RACE_IMAGE] : ['postgres:16', 'mirror.gcr.io/library/postgres:16'];
  let up = null;
  for (const image of images) {
    up = spawnSync('docker', ['run', '-d', '--rm', '--name', name, '-e', 'POSTGRES_PASSWORD=race', '-p', '127.0.0.1:55432:5432', image], { encoding: 'utf8', shell: true });
    if (up.status === 0) break;
    spawnSync('docker', ['rm', '-f', name], { stdio: 'ignore', shell: true });
  }
  if (up.status !== 0) return { result: 'FAIL', note: `docker could not start ${images.join(' or ')}: ${String(up.stderr).trim().slice(0, 120)}`, secs: 0 };
  try {
    for (let i = 0; i < 60 && spawnSync('docker', ['exec', name, 'pg_isready', '-U', 'postgres'], { stdio: 'ignore', shell: true }).status !== 0; i++) await new Promise((r) => setTimeout(r, 1000));
    return await run(step, { QD_OTP_RACE_PG: 'postgres://postgres:race@127.0.0.1:55432/postgres' });
  } finally { spawnSync('docker', ['rm', '-f', name], { stdio: 'ignore', shell: true }); }
}

// The same property without Docker: initdb a NEW cluster in a temp directory (never the machine's own cluster, whose
// roles and databases outlive the run), start it on a loopback port, run the race, stop it, delete it. Returns null
// when no server binaries are installed. initdb refuses to run as root, so as root it runs as the postgres user.
async function withLocalPostgres(step) {
  if (process.platform === 'win32') return null;
  const onPath = execOut('command -v initdb');
  const vers = existsSync('/usr/lib/postgresql') ? readdirSync('/usr/lib/postgresql').filter((v) => /^\d+$/.test(v)).sort((a, b) => b - a) : [];
  const bin = onPath ? dirname(onPath) : vers.map((v) => `/usr/lib/postgresql/${v}/bin`).find((d) => existsSync(join(d, 'initdb')));
  if (!bin || !existsSync(join(bin, 'pg_ctl'))) return null;
  const root = process.getuid?.() === 0;
  if (root && spawnSync('id', ['postgres'], { stdio: 'ignore' }).status !== 0) return null;
  const as = (exe, args) => spawnSync(root ? 'runuser' : join(bin, exe), root ? ['-u', 'postgres', '--', join(bin, exe), ...args] : args, { encoding: 'utf8' });
  const dir = mkdtempSync(join(tmpdir(), 'qd-gate-otp-pg-'));
  if (root) spawnSync('chown', ['postgres', dir]);
  const data = join(dir, 'data'); const port = String(55433 + (process.pid % 500));
  const t0 = Date.now();
  try {
    const init = as('initdb', ['-D', data, '-U', 'postgres', '-A', 'trust', '--no-sync']);
    if (init.status !== 0) return { result: 'FAIL', note: `initdb failed: ${String(init.stderr).trim().slice(0, 120)}`, secs: 0 };
    const up = as('pg_ctl', ['-D', data, '-l', join(dir, 'server.log'), '-w', '-t', '60', '-o', `-p ${port} -k ${dir} -c listen_addresses=127.0.0.1 -c max_connections=60`, 'start']);
    if (up.status !== 0) return { result: 'FAIL', note: `local Postgres did not start: ${String(up.stderr || up.stdout).trim().slice(0, 120)}`, secs: Math.round((Date.now() - t0) / 1000) };
    const version = String(spawnSync(join(bin, 'postgres'), ['--version'], { encoding: 'utf8' }).stdout).trim().replace(/^postgres \(PostgreSQL\) /, '');
    const r = await run(step, { QD_OTP_RACE_PG: `postgres://postgres@127.0.0.1:${port}/postgres` });
    return { ...r, note: [`no Docker: a throwaway local Postgres ${version} cluster`, r.note].filter(Boolean).join('; ') };
  } finally {
    as('pg_ctl', ['-D', data, '-m', 'immediate', 'stop']);
    rmSync(dir, { recursive: true, force: true });
  }
}

const results = new Map();
const pick = (s) => {
  if (SKIP.has(s.id)) return { result: 'SKIPPED', note: 'named in --skip', secs: 0 };
  if (s.daily && !DAILY) return { result: 'SKIPPED', note: 'daily only (--daily)', secs: 0 };
  if (s.prod && OFFLINE) return { result: 'SKIPPED', note: 'production step, --offline', secs: 0 };
  if (s.prod && !TOKEN) return { result: 'FAIL', note: 'no SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token', secs: 0 };
  const refused = (s.hosts || []).filter((h) => !reachable(h));
  if (refused.length) return { result: 'NOT RUN', note: `the network refuses ${refused.join(', ')}: allow ${refused.length > 1 ? 'those hosts' : 'that host'} to run it`, secs: 0 };
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
// Taken before any step starts; tree-unchanged compares it with the tree after the last step.
const TREE_BEFORE = fingerprint(REPO);

// With a token, npm test is itself a production caller, so it runs FIRST in the one serial production chain:
// two callers sharing the management API's request budget is how 10 of 19 failures became 429s
// (scripts/checks/run.mjs). Review of #1597, 26 Oct 2026.
const serialFirst = TOKEN ? STEPS.filter((s) => s.id === 'npm-test') : [];
const alone = STEPS.filter((s) => s.alone);
const offline = STEPS.filter((s) => !s.prod && !s.post && !s.alone && !serialFirst.includes(s)); const prod = [...serialFirst, ...STEPS.filter((s) => s.prod)];
// Heavy offline steps share a few lanes sized to the memory this process may use (the cgroup limit where there is
// one): 5 GB a lane, measured peaks being 3.0 GB for an OCR suite. The longest go first so the lanes end together.
const GB = 1024 ** 3;
const memory = Math.min(process.constrainedMemory?.() || Infinity, totalmem());
const LANES = Math.max(1, Math.min(4, Number(process.env.QD_GATE_HEAVY_LANES) || Math.floor(memory / (5 * GB))));
const LONGEST_FIRST = ['npm-test', 'scan-redact', 'dwg', 'next-build', 'deno-all', 'scan-takeoff', 'typecheck', 'redact-page', 'deno-gated'];
const heavy = offline.filter((s) => s.heavy).sort((a, b) => LONGEST_FIRST.indexOf(a.id) - LONGEST_FIRST.indexOf(b.id));
console.log(`${heavy.length} heavy steps on ${LANES} lane(s) (${(memory / GB).toFixed(1)} GB available)`);
const finish = (s, r) => { results.set(s.id, r); console.log(`${r.result.padEnd(7)} ${s.id}${r.note ? ` (${r.note})` : ''}`); };
const doStep = async (s) => finish(s, pick(s) || await (s.postgres ? withPostgres(s) : run(s)));

// The memory cgroup of a cloud session is shared with every other process in it, other agents' gates and test runs
// included (27 Oct 2026: two lanes of this gate plus another worktree's OCR suites, and the kernel killed
// scan-redact again). So a heavy step starts only when the cgroup has HEADROOM_GB free, unless this gate has no heavy
// step running (then it starts anyway: waiting on other processes forever proves nothing either).
const HEADROOM_GB = 4;
function freeBytes() {
  try {
    const rel = readFileSync('/proc/self/cgroup', 'utf8').match(/^\d+:(?:memory)?:(.*)$/m)?.[1] ?? '';
    const v2 = join('/sys/fs/cgroup', rel); const v1 = join('/sys/fs/cgroup/memory', rel);
    const [dir, cur, max, stat, inactive] = existsSync(join(v2, 'memory.current'))
      ? [v2, 'memory.current', 'memory.max', 'memory.stat', /^inactive_file (\d+)/m]
      : [v1, 'memory.usage_in_bytes', 'memory.limit_in_bytes', 'memory.stat', /^total_inactive_file (\d+)/m];
    const used = Number(readFileSync(join(dir, cur), 'utf8')) - Number(readFileSync(join(dir, stat), 'utf8').match(inactive)?.[1] ?? 0);
    const limit = Math.min(Number(readFileSync(join(dir, max), 'utf8')) || Infinity, totalmem());
    if (Number.isFinite(used) && Number.isFinite(limit)) return limit - used;
  } catch { /* not Linux, or no cgroup: the machine's free memory */ }
  return freemem();
}
let heavyRunning = 0;
async function admitted() { while (heavyRunning > 0 && freeBytes() < HEADROOM_GB * GB) await new Promise((r) => setTimeout(r, 5000)); }
// A heavy step the KERNEL killed (not the gate's timeout, not an assertion) runs once more when the memory is there;
// the row says so, and the second run has to pass on its own.
async function doHeavy(s) {
  await admitted(); heavyRunning++;
  try {
    const first = pick(s) || await run(s);
    if (first.result !== 'FAIL' || !/^killed by .*not by the gate/.test(first.note || '')) return finish(s, first);
    console.log(`again   ${s.id} (${first.note}; waiting for ${HEADROOM_GB} GB free, then one rerun)`);
    heavyRunning--; await admitted(); heavyRunning++;
    const again = await run(s);
    finish(s, { ...again, note: [`the kernel killed the first run for memory (${first.secs}s in); this is the rerun`, again.note].filter(Boolean).join('; ') });
  } finally { heavyRunning--; }
}
await Promise.all([
  ...offline.filter((s) => !s.heavy).map(doStep),
  ...Array.from({ length: LANES }, async () => { for (let s; (s = heavy.shift());) await doHeavy(s); }),
  (async () => { for (const s of prod) finish(s, pick(s) || await run(s)); })(),
]);
for (const s of alone) await doStep(s);   // nothing else of this gate is running now
for (const s of STEPS.filter((x) => x.post)) {
  if (SKIP.has(s.id)) { finish(s, { result: 'SKIPPED', note: 'named in --skip', secs: 0 }); continue; }
  const before = TREE_BEFORE.split('\n'); const after = fingerprint(REPO).split('\n');
  const changed = [...after.filter((l) => !before.includes(l)).map((l) => `now ${l}`), ...before.filter((l) => !after.includes(l)).map((l) => `was ${l}`)];
  finish(s, changed.length ? { result: 'FAIL', note: `${changed.length} line(s) of the tree changed during the run: ${changed.slice(0, 4).join('; ')}`, secs: 0 }
    : { result: 'PASS', note: 'the same tree before and after', secs: 0 });
}

// NOT RUN is a failing verdict: what it would have proved is unproved here, and the table says why.
const fails = STEPS.filter((s) => results.get(s.id).result === 'FAIL');
const notRun = STEPS.filter((s) => results.get(s.id).result === 'NOT RUN');
const mark = { PASS: 'PASS', FAIL: '**FAIL**', 'NOT RUN': '**NOT RUN**', SKIPPED: 'SKIPPED' };
const rows = STEPS.map((s) => { const r = results.get(s.id);
  return `| ${mark[r.result]} | \`${s.id}\` | ${s.job} | ${s.name}${r.note ? ` (${r.note})` : ''} | ${r.secs}s |`; });
// "all PASS" only when every step ran and passed; a skipped step is counted in the headline, not hidden in the table.
const skipped = STEPS.filter((s) => results.get(s.id).result === 'SKIPPED').length;
const verdict = fails.length || notRun.length ? [fails.length && `${fails.length} FAILED`, notRun.length && `${notRun.length} NOT RUN`].filter(Boolean).join(', ')
  : skipped ? `${STEPS.length - skipped} PASS, ${skipped} SKIPPED` : 'all PASS';
const wall = Math.round((Date.now() - T0) / 1000);
const offlineNote = OFFLINE ? ' (OFFLINE: production steps not run)' : '';
const table = [`### Local gate${offlineNote}: ${verdict} on \`${branch}\` @ \`${head}\` (${Math.floor(wall / 60)} min ${wall % 60} s)`,
  '', '| result | step | workflow job | what | time |', '|---|---|---|---|---|', ...rows, '',
  `Run with \`npm run gate\` (scripts/ci/local_gate.mjs). Founder, 26 Oct 2026: no paid CI until the bugs clear; this replaces checks.yml and project-parity.yml on a PR.`].join('\n');
console.log('\n' + table);
writeFileSync(join(LOGS, 'summary.md'), table + '\n');   // this run's own folder, never a shared path
console.log(`\nsummary: ${join(LOGS, 'summary.md')}`);
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
process.exit(fails.length || notRun.length ? 1 : 0);
