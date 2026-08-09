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

function walk(dir, out = []) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) walk(full, out); }
    else if (e.isFile()) out.push(full);
  }
  return out;
}

export function discover(root = REPO) {
  const rel = (f) => path.relative(root, f).split(path.sep).join('/');
  const all = walk(root).map(rel);
  return {
    node: all.filter((f) => NODE_TEST.test(f)).sort(),
    deno: all.filter((f) => DENO_TEST.test(f)).sort(),
    looksLikeATest: all.filter((f) => LOOKS_LIKE_A_TEST.test(path.basename(f))).sort(),
  };
}

function main() {
  const { node, deno } = discover();

  if (!node.length) {
    console.error('no *.test.mjs files found in the repository - that is itself a failure');
    process.exit(1);
  }

  console.log(`running ${node.length} node check file(s):\n  ${node.join('\n  ')}\n`);
  const nodeRes = spawnSync(process.execPath, ['--test', ...node.map((f) => path.join(REPO, f))], { stdio: 'inherit', cwd: REPO });
  let status = nodeRes.status ?? 1;

  if (deno.length) {
    console.log(`\nrunning ${deno.length} deno test file(s):\n  ${deno.join('\n  ')}\n`);
    // No permission flags: `deno test` grants nothing by default on Deno 2, and these are pure
    // functions over byte arrays that must not reach the network or the filesystem. If one ever
    // needs to, failing the permission check is the correct outcome.
    // (attachment.test.ts documents itself as `deno test --allow-none ...`. That flag was removed
    // in Deno 2 and errors out - further evidence the file had never been run.)
    // --no-lock: matches the deno check steps in .github/workflows/checks.yml.
    const denoRes = spawnSync('deno', ['test', '--no-lock', ...deno],
      { stdio: 'inherit', cwd: REPO, shell: process.platform === 'win32' });
    if (denoRes.error && denoRes.error.code === 'ENOENT') {
      // NEVER SKIP. Passing silently when the runner is absent is the precise failure this file
      // was rewritten to remove: for a month the answer to "did the sanitiser tests pass?" was
      // "yes", and the true answer was "they never ran".
      console.error(`\ndeno is not on PATH, and ${deno.length} *.test.ts file(s) need it.`);
      console.error('Install deno (https://deno.land) or remove those files.');
      console.error('A suite that could not run must never be reported as a suite that passed.');
      process.exit(1);
    }
    status = status || (denoRes.status ?? 1);
  }

  process.exit(status);
}

// Only runs when invoked directly, so the guard test can import discover() without executing it.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
