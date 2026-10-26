// Deploy edge functions with the guarantees deploy_functions.ps1 established, from any OS.
//
//   node scripts/deploy_functions.mjs --ref=<project> supplier_portal supplier_api
//   node scripts/deploy_functions.mjs --ref=<project> --changed --base=<sha>
//   node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <slugs>
//
// ── WHY THIS EXISTS ALONGSIDE THE .ps1 ──────────────────────────────────────────────────────────
// The PowerShell script is correct and proven; it is also PowerShell, so a GitHub runner cannot
// use it. The alternative on offer was a workflow calling `supabase functions deploy` bare, which
// drops every guarantee the .ps1 spent three incidents acquiring. Rather than let CI deploy under
// weaker rules than a human does, the rules move into Node and both callers use the same ones.
//
// ── THE FOUR RULES, EACH FROM A REAL FAILURE ────────────────────────────────────────────────────
// 1. NEVER GUESS A TARGET. No ref, no deploy. The .ps1 was pinned to production in three places,
//    which is how staging could never run the application at all.
// 2. PRODUCTION NEEDS SAYING OUT LOUD. --production, or it refuses. Same as -IMeanProduction.
// 3. NO verify_jwt FLAG IS EVER PASSED. supabase/config.toml is the single source of truth and the
//    CLI reads it. Proven on production 3 Aug 2026: vercel_status (verify_jwt=false) redeployed
//    with no flag stayed false, where the CLI's own default would have flipped it to true and made
//    the function reject every request. Instead the committed config is CHECKED against live first
//    and a mismatch refuses the deploy, because deploying through drift means nobody knows which
//    value is about to win.
// 4. THE CLI's EXIT CODE IS NOT THE VERIFICATION. Each function's version is read from the API
//    before and after; a deploy that did not bump the version did not happen, whatever it printed.
import { execFileSync, spawnSync } from 'node:child_process';
import { isTransientDeployFailure } from './lib/retry.mjs';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { sql } from './lib/db.mjs';
import { warmable, warmFunctions } from './lib/warm_functions.mjs';

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const args = process.argv.slice(2);
const flag = (name) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const has = (name) => args.includes(`--${name}`);

const ref = flag('ref') || process.env.QD_TARGET_REF;
const die = (msg) => { console.error(msg); process.exit(1); };

if (!ref) die('No --ref given and QD_TARGET_REF is unset. Refusing to guess a deploy target.');
if (!/^[a-z]{20}$/.test(ref)) die(`--ref ${JSON.stringify(ref)} is not a valid project ref.`);
if (ref === PROD_REF && !has('production')) {
  die(`REFUSED: --ref is production (${PROD_REF}). Pass --production to mean it.`);
}

// THE TOKEN IS DEMANDED WHERE IT IS USED, NOT AT STARTUP. It was required here, above the slug
// resolution, which made `--dry-run` — a git diff and nothing else — fail without credentials. That
// broke the workflow's first real run on main: the two dry-run steps died on a missing token before
// the step whose whole job is to report the token missing could say so. A command that touches
// nothing should need nothing.

