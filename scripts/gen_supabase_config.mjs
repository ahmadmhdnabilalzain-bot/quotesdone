// DECISION D1 (3 Aug 2026) - pin verify_jwt in a config file instead of trusting a CLI flag.
//
// THE PROBLEM THIS SOLVES. There was no supabase/config.toml, so `supabase functions deploy` took
// verify_jwt from whatever flag it was given. The habit in the deploy scripts is a blanket
// --no-verify-jwt. 13 functions genuinely REQUIRE a JWT at the edge - stripe_setup, project_api,
// brand_upload and 10 others. One routine redeploy of any of those with the blanket flag silently
// removes that requirement, and nothing fails, nothing logs, and no test catches it. A security
// regression introduced by a security fix.
//
// NOTE (2 Sep 2026): the os_* operator console is DELIBERATELY verify_jwt=false, NOT an oversight.
// The os_* functions share a build-mode "open door" (fn_os_open_access): when that DB flag is open,
// they run with NO JWT under build-mode@quotesdone.local for operator/build-time recovery, and the OS
// frontend (src/lib/osClient.ts) sends tokenless requests to use it. verify_jwt=true would sever that
// door at the edge, so os_* stay edge-open and are guarded IN CODE (admin.auth.getUser +
// app_secrets.admin_emails, skipped only under the build-mode flag). Do NOT hand-add os_* to the JWT
// list - this file is generated from the LIVE values; the count is whatever live actually is (13).
// Edge-gating os_* is only correct AFTER build mode is retired (a launch decision, see docs/step3).
//
// This generates an explicit block per function from the LIVE Management API values, so the auth
// posture is reviewable in git and a diff is the alarm.
//
// REGENERATE, DO NOT HAND-EDIT:
//   node scripts/gen_supabase_config.mjs
// then `git diff supabase/config.toml`. A line you did not intend to change is the finding.

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// Production remains the default so regeneration keeps producing the committed config.toml.
// QD_TARGET_REF lets --check compare against a staging branch, which is the only way to deploy
// functions anywhere other than production.
const PROJECT_REF = process.env.QD_TARGET_REF || 'htdblwldjkcgjvmqkbeh';
const TOKEN_PATH = 'C:/Users/Opera/.supabase/access-token';
const REPO = process.cwd();
const OUT = join(REPO, 'supabase', 'config.toml');
const FN_DIR = join(REPO, 'supabase', 'functions');

