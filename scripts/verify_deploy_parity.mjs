// IS WHAT THE REPO SAYS ACTUALLY RUNNING? — on staging AND production.
//
// This is the gate that did not exist, and its absence is why "13/13 applied" could be true while
// five changed functions were unverified. verify_prod_readiness carries NEGATIVE signatures: three
// defect strings that must be ABSENT from production. That proves three old fixes left. It cannot
// prove new code ARRIVED, and it does not look at staging at all.
//
// WHY A WHOLE-FILE COMPARISON CANNOT WORK, AND WHAT DOES.
// The deployed bundle is transpiled JavaScript, not TypeScript. verify_prod_readiness.mjs:65-75
// measured this directly: the longest matching prefix of doc_extract was 432 chars of 17,317 and of
// customer_api 211 of 81,594, both diverging at the imports. So "is the source a substring of the
// bundle" reports "differs" for every function both before AND after a clean deploy — a check that
// can only ever fail.
//
// But that same measurement records what DOES survive: string literals and comments. Type
// annotations, non-null assertions and rewritten imports do not. So the signature is the set of
// string literals and object keys in the CURRENT source, asserted PRESENT in the deployed bundle.
// A deployment running older code is missing whatever the source has gained since — no diff base
// required, which matters because after a merge to main the branch diff is empty and a
// diff-derived signature silently degrades to "nothing to check", i.e. a green that means nothing.
//
// Read-only by construction: every call is a GET against /functions/<slug>/body.
//
//   node scripts/verify_deploy_parity.mjs                 # functions touched in the last 20 commits
//   node scripts/verify_deploy_parity.mjs --since=HEAD~50  # wider window
//   node scripts/verify_deploy_parity.mjs --all            # every function in the repo
//
// `--staging-only` WAS REMOVED WITH THE STAGING PROJECT (15 Aug 2026), rather than left pointing at
// a ref that no longer resolves. Kept, it would have been the worst kind of flag: every GET against
// the dead project 404s, 404 is read as NOT DEPLOYED, and the run would have failed 202 out of 202
// functions — or, had the 404 been treated as a skip instead, printed "DEPLOY PARITY OK" over an
// empty set of projects. A flag whose only remaining behaviour is to measure nothing is worse than
// no flag: it reads exactly like a scoped check. Passing it now exits non-zero and says why.
import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const FN_DIR = 'supabase/functions';

const argv = process.argv.slice(2);
const arg = (k, d) => (argv.find((a) => a.startsWith(`--${k}=`)) || `--${k}=${d}`).split('=')[1];
const has = (k) => argv.includes(`--${k}`);

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const H = { Authorization: 'Bearer ' + token };

if (has('staging-only')) {
  console.error('--staging-only was removed with the staging project on 15 Aug 2026. There is one');
  console.error(`project (${PROD_REF}); scoping this check to the other one can only measure nothing.`);
  process.exit(2);
}
const REFS = { production: PROD_REF };

