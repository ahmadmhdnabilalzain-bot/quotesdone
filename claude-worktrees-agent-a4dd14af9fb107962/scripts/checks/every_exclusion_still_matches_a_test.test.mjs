// An exclusion in scripts/checks/test-profiles.json is a debt with a name on it. This asserts it
// still points at something real.
//
// THE DEFECT THIS PREVENTS. A profile that excludes "production: the thing that used to fail" keeps
// excluding it after the test is renamed, rewritten or deleted — and if a NEW test is ever given
// that name, the profile silences it on arrival. A suppression that outlives its subject is exactly
// the shape of a stale deferral, and this repository has already produced that shape twice: a
// keep-list that missed a category, and four Phase A deferrals that no check knew were approved.
//
// So: every excluded test name must still be findable in the file the profile says it lives in, and
// every exclusion must carry an owner, a phase and a reason. A profile entry that cannot say who
// owes the work is not a deferral, it is a hiding place.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadProfile, skipPatternFor } from './run.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const doc = JSON.parse(readFileSync(join(REPO, 'scripts', 'checks', 'test-profiles.json'), 'utf8'));
const names = Object.keys(doc.profiles ?? {});

test('there is at least one profile, and phase-d is one of them', () => {
  assert.ok(names.length > 0, 'test-profiles.json defines no profiles');
  assert.ok(names.includes('phase-d'),
    `no phase-d profile. Phase D readiness requires a dedicated deterministic suite; profiles found: ${names.join(', ')}`);
});

for (const name of names) {
  const p = loadProfile(name, REPO);

  test(`profile ${name}: every exclusion names a file that exists`, () => {
    for (const e of p.excluded) {
      assert.ok(existsSync(join(REPO, e.file)),
        `profile ${name} excludes ${JSON.stringify(e.test)} from ${e.file}, and that file does not `
        + 'exist. An exclusion pointing at a deleted file silences any future test that takes the '
        + 'same name. Delete the exclusion.');
    }
  });

  test(`profile ${name}: every excluded test still exists in the file that owns it`, () => {
    for (const e of p.excluded) {
      const src = readFileSync(join(REPO, e.file), 'utf8');
      // Test names in this repository are commonly built as `${label}: the assertion`, so the
      // literal full name is not in the source. The part after the label is, and that is what
      // identifies the test.
      const tail = e.test.replace(/^[^:]*:\s*/, '');
      assert.ok(src.includes(tail),
        `profile ${name} excludes ${JSON.stringify(e.test)}, but ${e.file} no longer contains `
        + `${JSON.stringify(tail)}. The test was renamed or removed and the exclusion outlived it. `
        + 'Delete the exclusion, or update it to the current name.');
    }
  });

  test(`profile ${name}: every exclusion carries an owner, a phase and a reason`, () => {
    for (const e of p.excluded) {
      for (const field of ['owner', 'phase', 'reason']) {
        assert.ok(typeof e[field] === 'string' && e[field].trim().length > 10,
          `profile ${name} excludes ${JSON.stringify(e.test)} with no usable ${field}. An exclusion `
          + 'that cannot say who owes the work is a hiding place, not a deferral.');
      }
    }
  });

  test(`profile ${name}: the skip pattern matches every excluded name and nothing else`, () => {
    const pattern = skipPatternFor(p);
    if (!p.excluded.length) { assert.equal(pattern, null); return; }
    const re = new RegExp(pattern);
    for (const e of p.excluded) {
      assert.match(e.test, re, `the generated skip pattern does not match ${JSON.stringify(e.test)}`);
    }
    // Anchored, so an exclusion cannot swallow a longer test name that merely contains it.
    for (const e of p.excluded) {
      assert.doesNotMatch(`${e.test} and something else entirely`, re,
        'the skip pattern is not anchored, so it would also silence longer test names that happen '
        + 'to start with an excluded one');
    }
  });
}
