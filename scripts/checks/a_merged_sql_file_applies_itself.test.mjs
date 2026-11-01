// The apply reads only what a push adds to MANIFEST.txt (ledger 1463). Known-bad controls: a removed line and a comment.
import test from 'node:test';
import assert from 'node:assert/strict';
import { addedFiles } from '../ci/apply_new_manifest_lines.mjs';

test('only added scripts/sql lines are applied, in order', () => {
  const diff = ['--- a/scripts/sql/MANIFEST.txt', '+++ b/scripts/sql/MANIFEST.txt', '-scripts/sql/old.sql', '+# a note', '+scripts/sql/a.sql', ' scripts/sql/same.sql', '+scripts/sql/b.sql'].join('\n');
  assert.deepEqual(addedFiles(diff), ['scripts/sql/a.sql', 'scripts/sql/b.sql']);
});
