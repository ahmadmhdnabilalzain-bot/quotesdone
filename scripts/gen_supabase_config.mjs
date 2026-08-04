// DECISION D1 (3 Aug 2026) - pin verify_jwt in a config file instead of trusting a CLI flag.
//
// THE PROBLEM THIS SOLVES. There was no supabase/config.toml, so `supabase functions deploy` took
// verify_jwt from whatever flag it was given. The habit in the deploy scripts is a blanket
// --no-verify-jwt. 17 of the 190 deployed functions genuinely REQUIRE a JWT - including
// stripe_setup, project_api, brand_upload and the whole os_* operator console. One routine
// redeploy of any of those with the blanket flag silently removes that requirement, and nothing
// fails, nothing logs, and no test catches it. A security regression introduced by a security fix.
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

const token = readFileSync(TOKEN_PATH, 'utf8').trim();

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
  for (const slug of committed.keys()) if (!deployed.has(slug)) drift.push(`${slug}: in config.toml but NOT DEPLOYED`);
  if (drift.length) {
    console.error(`VERIFY_JWT DRIFT (${drift.length}):`);
    for (const d of drift) console.error('  ' + d);
    process.exit(1);
  }
  console.log(`verify_jwt drift check: OK (${sorted.length} functions, ${jwtTrue.length} require a JWT)`);
  process.exit(0);
}

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