// ---- which functions to check -------------------------------------------------------------------
function slugsToCheck() {
  if (has('all')) {
    return readdirSync(FN_DIR, { withFileTypes: true })
      .filter((e) => e.isDirectory() && e.name !== '_shared')
      .filter((e) => existsSync(`${FN_DIR}/${e.name}/index.ts`))
      .map((e) => e.name).sort();
  }
  const since = arg('since', 'HEAD~20');
  const touched = execSync(`git diff --name-only ${since}...HEAD -- ${FN_DIR}/`)
    .toString().split('\n')
    .map((l) => (l.match(/^supabase\/functions\/([^/]+)\//) || [])[1])
    .filter(Boolean);
  return [...new Set(touched)].filter((s) => s !== '_shared' && existsSync(`${FN_DIR}/${s}/index.ts`)).sort();
}

// ---- signatures ---------------------------------------------------------------------------------
// Deliberately conservative. A false STALE sends someone to redeploy something that is already
// live, which burns trust in the gate faster than a missed staleness does.
//   - skip comment lines: they survive transpilation, but a signature that matches its own
//     explanatory comment is exactly the defect verify_prod_readiness hit on 5 Aug 2026
//   - skip template literals containing ${}: the bundle splits them
//   - skip anything with a URL or an env-var shape: those get rewritten
const GENERIC = new Set([
  'application/json', 'Content-Type', 'content-type', 'Authorization', 'authorization',
  'access-control-allow-origin', 'Access-Control-Allow-Origin', 'apikey', 'utf-8',
  'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY',
]);

/**
 * The string literals on ONE line, found by walking it once and tracking which quote opened the
 * current string.
 *
 * THE REGEX THIS REPLACES PRODUCED A PERMANENT FALSE STALE, and a false STALE is the failure this
 * file's own header calls the worse one. `/'([^'\\\n]{14,})'|"([^"\\\n]{14,})"/g` has no idea which
 * quotes are open. On procurement_api's line
 *
 *     if (decision !== 'approved' && decision !== 'rejected') return J({ error: "decision must be …
 *
 * every real literal is too short to qualify, so the scan reached the quote CLOSING 'rejected',
 * treated it as an opening quote, ran 38 characters of code to the next quote — the one opening
 * 'approved' inside the double-quoted string — and emitted
 *
 *     ") return J({ error: \"decision must be"
 *
 * as a signature. That is source code, not a literal; the bundler re-quotes strings, so it can
 * never appear in a deployed bundle and the function reported STALE on both projects forever, on
 * two occasions after being redeployed. Verified by hashing the deployed body: the code was live.
 *
 * A quote inside a string of the other kind ("it's") is now what it actually is — part of the
 * string — instead of a delimiter.
 */
function stringLiterals(line) {
  const out = [];
  let quote = null, buf = '', escaped = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote) {
      // A LITERAL CONTAINING AN ESCAPE IS DROPPED, not repaired. The old regex excluded backslashes
      // for a reason the first version of this rewrite forgot: the signature is compared against a
      // BUNDLE, and the bundler re-encodes escapes, so \n in source is a real newline in the
      // bundle. Substituting a placeholder produced signatures like "xxLANGUAGE: Write ALL…" and
      // took the gate from one false STALE to six.
      if (c === '\\') { escaped = true; i++; continue; }
      if (c === quote) { if (!escaped) out.push(buf.trim()); quote = null; buf = ''; escaped = false; continue; }
      buf += c;
    } else if (c === '"' || c === "'" || c === '`') {
      quote = c; buf = ''; escaped = false;
    }
  }
  // An unterminated quote means the literal spans lines (or the line was cut). Nothing is emitted:
  // a partial string is exactly the kind of not-really-a-literal that caused the defect above.
  return out.filter((s) => s.length >= 14 && !s.includes('${'));
}

function signatures(slug) {
  const src = readFileSync(`${FN_DIR}/${slug}/index.ts`, 'utf8');
  const out = new Set();
  let block = false;
  for (const raw of src.split('\n')) {
    const line = raw.trim();
    if (block) { if (line.includes('*/')) block = false; continue; }
    if (line.startsWith('/*')) { if (!line.includes('*/')) block = true; continue; }
    if (line.startsWith('//') || line.startsWith('*')) continue;
    for (const s of stringLiterals(line)) {
      if (!s || GENERIC.has(s)) continue;
      if (s.includes('://') || /^[A-Z_]{6,}$/.test(s)) continue;
      if (/^[\s.,;:%*+\-/\\|]+$/.test(s)) continue;
      out.add(s);
    }
  }
  // Longest first: the most distinctive strings are the least likely to collide across versions.
  return [...out].sort((a, b) => b.length - a.length).slice(0, 25);
}

// ---- run ----------------------------------------------------------------------------------------
const slugs = slugsToCheck();
const scope = has('all') ? 'every function in the repo' : `functions touched since ${arg('since', 'HEAD~20')}`;
console.log(`\nDEPLOY PARITY — ${slugs.length} function(s), ${scope}`);
console.log(`checking: ${Object.entries(REFS).map(([k, v]) => `${k} ${v}`).join('  |  ')}\n`);

const rows = [];
let checked = 0;
for (const slug of slugs) {
  const sigs = signatures(slug);
  const per = {};
  for (const [env, ref] of Object.entries(REFS)) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/functions/${slug}/body`, { headers: H });
    if (!r.ok) { per[env] = { state: 'NOT DEPLOYED', missing: [] }; continue; }
    const body = await r.text();
    if (!sigs.length) { per[env] = { state: 'NO SIGNATURE', missing: [] }; continue; }
    const missing = sigs.filter((s) => !body.includes(s));
    per[env] = { state: missing.length ? 'STALE' : 'LIVE', missing, sigs: sigs.length };
  }
  rows.push({ slug, sigs: sigs.length, per });
  checked++;
  const cells = Object.entries(per).map(([env, v]) =>
    `${env}=${v.state}${v.state === 'STALE' ? ` ${v.sigs - v.missing.length}/${v.sigs}` : ''}`);
  console.log(`${slug.padEnd(24)} sigs=${String(sigs.length).padStart(2)}  ${cells.join('   ')}`);
  for (const [env, v] of Object.entries(per)) {
    if (v.state === 'STALE') {
      console.log(`${' '.repeat(26)}${env} missing: ${v.missing.slice(0, 3).map((s) => JSON.stringify(s.slice(0, 64))).join(' | ')}`);
    }
  }
}

const bad = rows.filter((r) => Object.values(r.per).some((v) => v.state === 'STALE' || v.state === 'NOT DEPLOYED'));
const nosig = rows.filter((r) => Object.values(r.per).some((v) => v.state === 'NO SIGNATURE'));

console.log(`\n${'='.repeat(96)}`);
if (nosig.length) {
  // Reported, never silently passed: "no signature derivable" reads exactly like a pass and is not
  // one. The first cut of this check used a 24-char floor and reported customer_api that way, whose
  // whole added signature was 'original_stored' — 15 chars.
  console.log(`NOTE  ${nosig.length} function(s) yielded no usable signature: ${nosig.map((r) => r.slug).join(', ')}`);
  console.log(`      These are UNVERIFIED, not verified. Add a distinctive string literal if it matters.`);
}
if (bad.length === 0) {
  console.log(`DEPLOY PARITY OK — ${checked} function(s) carry the repo's current code on ${Object.keys(REFS).join(' and ')}`);
} else {
  console.log(`DEPLOY PARITY FAILED — ${bad.length} of ${checked} function(s) are not running the repo's code:`);
  for (const r of bad) {
    for (const [env, v] of Object.entries(r.per)) {
      if (v.state === 'STALE' || v.state === 'NOT DEPLOYED') console.log(`  ${r.slug} on ${env}: ${v.state}`);
    }
  }
  console.log(`\nRedeploy with: npx supabase functions deploy <slug> --project-ref <ref>`);
}
process.exitCode = bad.length ? 1 : 0;
