// THE PR GATE, RUN FROM A WORKTREE (it_engineer, 26 Oct 2026).
//
// Founder, 26 Oct 2026: Ubicloud is stopped and no paid service runs CI, GitHub-hosted Actions minutes included,
// until the bugs are cleared; Claude sessions run the checks themselves. Every workflow is workflow_dispatch only.
// This runs the same commands the PR-gate jobs ran, from the files that define them:
//   checks.yml          checks, migration-lint, typecheck, deno-check, otp-race
//   project-parity.yml  parity, kernel-gate (both need SUPABASE_ACCESS_TOKEN or ~/.supabase/access-token)
// and prints ONE PASS/FAIL table. Exit 1 on any FAIL or NOT RUN. A step that cannot run (no token, no Postgres for
// the OTP race) is a FAIL, and a step whose host the network refuses is NOT RUN; neither is ever a quiet pass. Only a
// step named in --skip is left out, and the table says so.
//
//   npm run gate                                  # everything
//   npm run gate -- --pr 1601                     # and post the table on PR #1601 (gh api REST, works where GraphQL is blocked)
//   npm run gate -- --skip=otp-race,audit         # leave named steps out, shown as SKIPPED (named)
//   npm run gate -- --daily                       # also the daily-only step: every deployed function runs main
//
// Offline steps run in parallel, the heavy ones on memory-sized lanes; production steps run one after another (the
// management API's 429 budget, and the kernel gate's serial rule in project-parity.yml).
// Logs and summary.md: <tmp>/qd-gate-<time>-<random>/, one folder per run.
import { spawn, spawnSync } from 'node:child_process';
import { lstatSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir, homedir, totalmem, freemem } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const arg = (name) => { const i = argv.findIndex((a) => a === `--${name}` || a.startsWith(`--${name}=`));
  return i < 0 ? null : argv[i].includes('=') ? argv[i].split('=').slice(1).join('=') : (argv[i + 1] ?? ''); };
const PR = arg('pr');
if (PR !== null && !/^\d+$/.test(PR)) { console.error('--pr needs a pull request number'); process.exit(2); }
const SKIP = new Set((arg('skip') || '').split(',').map((s) => s.trim()).filter(Boolean));
const DAILY = argv.includes('--daily');
// One folder per run (mkdtemp adds a random suffix), so two gates run at once never write each other's logs or summary.
const T0 = Date.now();
const LOGS = mkdtempSync(join(tmpdir(), `qd-gate-${new Date(T0).toISOString().replace(/[:.]/g, '-')}-`));

const TOKEN = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
// A worktree whose node_modules is a symlink to the main checkout's resolves every package OUTSIDE ".", so
// --allow-read=. refused tesseract's .wasm and scan-takeoff failed with NotCapable (27 Oct 2026, reproduced). The
// read grant then names the link's real target as well: the same dependency tree, nothing wider.
const NM_LINK = (() => { try { const p = join(REPO, 'node_modules'); if (!lstatSync(p).isSymbolicLink()) return null;
  const real = realpathSync(p); return real.startsWith(REPO) ? null : real; } catch { return null; } })();
const DENO = `deno test --no-lock --node-modules-dir=auto --allow-read=.${NM_LINK ? `,${NM_LINK}` : ''}`;
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

