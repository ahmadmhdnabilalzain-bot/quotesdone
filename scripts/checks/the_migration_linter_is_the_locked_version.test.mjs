// THE MIGRATION LINTER IS THE VERSION THE LOCKFILE NAMES (it_engineer, 27 Oct 2026).
//
// Measured 27 Oct 2026: package.json asked for squawk-cli "^2.66.0" and package-lock.json locked 2.66.0. npm ci honours
// the lock, but the deno steps (deno check / deno test --node-modules-dir=auto --no-lock) resolve package.json ranges
// themselves, ignore the lockfile, and re-pointed node_modules/squawk-cli at 2.70.0 (node_modules/.deno/squawk-cli@2.70.0).
// 2.70.0 added the ban-drop-constraint rule, so the gate's migration-lint step (npx squawk) failed on an unchanged,
// long-applied migration (20260815050000_phase_a_organization_closure.sql:104) while 2.66.0 reports 0 issues in the
// same 8 files. Which linter ran depended on whether a deno step had run first: not reproducible.
// The fix is an exact pin, so every resolver lands on the locked version. This FAILS when the pin is loosened to a
// range again, or when the pin and the lock disagree. Repository only; no token needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const pkg = JSON.parse(readFileSync(join(REPO, 'package.json'), 'utf8'));
const lock = JSON.parse(readFileSync(join(REPO, 'package-lock.json'), 'utf8'));
const EXACT = /^\d+\.\d+\.\d+$/;

test('squawk-cli is pinned to one exact version, not a range a resolver may float', () => {
  const want = pkg.devDependencies?.['squawk-cli'];
  assert.ok(want, 'squawk-cli is no longer a devDependency: the gate\'s migration-lint step runs npx squawk');
  assert.match(want, EXACT, `package.json asks for squawk-cli "${want}"; a range lets deno's --node-modules-dir=auto pick a newer linter than the lock`);
});

test('the pin, the lockfile root and the locked package all name the same squawk-cli', () => {
  const want = pkg.devDependencies['squawk-cli'];
  assert.equal(lock.packages?.['']?.devDependencies?.['squawk-cli'], want, 'package-lock.json root disagrees with package.json: run npm install');
  assert.equal(lock.packages?.['node_modules/squawk-cli']?.version, want, 'package-lock.json locks a different squawk-cli than package.json pins');
});
