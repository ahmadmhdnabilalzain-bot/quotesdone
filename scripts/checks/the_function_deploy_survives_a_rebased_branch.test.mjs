// THE FUNCTION DEPLOY SURVIVES A REBASED BRANCH (it_engineer, 5 Oct 2026). After a rebase or force-push,
// github.event.before names a head that no longer exists, and "deploy changed functions" failed on the diff
// (#1183, #1173, #1158). The scope step must fall back to the merge-base with main when that commit is missing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

test('a missing event.before falls back to the merge-base with origin/main', () => {
  const y = readFileSync(new URL('../../.github/workflows/deploy-functions.yml', import.meta.url), 'utf8');
  assert.match(y, /git cat-file -e "\$before\^\{commit\}"/, 'no check that the base commit still exists');
  assert.match(y, /before=\$\(git merge-base origin\/main HEAD/, 'no merge-base fallback');
  assert.match(y, /fetch-depth: 0/, 'the checkout is shallow, so no merge-base can be found');
});
