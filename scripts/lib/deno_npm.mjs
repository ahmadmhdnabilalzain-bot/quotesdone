// HOW EVERY DENO CALL THE GATE MAKES RESOLVES npm: PACKAGES (it_engineer, 11 Nov 2026; TD-14, TD-24).
//
// `--node-modules-dir=none`: npm packages come from Deno's global cache (DENO_DIR/npm) and Deno never creates or
// rewrites ./node_modules. Until today the gate's Deno steps, scripts/checks/run.mjs's Deno suite and three checks
// that spawn Deno used `=auto`, which writes node_modules/.deno and relinks top-level packages to whatever version
// the Deno import names. Measured 11 Nov 2026, in a worktree whose node_modules had been built lockfile-exact an hour
// earlier: after one offline run of scripts/checks/*.test.mjs, node_modules/.deno existed and the website's own
// pdfjs-dist (6.5.438 in package-lock.json) was a symlink to 4.10.38, the version pdf_native's Deno tests import. A
// next build after that bundles a pdfjs the lockfile never named.
//
// `=auto` was chosen on 9 Sep 2026 because with neither flag a root package.json makes Deno EXPECT a node_modules
// that a fresh checkout lacks ("Could not find a matching package"). `none` removes that expectation too: measured
// 11 Nov 2026, `deno check` of all 78 functions and the gate's Deno test steps pass with it.
//
// A test that READS a file inside an npm package at run time (tesseract.js's .wasm, for one) now reads it from the
// global cache, so its --allow-read must name denoNpmCache() as well as the repository. Module loading itself needs
// no read grant.
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const DENO_NPM_FLAGS = ['--no-lock', '--node-modules-dir=none'];

let cache;
/** Deno's npm cache directory (where `none` reads packages from), read once from `deno info --json`. */
export function denoNpmCache() {
  if (cache === undefined) {
    const r = spawnSync('deno', ['info', '--json'], { encoding: 'utf8' });
    try { cache = JSON.parse(r.stdout).npmCache; } catch { cache = null; }
    cache ||= join(process.env.DENO_DIR || join(homedir(), '.cache', 'deno'), 'npm');
  }
  return cache;
}
