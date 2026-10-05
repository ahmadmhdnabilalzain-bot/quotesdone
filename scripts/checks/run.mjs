// Runs the repository's whole test suite: the Node checks in this directory, and the Deno tests
// that live beside the edge-function code they cover.
//
// Deliberately no test framework. The repository had zero tests and no runner; adding Vitest or
// Jest to get these files running would mean a dependency tree, a config file and a version to
// keep current, for something `node --test` and `deno test` already do. When the suite grows past
// what this can express - browser E2E, snapshot testing - that is the moment to add a framework,
// not before.
//
// 4 AUG 2026. This runner used to read only `*.test.mjs` in this one directory, and CI ran
// `npm test`, `npm run typecheck` and `deno check` - `deno test` appeared nowhere. So
// supabase/functions/_shared/attachment.test.ts, 178 lines of behavioural tests over the sanitiser
// at the centre of audit 9.1, had never executed. Not failed: never run. A test suite CI cannot
// see is not a test suite.
//
// Three things changed, and the third is the one that matters:
//   1. discovery walks the whole repository, not this one directory
//   2. `*.test.ts` is handed to `deno test`, and a missing deno is a HARD FAILURE, never a skip
//   3. discovery is exported, and every_test_file_is_run.test.mjs asserts that every file this
//      repository would call a test is claimed by it - so a `.test.tsx` or a `.spec.ts` added
//      later cannot quietly go unrun the way attachment.test.ts did
//
//   npm test            - run everything
//   node scripts/checks/run.mjs
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');

// The two runners this repository has. Exported so the guard test asserts against the real
// patterns rather than against a copy of them - a guard that restates the thing it guards proves
// only that somebody typed it twice.
export const NODE_TEST = /\.test\.mjs$/;
export const DENO_TEST = /\.test\.ts$/;
// Anything a reader would call a test file. Wider than the two above ON PURPOSE: the gap between
// this set and those two is exactly the defect being prevented.
export const LOOKS_LIKE_A_TEST = /\.(test|spec)\.[cm]?[jt]sx?$/;

// `vendor` is here for a reason that only shows up off CI. It holds UNTRACKED third-party
// reference material — a checkout of PaddleOCR's JS packages carries 280 of the 281 `*.test.ts`
// files this walk finds, against exactly one of ours. CI never sees them because they are not in
// git, so CI has always been green; a developer machine that has them hands all 281 paths to
// `deno test` on a single command line and Windows refuses at its 32k limit with "The command line
// is too long". The gate was therefore GREEN IN CI AND UNRUNNABLE LOCALLY, which is the worst
// combination — and it stopped being academic on 9 Aug 2026 when the Actions allowance ran out.
//
// Excluding it is also correct on its own terms: a vendored library's own suite is not this
// repository's gate. It can fail for reasons that have nothing to do with this codebase, and it
// costs CI minutes to prove someone else's tests still pass. discover() is exported and
// every_test_file_is_run.test.mjs asserts against the same walk, so both sides stay consistent.
const SKIP_DIRS = new Set(['.git', 'node_modules', '.next', 'dist', 'build', 'out', '.vercel', 'coverage', '.turbo', 'vendor']);

// A DIRECTORY THAT CARRIES ITS OWN `.git` IS A DIFFERENT REPOSITORY, NOT PART OF THIS ONE.
//
// 17 AUG 2026. The independent acceptance measured this walk and it returned 96 node test files,
// THIRTY-NINE of them out of `$WT/` — an untracked 159 MB copy of this repository dated 14 Aug,
// sitting inside the working tree. `$WT` is not in SKIP_DIRS, so `npm test` was handing the runner
// a second, stale copy of the estate's own gates. Among them:
//
//   $WT/scripts/checks/v3_runtime_behaviour.test.mjs:26
//     const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh', staging: 'pglpqrhvozwepymcuunn' };
//
//   — a live reference to the Supabase project DELETED on 15 Aug 2026 — and a copy of
//   sql_files_match_live.test.mjs, which this repository retired.
//
// CI never saw it because CI checks out clean; the developer machine did, and a check that is green
// in CI and wrong locally is the same shape as the vendor/ problem this walk was already rewritten
// once to fix. Naming `$WT` in SKIP_DIRS would fix today and not tomorrow. A nested checkout always
// carries a `.git` entry — file (worktree pointer) or directory — so that is what is tested, and any
// future copy under any name is excluded the moment it appears.
const SKIPPED_NESTED = [];
function isNestedRepo(dir) {
  return fs.existsSync(path.join(dir, '.git'));
}