// deno check over edge functions. ml_embed.ts imports transformers.js as jsDelivr's +esm build ON PURPOSE (its header:
// the npm: specifier fails to deploy). Where cdn.jsdelivr.net is refused (a cloud session's proxy, 27 Oct 2026),
// each such import is type-checked from npm: at the SAME package version, through an import map written into this
// run's log folder, and the row says so. The npm package carries the version's own .d.ts; the +esm URL serves no
// types at all, so the substitute is checked at least as strictly. The committed import is never changed.
function denoCheck(slugs) {
  const files = slugs.map((s) => `supabase/functions/${s}/index.ts`);
  const base = `deno check --no-lock --node-modules-dir=auto ${files.join(' ')}`;
  if (reachable('cdn.jsdelivr.net')) return base;
  const imports = {};
  const walk = (d) => { for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(ts|tsx|js|mjs)$/.test(e.name)) for (const m of readFileSync(p, 'utf8').matchAll(/['"](https:\/\/cdn\.jsdelivr\.net\/npm\/((?:@[^/'"]+\/)?[^/@'"]+)@([^/'"]+)\/\+esm)['"]/g)) imports[m[1]] = `npm:${m[2]}@${m[3]}`;
  } };
  walk(join(REPO, 'supabase/functions'));
  if (!Object.keys(imports).length) return base;
  const map = join(LOGS, 'jsdelivr_to_npm.import_map.json');
  writeFileSync(map, JSON.stringify({ imports }, null, 2));
  return { cmd: `${base} --import-map=${map}`, note: `cdn.jsdelivr.net unreachable here: ${Object.values(imports).join(', ')} type-checked from npm at the same version (${map})` };
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
  ['ssrf', 'checks', 'the SSRF guard fires on a private address, file:// and metadata', 'node scripts/checks/ssrf_guard_refuses_private_addresses.mjs'],
  ['fetch-timeout', 'checks', 'no new outbound fetch without a deadline', 'node scripts/checks/every_outbound_fetch_has_a_timeout.mjs'],
  ['dwg', 'checks', 'a DWG is read into the same take-off as its DXF', `${DENO} --allow-net=raw.githubusercontent.com,cdn.jsdelivr.net supabase/functions/_shared/doc_read/dwg_samples.check.ts`, { heavy: true, hosts: ['raw.githubusercontent.com', 'cdn.jsdelivr.net'] }],
  ['redact-page', 'checks', 'a redacted drawing page covers every identity', `${DENO} --allow-net=deno.land supabase/functions/_shared/drawing_redact_page.check.ts`, { heavy: true, hosts: ['deno.land'] }],
  ['scan-redact', 'checks', 'a scanned drawing is redacted by OCR, or held', `${DENO} --allow-env --allow-net=deno.land supabase/functions/_shared/scan_redact.check.ts`, { heavy: true, hosts: ['deno.land'] }],
  ['scan-takeoff', 'checks', 'a scanned PDF set is counted by OCR to the hand count', `${DENO} --allow-env --allow-net=deno.land,esm.sh supabase/functions/_shared/scan_takeoff.check.ts`, { heavy: true, hosts: ['deno.land', 'esm.sh'] }],
  ['migration-lint', 'migration-lint', 'lint migrations for locking operations (squawk)', () => { const f = migrations(); return f.length ? `npx squawk ${f.join(' ')}` : null; }],
  ['typecheck', 'typecheck', 'typecheck the app', 'npm run typecheck', { heavy: true }],
  ['audit', 'typecheck', 'no HIGH or CRITICAL advisory in a production dependency', 'npm audit --omit=dev --audit-level=high'],
  ['deno-gated', 'deno-check', 'typecheck the gated edge functions', () => denoCheck(['ceo_agent', 'stripe_webhook', 'supplier_pay', 'customer_api', 'supplier_api', 'resend_inbound', 'supplier_catalog_ingest']), { heavy: true }],
  ['deno-all', 'deno-check', 'typecheck every edge function', () => denoCheck(readdirSync(join(REPO, 'supabase/functions')).filter((d) => existsSync(join(REPO, 'supabase/functions', d, 'index.ts')))), { heavy: true }],
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
  const c = typeof step.cmd === 'function' ? step.cmd() : step.cmd;
  if (c === null) return Promise.resolve({ result: 'PASS', note: 'nothing to run (only generated baseline migrations)', secs: 0 });
  const cmd = typeof c === 'object' ? c.cmd : c; const why = typeof c === 'object' ? c.note : undefined;
  const noted = (r) => (why ? { ...r, note: [why, r.note].filter(Boolean).join('; ') } : r);
  const log = join(LOGS, `${step.id}.log`); const t0 = Date.now();
  return new Promise((done) => {
    const p = spawn(cmd, { cwd: REPO, shell: true, detached: process.platform !== 'win32', env: { ...process.env, ...env, ...(step.env || {}), ...extraEnv } });
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
  const up = spawnSync('docker', ['run', '-d', '--rm', '--name', name, '-e', 'POSTGRES_PASSWORD=race', '-p', '127.0.0.1:55432:5432', 'postgres:16'], { encoding: 'utf8', shell: true });
  if (up.status !== 0) return { result: 'FAIL', note: `docker could not start postgres:16: ${String(up.stderr).trim().slice(0, 120)}`, secs: 0 };
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
  if (!SLUG) { console.error('--pr refused: could not read owner/repo from the origin remote'); process.exit(2); }
  if (execOut('git status --porcelain --untracked-files=no')) { console.error('--pr refused: the worktree has uncommitted changes'); process.exit(2); }
  // REST only (gh api), never `gh pr`: a cloud or phone session's proxy blocks GraphQL, so `gh pr ...` gets 403 there.
  const prHead = execOut(`gh api repos/${SLUG}/pulls/${PR} --jq .head.sha`);
  if (!prHead || prHead !== execOut('git rev-parse HEAD')) { console.error(`--pr refused: HEAD is not PR #${PR}'s head (${prHead || 'unreadable'})`); process.exit(2); }
}
console.log(`local gate on ${branch} @ ${head}; logs in ${LOGS}`);
if (NM_LINK) console.log(`node_modules is a link to ${NM_LINK}: the deno steps may read it too`);

// With a token, npm test is itself a production caller, so it runs FIRST in the one serial production chain:
// two callers sharing the management API's request budget is how 10 of 19 failures became 429s
// (scripts/checks/run.mjs). Review of #1597, 26 Oct 2026.
const serialFirst = TOKEN ? STEPS.filter((s) => s.id === 'npm-test') : [];
const offline = STEPS.filter((s) => !s.prod && !serialFirst.includes(s)); const prod = [...serialFirst, ...STEPS.filter((s) => s.prod)];
// Heavy offline steps share a few lanes sized to the memory this process may use (the cgroup limit where there is
// one): 5 GB a lane, measured peaks being 3.0 GB for an OCR suite. The longest go first so the lanes end together.
const GB = 1024 ** 3;
const memory = Math.min(process.constrainedMemory?.() || Infinity, totalmem());
const LANES = Math.max(1, Math.min(4, Number(process.env.QD_GATE_HEAVY_LANES) || Math.floor(memory / (5 * GB))));
const LONGEST_FIRST = ['npm-test', 'scan-redact', 'dwg', 'deno-all', 'scan-takeoff', 'typecheck', 'redact-page', 'deno-gated'];
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
const table = [`### Local gate: ${verdict} on \`${branch}\` @ \`${head}\` (${Math.floor(wall / 60)} min ${wall % 60} s)`,
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
