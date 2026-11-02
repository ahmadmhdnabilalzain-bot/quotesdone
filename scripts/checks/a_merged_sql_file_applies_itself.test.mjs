// The apply reads only what a push adds to MANIFEST.txt (ledger 1463). Known-bad controls: a removed line, a comment and a probe.
import test from 'node:test';
import assert from 'node:assert/strict';
import { addedFiles, seatOf } from '../ci/apply_new_manifest_lines.mjs';

test('only added scripts/sql lines are applied, in order', () => {
  const diff = ['--- a/scripts/sql/MANIFEST.txt', '+++ b/scripts/sql/MANIFEST.txt', '-scripts/sql/old.sql', '+# a note', '+scripts/sql/a.sql', ' scripts/sql/same.sql', '+scripts/sql/b.sql', '+scripts/sql/b_probe.sql'].join('\n');
  assert.deepEqual(addedFiles(diff), ['scripts/sql/a.sql', 'scripts/sql/b.sql']);
});

test('an apply always names a seat: the file header first, then the merge title, even one naming two seats', () => {
  assert.equal(seatOf('-- Seat: it_engineer, for x\nselect 1;', 'customer_support: y'), 'it_engineer');
  assert.equal(seatOf('select 1;', 'customer_support, sales_engineer: y'), 'customer_support');
  assert.equal(seatOf('select 1;', 'Merge branch'), 'it_engineer');
});