function walk(dir, out = [], root = dir) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      if (isNestedRepo(full)) { SKIPPED_NESTED.push(path.relative(root, full).split(path.sep).join('/')); continue; }
      walk(full, out, root);
    } else if (e.isFile()) out.push(full);
  }
  return out;
}

/** Nested checkouts excluded by the most recent discover(). Reported, never silently dropped. */
export function nestedReposSkipped() { return [...SKIPPED_NESTED]; }

export function discover(root = REPO) {
  const rel = (f) => path.relative(root, f).split(path.sep).join('/');
  SKIPPED_NESTED.length = 0;
  const all = walk(root, [], root).map(rel);
  return {
    node: all.filter((f) => NODE_TEST.test(f)).sort(),
    deno: all.filter((f) => DENO_TEST.test(f)).sort(),
    looksLikeATest: all.filter((f) => LOOKS_LIKE_A_TEST.test(path.basename(f))).sort(),
  };
}

/**
 * A named profile from test-profiles.json, or null for "run everything".
 *
 * 18 AUG 2026. There was no selection mechanism here at all — discover() found every *.test.mjs and
 * ran it — so a later-phase test was not excluded from a phase suite, it was simply failing in it.
 * The final acceptance audit counted five such failures and could not tell them apart from
 * regressions without reading each one. An exclusion is now a committed row with an owner, a reason
 * and the measurement that justified it, and a guard test asserts every exclusion still matches a
 * real test so one cannot outlive its subject.
 */
export function loadProfile(name, root = REPO) {
  if (!name) return null;
  const file = path.join(root, 'scripts', 'checks', 'test-profiles.json');
  const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
  const p = doc.profiles?.[name];
  if (!p) {
    const known = Object.keys(doc.profiles ?? {}).join(', ') || '(none)';
    console.error(`unknown test profile ${JSON.stringify(name)}. Known profiles: ${known}`);
    console.error(`Profiles are defined in scripts/checks/test-profiles.json.`);
    process.exit(2);
  }
  return { name, ...p, excluded: p.excluded ?? [] };
}

/** Exact test names a profile excludes, as one anchored alternation for --test-skip-pattern. */
export function skipPatternFor(profile) {
  if (!profile?.excluded?.length) return null;
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return `^(?:${profile.excluded.map((e) => esc(e.test)).join('|')})$`;
}

// THE COMMAND LINE HAS A CEILING, AND A SPAWN THAT CANNOT START IS A FAILURE (5 Oct 2026, it_engineer).
// Every node test path used to go to ONE `node --test` call. On Windows, past ~32k characters, the
// spawn answered "The command line is too long" and the run printed SUCCESS without executing a test.
// Files now go in batches well under that limit, and the run fails on ANY spawn error or any batch
// whose status is not 0 — a null status (killed, never started) is a failure, never a pass.
//   prevented by: scripts/checks/run_fails_when_a_batch_cannot_start.test.mjs
export const MAX_ARGS_CHARS = 6000;
export function batches(files, max = MAX_ARGS_CHARS) {
  const out = [];
  let cur = [], len = 0;
  for (const f of files) {
    if (cur.length && len + f.length + 1 > max) { out.push(cur); cur = []; len = 0; }
    cur.push(f); len += f.length + 1;
  }
  if (cur.length) out.push(cur);
  return out;
}

/** Runs `cmd ...baseArgs ...batch` per batch. 0 only when every batch started AND exited 0; 127 = cmd not found. */
export function runBatched(cmd, baseArgs, files, opts, spawn = spawnSync) {
  let status = 0;
  for (const b of batches(files)) {
    const r = spawn(cmd, [...baseArgs, ...b], opts);
    if (r.error) {
      console.error(`\n${cmd} could not start a batch of ${b.length} file(s): ${r.error.code || r.error.message}`);
      if (r.error.code === 'ENOENT') return 127;
      status = status || 1;
    } else if (r.status !== 0) status = status || (r.status ?? 1);
  }
  return status;
}