// ── WHICH FUNCTIONS ────────────────────────────────────────────────────────────────────────────
// --changed asks git, so a push deploys what the push touched rather than all 196. Deploying
// everything on every commit bumps 196 version numbers and destroys the one signal that says which
// function actually moved. _shared is a library, never a function, and is excluded by name.
let slugs = args.filter((a) => !a.startsWith('--'));
if (has('changed')) {
  const base = flag('base');
  if (!base) die('--changed needs --base=<sha> to diff against.');
  let out = '';
  try {
    out = execFileSync('git', ['diff', '--name-only', `${base}...HEAD`, '--', 'supabase/functions/'],
      { encoding: 'utf8' });
  } catch (e) { die(`git diff failed: ${e.message}`); }
  const touched = new Set();
  for (const line of out.split('\n')) {
    const m = line.match(/^supabase\/functions\/([^/]+)\//);
    if (m) touched.add(m[1]);
  }
  // A change to _shared can break any function that imports it, so it widens the set rather than
  // being ignored — silently skipping it would deploy nothing for the change most able to break
  // everything. The importers are found by reading the source, not guessed.
  if (touched.has('_shared')) {
    touched.delete('_shared');
    const dirs = readdirSync('supabase/functions', { withFileTypes: true })
      .filter((d) => d.isDirectory() && d.name !== '_shared').map((d) => d.name);
    for (const d of dirs) {
      const idx = `supabase/functions/${d}/index.ts`;
      if (existsSync(idx) && /_shared\//.test(readFileSync(idx, 'utf8'))) touched.add(d);
    }
    console.log(`_shared changed — widened to ${touched.size} importer(s)`);
  }
  // A DELETED FUNCTION IS A CHANGED FUNCTION, and it cannot be deployed.
  //
  // `git diff --name-only` lists removals exactly like edits, so deleting 68 functions on 8 Sep
  // 2026 produced 68 slugs whose directory no longer exists, and the typecheck step failed with 68
  // "Cannot find module" errors before a single live function was touched. The deploy was not
  // broken by the deletion; it was broken by assuming every path in a diff still has a file behind
  // it.
  //
  // They are reported rather than quietly dropped. A deletion that vanishes from the deploy log
  // reads identically to one that never happened, and the undeploy is a separate action somebody
  // still has to take -- this line is where they find out it is owed.
  const gone = [...touched].filter((s) => !existsSync(`supabase/functions/${s}/index.ts`));
  if (gone.length) {
    console.log(`${gone.length} function(s) were DELETED in this range and cannot be deployed: ${gone.join(' ')}`);
    console.log('  Removing them from production is a separate step; this run only skips them.');
    for (const s of gone) touched.delete(s);
  }
  slugs = [...touched].sort();
}
slugs = slugs.filter((s) => s !== '_shared');
// The same guard for an explicitly named slug: a typo or a stale runbook should say which name is
// wrong, not fail later inside a typechecker with a file:// URL.
{
  const missing = slugs.filter((s) => !existsSync(`supabase/functions/${s}/index.ts`));
  if (missing.length) die(`no such function(s) in this checkout: ${missing.join(' ')}`);
}
if (!slugs.length) { console.log('No functions to deploy. Nothing to do.'); process.exit(0); }

console.log(`target project: ${ref}${ref === PROD_REF ? '  (PRODUCTION)' : ''}`);
console.log(`${slugs.length} function(s): ${slugs.join(' ')}\n`);

// --dry-run prints the set and stops. What --changed resolves to is the part most able to be
// silently wrong — deploying nothing looks identical to having nothing to deploy — so it has to be
// inspectable without a deploy to inspect it.
if (has('dry-run')) { console.log('--dry-run: stopping before the drift check.'); process.exit(0); }

// Everything past this point talks to the API, so the token is required from here.
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync('C:/Users/Opera/.supabase/access-token')
      ? readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8') : '')).trim();
if (!token) die('No Supabase access token (SUPABASE_ACCESS_TOKEN).');
const H = { Authorization: 'Bearer ' + token };

// A 429 IS THE ROAD BEING BUSY, NOT THE BUILD BEING BROKEN.
//
// MEASURED 13 Aug 2026: a change to _shared/internal_auth.ts made every importer a changed function,
// so the job deployed 130. All 130 uploaded; the read-back then verified 120 and returned
// "CHECK FAILED: 429 ThrottlerException" for the last ten — translate_page, uptime_check,
// vercel_status, vt_scan, wa_inbound, wa_optin_set (retired 14 Sep 2026, PR #657), wa_template_setup, wa_templates_watch,
// workflow_dispatch, yello_scrape. Re-running the job failed on the SAME TEN. That is not a flake:
// the management API's rate limit lands at a fixed point in an alphabetical loop of 130, so the
// verifier could never confirm a full-fleet deploy, and a red job that means "we deployed fine but
// stopped counting" trains everyone to re-run rather than read it.
//
// Retried with backoff, the same shape pack_scorecard.mjs and sql_files_match_live already use.
// ONLY on 429/5xx: a 404 or a 401 is an answer and must stay an answer.
const api = async (path, attempt = 0) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}${path}`, { headers: H });
  if (r.ok) return r.json();
  const body = (await r.text()).slice(0, 200);
  // 3 SEP 2026: seven attempts, not five. A 135-function deploy on main verified 134 and lost
  // supplier_portal to a 429 after five retries (~37s of backoff, inside the API's ~60s throttle
  // window) — twice in one hour, and production carried the code both times (parity OK). Two more
  // attempts take the wait past the window: +38s, +77s.
  if ((r.status === 429 || r.status >= 500) && attempt < 7) {
    await new Promise((s) => setTimeout(s, 1200 * 2 ** attempt));   // 1.2s, 2.4s, 4.8s, 9.6s, 19.2s, 38.4s, 76.8s
    return api(path, attempt + 1);
  }
  throw new Error(`${r.status} ${body}`);
};

// ── RULE 3: THE DRIFT CHECK ────────────────────────────────────────────────────────────────────
const live = await api('/functions').catch((e) => die(`Could not list functions on ${ref}: ${e.message}`));
console.log('--- verify_jwt drift check ---');
if (!Array.isArray(live) || live.length === 0) {
  console.log(`SKIPPED: ${ref} has no deployed functions yet, so config.toml cannot have drifted from it.`);
} else {
  const chk = spawnSync('node', ['scripts/gen_supabase_config.mjs', '--check', `--deploying=${slugs.join(',')}`],
    { stdio: 'inherit', env: { ...process.env, QD_TARGET_REF: ref, SUPABASE_ACCESS_TOKEN: token } });
  if (chk.status !== 0) {
    die('\nREFUSING TO DEPLOY. config.toml and the live project disagree about verify_jwt.\n'
      + 'Resolve it deliberately: regenerate (node scripts/gen_supabase_config.mjs) and review the\n'
      + 'diff, or fix the live value. Do not deploy through drift.');
  }
}

// Versions BEFORE, so "it deployed" is a comparison rather than a claim.
const before = {};
for (const f of slugs) {
  before[f] = await api(`/functions/${f}`).then((m) => Number(m.version)).catch(() => -1);
}

console.log(`\n--- deploying ${slugs.length} function(s) to ${ref} ---`);
const failed = [];
for (const [i, f] of slugs.entries()) {
  // NO verify_jwt FLAG. See rule 3. --use-api matches what the .ps1 does.
  // ── HOW THE CLI IS INVOKED, WHICH TOOK THREE ATTEMPTS ────────────────────────────────────────
  // `shell: true` works but concatenates the argv into a command line, which Node deprecates
  // (DEP0190) and which is a genuine quoting hazard. Naming supabase.cmd directly does NOT work:
  // the file exists, but Windows cannot execute a batch file without an interpreter, so spawnSync
  // returned a failure — caught, correctly, by the version check below rather than by trusting an
  // exit code. Routing through the command interpreter explicitly gets both: a real argv, and a
  // .cmd that runs.
  const [exe, pre] = process.platform === 'win32'
    ? [process.env.ComSpec || 'cmd.exe', ['/c', 'supabase']]
    : ['supabase', []];
  // A REGISTRY BLIP IS NOT A BROKEN FUNCTION (21 Sep 2026, main run 35619142770: 62/63 deployed;
  // email_cron failed because jsr.io's supabase-js manifest "timed out after 10s"). Up to 3 attempts,
  // 5 s then 10 s apart, ONLY when the failure text is a network/registry class
  // (scripts/lib/retry.mjs isTransientDeployFailure, tested in retry.test.mjs). A type or bundle
  // error in our code fails on the first attempt, exactly as before.
  let r;
  for (let attempt = 1; ; attempt++) {
    r = spawnSync(exe, [...pre, 'functions', 'deploy', f, '--project-ref', ref, '--use-api'],
      { encoding: 'utf8', env: { ...process.env, SUPABASE_ACCESS_TOKEN: token } });
    const out = (r.stdout || '') + (r.stderr || '');
    if (r.status === 0 || attempt >= 3 || !isTransientDeployFailure(out)) break;
    console.log(`[${i + 1}/${slugs.length}] ${f} transient failure (attempt ${attempt}/3), retrying: ${out.trim().slice(-200)}`);
    await new Promise((res) => setTimeout(res, 5000 * 2 ** (attempt - 1)));
  }
  if (r.status !== 0) {
    failed.push(f);
    console.log(`[${i + 1}/${slugs.length}] ${f} DEPLOY FAILED exit=${r.status}`);
    console.log((r.stdout || '') + (r.stderr || ''));
  } else {
    console.log(`[${i + 1}/${slugs.length}] ${f} deployed`);
  }
}

// ── RULE 4: VERIFY AGAINST THE DEPLOYED BUNDLE ─────────────────────────────────────────────────
console.log('\n--- verifying against the DEPLOYED bundle ---');
const notVerified = [];
const after = {};
let pass = 0;
// PACE THE LOOP, DO NOT ONLY RECOVER FROM IT. The 429 retry took a 130-function deploy from
// 120 verified to 129, and translate_page still exhausted five attempts — because the loop fires
// one request per function back to back and the retry only starts helping AFTER the limit is
// already hit. A small gap keeps the whole run under it instead: 120ms x 130 adds ~16s to a job
// that already takes minutes, and the backoff stays as the safety net for a genuinely busy API.
// Skipped entirely for small deploys, which never came near the limit.
const PACE_MS = slugs.length > 100 ? 250 : slugs.length > 20 ? 120 : 0;   // 250ms x 135 adds ~34s; the tail of a full redeploy is where the limit bit
for (const f of slugs) {
  if (PACE_MS) await new Promise((s) => setTimeout(s, PACE_MS));
  try {
    const m = await api(`/functions/${f}`);
    // A first deploy has no previous version, so "bumped" is satisfied by the function existing.
    const bumped = before[f] < 0 ? Number(m.version) >= 1 : Number(m.version) > before[f];
    after[f] = Number(m.version);
    if (bumped) pass++; else notVerified.push(f);
    console.log(`${f.padEnd(24)} v${String(m.version).padEnd(4)} (was v${String(before[f]).padEnd(4)}) `
      + `ok=${String(bumped).padEnd(5)} verify_jwt=${m.verify_jwt}`);
  } catch (e) {
    notVerified.push(f);
    console.log(`${f.padEnd(24)} CHECK FAILED: ${e.message}`);
  }
}

console.log(`\nDEPLOYED_OK ${pass}/${slugs.length}`);
if (failed.length) console.log('DEPLOY FAILURES: ' + failed.join(' '));
if (notVerified.length) console.log('NOT VERIFIED:    ' + notVerified.join(' '));
if (failed.length || notVerified.length) process.exit(1);
console.log('ALL GOOD');

// 3 SEP 2026 (MASTER_PLAN A5): a verified deploy is a company event. The change_deployment workflow
// waited on deploy.completed and nothing in the estate ever emitted it; this is the only place that
// KNOWS a deploy completed and was read back, so it says so. Best-effort: a deploy that succeeded is
// not un-succeeded by a failed event write, but the failure is printed, never swallowed.
// 5 SEP 2026: the payload also carries the rule-4 verification itself — pass/of, the slugs not
// verified, and each function's version before and after — so change_deployment step 8 ("promote to
// production", fn_change_deployment_execute) records the parity verdict from the instrument that
// measured it instead of re-asserting it. An event without `verified` is read as "not in payload".
try {
  const payload = JSON.stringify({
    ref, functions: slugs, count: slugs.length, at: new Date().toISOString(),
    verified: { pass, of: slugs.length, not_verified: notVerified,
                versions: Object.fromEntries(slugs.map((f) => [f, { before: before[f], after: after[f] ?? null }])) },
  });
  const q = (v) => "'" + String(v).replace(/'/g, "''") + "'";
  await sql(`select public.fn_emit('deploy.completed', 'deploy', ${q(new Date().toISOString())}, 'deploy_functions', ${q(payload)}::jsonb)`);
  console.log(`deploy.completed emitted for ${slugs.length} function(s)`);
} catch (e) {
  console.log(`deploy.completed NOT emitted: ${String(e?.message || e).slice(0, 200)}`);
}

// A FRESH DEPLOY IS COLD (22 Sep 2026): the first calls to a just-deployed bundle waited ~3 s for it to
// reach a worker, and the first customer after every merge paid that. Measurements and the rule for
// which functions may be called are in scripts/lib/warm_functions.mjs. Best-effort: never fails a deploy.
try {
  const hot = warmable(slugs, (s) => readFileSync(`supabase/functions/${s}/index.ts`, 'utf8'));
  if (hot.length) {
    const anon = (await api('/api-keys')).find((k) => k.name === 'anon')?.api_key;
    if (!anon) throw new Error('no anon key listed for the project');
    const w = await warmFunctions({ url: `https://${ref}.supabase.co`, anon, slugs: hot });
    for (const [s, r] of Object.entries(w)) console.log(`warmed ${s.padEnd(24)} ${r.ok}/${r.calls} answered, slowest per round ${r.slowest_ms.join(' / ')} ms`);
  }
} catch (e) {
  console.log(`warming NOT done: ${String(e?.message || e).slice(0, 200)}`);
}