// ── THE ENV VAR COMES FIRST, AND ON CI IT IS THE ONLY THING THERE ────────────────────────────────
// This was `readFileSync(TOKEN_PATH)` with no fallback — the ONLY one of the eleven token readers
// in this repo written that way; qd_guard, apply_sql, deploy_functions and the rest all try
// SUPABASE_ACCESS_TOKEN first. On a Windows desktop the difference is invisible. On a GitHub
// runner the path does not exist, so this threw ENOENT on the first deploy that ever got far
// enough to call it — 8 Aug 2026, minutes after SUPABASE_ACCESS_TOKEN was finally added as a
// secret.
//
// AND THE FAILURE POINTED AT THE WRONG THING. This script is called by deploy_functions.mjs's
// verify_jwt drift check, which treats a non-zero exit as DRIFT. So an ENOENT on a hardcoded
// desktop path was reported as:
//
//     REFUSING TO DEPLOY. config.toml and the live project disagree about verify_jwt.
//
// which is a security-posture alarm about a file that was never read. Anyone acting on that
// message would have gone looking for a verify_jwt mismatch that did not exist.
//
// existsSync guards the read so a missing file is a clear "no token" rather than a stack trace,
// which is the shape deploy_functions.mjs already uses.
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(TOKEN_PATH) ? readFileSync(TOKEN_PATH, 'utf8') : '')).trim();
if (!token) {
  throw new Error('No Supabase access token. Set SUPABASE_ACCESS_TOKEN, or place one at '
    + TOKEN_PATH + ' (https://supabase.com/dashboard/account/tokens).');
}

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/functions`, {
  headers: { Authorization: `Bearer ${token}` },
});
if (!res.ok) throw new Error(`Management API ${res.status}: ${await res.text()}`);
const fns = await res.json();
if (!Array.isArray(fns) || fns.length === 0) throw new Error('Management API returned no functions - refusing to write a config that would drop every entry.');

// Fail closed on a missing value. A function whose verify_jwt we could not read must not be
// silently written as `false` - that is exactly the failure this file exists to prevent.
const bad = fns.filter((f) => typeof f.verify_jwt !== 'boolean');
if (bad.length) throw new Error('verify_jwt missing or non-boolean for: ' + bad.map((f) => f.slug).join(' '));

const repoDirs = new Set(
  existsSync(FN_DIR)
    ? readdirSync(FN_DIR, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith('_')).map((d) => d.name)
    : [],
);
const deployed = new Set(fns.map((f) => f.slug));
const onlyDeployed = [...deployed].filter((s) => !repoDirs.has(s)).sort();
const onlyRepo = [...repoDirs].filter((s) => !deployed.has(s)).sort();

const sorted = [...fns].sort((a, b) => a.slug.localeCompare(b.slug));
const jwtTrue = sorted.filter((f) => f.verify_jwt);

// --check: compare the committed config against live and exit non-zero on drift. This is the
// control that makes the file mean something. Run it in CI and before any deploy batch: if live
// and config disagree, one of them changed without review, and THAT is the finding.
if (process.argv.includes('--check')) {
  if (!existsSync(OUT)) { console.error('FAIL: supabase/config.toml does not exist. Run without --check to generate it.'); process.exit(1); }
  const text = readFileSync(OUT, 'utf8');
  const committed = new Map();
  const re = /^\[functions\.([A-Za-z0-9_-]+)\]\s*\r?\nverify_jwt\s*=\s*(true|false)/gm;
  for (const m of text.matchAll(re)) committed.set(m[1], m[2] === 'true');
  const drift = [];
  for (const f of sorted) {
    if (!committed.has(f.slug)) drift.push(`${f.slug}: live=${f.verify_jwt} but ABSENT from config.toml`);
    else if (committed.get(f.slug) !== f.verify_jwt) drift.push(`${f.slug}: config=${committed.get(f.slug)} live=${f.verify_jwt}`);
  }
  // "In config.toml but not deployed" is a real finding on production: something was removed
  // without review. On a staging project being populated in batches it is simply the state
  // between batches, and treating it as drift blocks every deploy after the first - which is
  // exactly what happened when 38 of 190 functions were live. Absent is not drifted.
  const isProduction = PROJECT_REF === 'htdblwldjkcgjvmqkbeh';
  // ── AND A FUNCTION BEING ADDED IS NOT A FUNCTION THAT WAS REMOVED ─────────────────────────────
  // The finding above is "something was removed without review". A BRAND-NEW production function is
  // in exactly the same state for exactly one moment — config.toml committed, deploy not yet run —
  // and the gate fired on it, so the only tool in the repo could never create a production function
  // at all (observed 8 Aug 2026, supplier_onboard). --deploying names the slugs this run is about
  // to deploy, and only those are exempt: a slug that was genuinely removed is not in the deploy
  // list, so it still fails. The gate keeps its teeth and loses the false positive.
  const deployingArg = process.argv.find((a) => a.startsWith('--deploying='));
  const deploying = new Set((deployingArg ? deployingArg.slice(12) : '').split(',').map((s) => s.trim()).filter(Boolean));
  if (isProduction) {
    for (const slug of committed.keys()) {
      if (deployed.has(slug) || deploying.has(slug)) continue;
      drift.push(`${slug}: in config.toml but NOT DEPLOYED`);
    }
    if (deploying.size) console.log(`note: ${deploying.size} slug(s) exempt as this run's deploy target [${[...deploying].join(' ')}]`);
  } else {
    const undeployed = [...committed.keys()].filter((s) => !deployed.has(s));
    if (undeployed.length) console.log(`note: ${undeployed.length} function(s) in config.toml not yet deployed to ${PROJECT_REF} (not drift)`);
  }
  if (drift.length) {
    console.error(`VERIFY_JWT DRIFT (${drift.length}):`);
    for (const d of drift) console.error('  ' + d);
    process.exitCode = 1;
  } else {
    console.log(`verify_jwt drift check: OK (${sorted.length} functions, ${jwtTrue.length} require a JWT)`);
    process.exitCode = 0;
  }
  // Deliberately NOT process.exit(). On Node 24 for Windows, calling exit() while undici's
  // keep-alive socket is still closing aborts the process with
  //   Assertion failed: !(handle->flags & UV_HANDLE_CLOSING), src\win\async.c line 94
  // which returns non-zero AFTER the check has already printed OK - so a passing drift check
  // read as a failing one and refused a 152-function deploy. Setting exitCode lets Node drain
  // its handles and exit on its own with the status we asked for.
} else {

const lines = [];
lines.push('# GENERATED FILE - do not hand-edit. Regenerate with:');
lines.push('#   node scripts/gen_supabase_config.mjs');
lines.push('#');
lines.push('# Why this file exists (decision D1, 3 Aug 2026). Without it, `supabase functions deploy`');
lines.push('# sets verify_jwt from whatever CLI flag it is passed, and the deploy scripts pass a blanket');
lines.push('# --no-verify-jwt. ' + jwtTrue.length + ' of these ' + sorted.length + ' functions REQUIRE a JWT, so one routine redeploy');
lines.push('# could silently strip that requirement with nothing failing and nothing logged. Pinning the');
lines.push('# value here makes the auth posture reviewable in git: an unintended change shows up as a diff.');
lines.push('#');
lines.push('# Functions that require a JWT (' + jwtTrue.length + '):');
for (const f of jwtTrue) lines.push('#   ' + f.slug);
lines.push('');
lines.push(`project_id = "${PROJECT_REF}"`);
lines.push('');
for (const f of sorted) {
  lines.push(`[functions.${f.slug}]`);
  lines.push(`verify_jwt = ${f.verify_jwt}`);
  lines.push('');
}
writeFileSync(OUT, lines.join('\n'), 'utf8');

console.log(`wrote ${OUT}`);
console.log(`functions=${sorted.length} verify_jwt_true=${jwtTrue.length} verify_jwt_false=${sorted.length - jwtTrue.length}`);
console.log(`deployed-but-not-in-repo (${onlyDeployed.length}): ${onlyDeployed.join(' ') || '-'}`);
console.log(`in-repo-but-not-deployed (${onlyRepo.length}): ${onlyRepo.join(' ') || '-'}`);

}