function main() {
  const { node, deno } = discover();
  const profileName = (process.argv.find((a) => a.startsWith('--profile=')) || '').split('=')[1];
  const profile = loadProfile(profileName);

  if (!node.length) {
    console.error('no *.test.mjs files found in the repository - that is itself a failure');
    process.exit(1);
  }

  const nested = nestedReposSkipped();
  if (nested.length) {
    console.log(`EXCLUDED — nested checkout(s) inside the working tree, not part of this repository:`);
    for (const n of nested) console.log(`  ${n}/`);
    console.log(`  These carry their own .git. Delete them or move them outside the tree; they are`);
    console.log(`  stale copies of this repository's own gates and one of them still names the`);
    console.log(`  Supabase project deleted on 15 Aug 2026.\n`);
  }

  if (profile) {
    console.log(`PROFILE ${profile.name} — ${profile.description}`);
    for (const [k, v] of Object.entries(profile.env ?? {})) process.env[k] = v;
    if (profile.env) console.log(`  contract: ${Object.entries(profile.env).map(([k, v]) => `${k}=${v}`).join(' ')}`);
    // NAMED, NEVER SILENT. Every excluded test is printed with its owner on the run that skips it,
    // so "the suite is green" and "two tests are owed to the knowledge phase" are read together.
    if (profile.excluded.length) {
      console.log(`  EXCLUDED — ${profile.excluded.length} test(s), each owned and owed:`);
      for (const e of profile.excluded) {
        console.log(`    ${e.test}`);
        console.log(`      ${e.file} · ${e.phase} · owner: ${e.owner}`);
      }
    } else {
      console.log('  EXCLUDED — none');
    }
    console.log('');
  }

  console.log(`running ${node.length} node check file(s):\n  ${node.join('\n  ')}\n`);
  // ONE AT A TIME, BECAUSE THE MANAGEMENT API IS THE SHARED RESOURCE.
  //
  // 17 AUG 2026. `node --test` defaults to one worker per CPU, and most of these files talk to the
  // Supabase management API. The independent acceptance ran the suite and TEN of nineteen failures
  // were `429 ThrottlerException: Too Many Requests` — on four different files, several after ~50
  // seconds of waiting, and a different ten on a different run. Four of those files already carry
  // their own 429 retry; the concurrency exhausted the budget anyway, which is what says the
  // problem is here and not in the retry loops.
  //
  // A green suite is worth less than a slow one if red means "the API was busy". Serialising costs
  // wall-clock and buys a deterministic answer. Raise it again only with a shared rate limiter in
  // front of the API, not by hoping.
  // ponytail: --test-concurrency=1, revisit when a shared limiter exists.
  const skip = skipPatternFor(profile);
  let status = runBatched(process.execPath,
    ['--test', '--test-concurrency=1', ...(skip ? [`--test-skip-pattern=${skip}`] : [])],
    node.map((f) => path.join(REPO, f)),
    { stdio: 'inherit', cwd: REPO });

  // THE CHECKS THAT ARE NOT `*.test.mjs`, 22 Sep 2026 (documents-language audit, DL-12).
  // language_follows_registration.mjs is a full gate — it walks production in one rolled-back
  // transaction, reads the 396 intake questions and then reads every touchpoint's source — and it
  // was in scripts/checks with nothing running it. It had been RED on main since 14 Sep on two
  // assertions that named the pre-fix code, and nobody saw it because nothing ran it. Its first
  // part needs a management token; when there is none the run says so by name rather than passing
  // quietly (the rule this runner was rewritten for).
  //
  // AND IT IS SPAWNED UNCONDITIONALLY, 22 Sep 2026 (second review of PR #857). The first version of
  // this loop skipped the file when no token was present — and this job has no token, so the file was
  // "registered and never enforced", exactly the state it was added to end. The check itself now
  // separates its parts: without a token the production walk and the 396 intake questions print
  // NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL by name, and the source assertions — the documents, the
  // edge functions, the portals, and the arabic_frame deploy-order bridge — run and fail it here.
  for (const check of ['scripts/checks/language_follows_registration.mjs']) {
    console.log(`\nrunning ${check}`);
    const r = spawnSync(process.execPath, [path.join(REPO, check)], { stdio: 'inherit', cwd: REPO });
    status = status || (r.status ?? 1);
  }

  if (deno.length) {
    console.log(`\nrunning ${deno.length} deno test file(s):\n  ${deno.join('\n  ')}\n`);
    // No permission flags: `deno test` grants nothing by default on Deno 2, and these are pure
    // functions over byte arrays that must not reach the network or the filesystem. If one ever
    // needs to, failing the permission check is the correct outcome.
    // (attachment.test.ts documents itself as `deno test --allow-none ...`. That flag was removed
    // in Deno 2 and errors out - further evidence the file had never been run.)
    // --no-lock: matches the deno check steps in .github/workflows/checks.yml.
    //
    // --node-modules-dir=auto, added 9 Sep 2026, and it is not cosmetic. observe.test.ts imports
    // _shared/observe.ts, which imports supabase-js, which pulls npm:@supabase/realtime-js. On this
    // machine that resolved silently because node_modules already existed; the CI runner has none,
    // so `deno test` died with "Could not find a matching package ... in the node_modules directory"
    // BEFORE running a single assertion — the whole Deno suite reported as one failure with no test
    // names in it. Every `deno check` step in this repo already carries this flag; the test step
    // did not, and nothing needed it until a test reached a module with an npm dependency.
    // --allow-env, SCOPED to three names (15 Sep 2026): resend_inbound/index.test.ts drives the live
    // webhook's own handler, whose module builds its Supabase client from these at import. The test points
    // them at a stub host and replaces fetch; no network, no filesystem, no other variable is granted.
    // --allow-read, SCOPED to one fixtures folder (21 Sep 2026): supplier_api/quote_review.test.ts
    // replays the browser auditor's own quotation PDF and CSVs, committed under supplier_api/fixtures/.
    // CI refused with NotCapable "Requires read access to .../fixtures/ZZDEMO_quotation_D958E1EA.pdf"
    // while the same test passed locally. Only that folder is readable; the rest of the tree is not.
    const denoStatus = runBatched('deno', ['test', '--no-lock', '--node-modules-dir=auto',
      '--allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE',
      // Widened to READ the repository (21 Sep 2026, PR #780): the catalogue tests read synthetic
      // fixtures, the taxonomy seed in scripts/sql, and tesseract.js's wasm under node_modules/.deno.
      // A per-folder list failed to resolve those files; the repository root read-only is the simple
      // rule. Still no write, no network, no environment beyond the three names above.
      // --allow-net, SCOPED to loopback (23 Sep 2026, PR #856): _shared/timed_fetch.test.ts proves the
      // helper 21 functions now share rejects instead of hanging, and to do that it has to accept a real
      // connection and answer nothing — Deno.listen on 127.0.0.1. CI failed with NotCapable "Requires net
      // access to 127.0.0.1:0" while `deno test -A` passed locally, which is the same shape as the two
      // widenings above. A per-test `permissions: { net: [...] }` does NOT work here: Deno refuses with
      // "Can't escalate parent thread permissions", so the grant has to be on the runner. 127.0.0.1 is the
      // whole grant — no hostname resolves to it but itself, so no test can reach a real service, and
      // nothing outbound (Resend, Twilio, Stripe, Supabase) is reachable from this runner.
      '--allow-net=127.0.0.1',
      `--allow-read=${REPO}`], deno,
      { stdio: 'inherit', cwd: REPO, shell: process.platform === 'win32' });
    if (denoStatus === 127) {
      // NEVER SKIP. Passing silently when the runner is absent is the precise failure this file
      // was rewritten to remove: for a month the answer to "did the sanitiser tests pass?" was
      // "yes", and the true answer was "they never ran".
      console.error(`\ndeno is not on PATH, and ${deno.length} *.test.ts file(s) need it.`);
      console.error('Install deno (https://deno.land) or remove those files.');
      console.error('A suite that could not run must never be reported as a suite that passed.');
      process.exit(1);
    }
    status = status || denoStatus;
  }

  process.exit(status);
}

// Only runs when invoked directly, so the guard test can import discover() without executing it.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
