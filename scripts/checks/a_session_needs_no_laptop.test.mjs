// A Claude Code cloud session needs nothing from the founder's laptop (owner: it_engineer, 26 Oct 2026).
//
// Founder's order of 26 Oct 2026: he must be able to run claude.ai/code cloud sessions on this repository
// from his phone. Measured that day: 110 live scripts read the Supabase token from a fixed Windows path,
// 20 more wrote to or read from folders that exist only on his machine, and the repository's two
// PreToolUse hooks called an .EXE by its absolute Windows path. On Linux each failed with an ENOENT
// that named a Windows path instead of the missing variable.
//
//   1. no live file names a Windows user folder (scripts/archive/ is history, and is skipped);
//   2. the token helper prefers SUPABASE_ACCESS_TOKEN, and with neither the variable nor a CLI login
//      its error NAMES the variable (asserted in a child process, so this run's own token is untouched).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../', import.meta.url));
// Built from parts so this file does not match itself.
const WIN_USER = new RegExp(['C:', '[\\\\/]+', 'Users', '[\\\\/]+', 'Opera'].join(''), 'i');

test('no live script, hook or function names a folder on the founder\'s laptop', () => {
  const files = execFileSync('git', ['ls-files', 'scripts', 'supabase', '.claude/settings.json', 'package.json'],
    { cwd: REPO, encoding: 'utf8' }).split('\n').filter((f) => f && !f.startsWith('scripts/archive/'));
  const hits = files.filter((f) => { try { return WIN_USER.test(readFileSync(REPO + f, 'utf8')); } catch { return false; } });
  assert.deepEqual(hits, [], 'these files name a laptop path; use a repo-relative path, an env var or os.tmpdir()');
});

test('the token comes from SUPABASE_ACCESS_TOKEN, and its absence is reported by name', () => {
  const helper = new URL('../lib/supabase_token.mjs', import.meta.url).href;
  const run = (env) => spawnSync(process.execPath, ['--input-type=module', '-e',
    `import { supabaseAccessToken } from '${helper}'; console.log(supabaseAccessToken());`],
    { encoding: 'utf8', env: { PATH: process.env.PATH, ...env } });
  // A home with no CLI login in it: the variable is the only source.
  const home = tmpdir() + '/qd-no-login-' + process.pid;
  const set = run({ SUPABASE_ACCESS_TOKEN: ' from-env ', HOME: home, USERPROFILE: home });
  assert.equal(set.stdout.trim(), 'from-env');
  const unset = run({ HOME: home, USERPROFILE: home });
  assert.notEqual(unset.status, 0);
  assert.match(unset.stderr, /SUPABASE_ACCESS_TOKEN is not set/);
});
