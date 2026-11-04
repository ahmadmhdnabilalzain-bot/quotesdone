// EVERY FAILURE DRILL NAMES A TEST THAT EXISTS AND RUNS IT (it_engineer, 3 Nov 2026).
//
// docs/release/qualification_matrix.md §5.1 lists drills D1-D12. On 3 Nov 2026 they were built as Deno tests of the real
// modules with stubbed dependencies (docs/reports/failure_drills_2026-11-03/README.md), and the asset column now names
// the files. A narrative column that names a file is a claim; this makes it a measurement, so a drill cannot read PASS
// over a file that was renamed, deleted, or never had a test for that drill in it. Offline, no token, no network.
//
// For every row of the §5.1 table:
//   - the asset cell names at least one *.test.ts file, OR says NOT DRILLABLE OFFLINE (a written verdict, never a pass);
//   - every named *.test.ts exists, and has a Deno.test whose name starts with that drill's id (e.g. 'D4 ', or 'D6.3 ');
//   - a cell that says PASS names at least one test (PASS over nothing is the failure this check exists for).
// Known-bad control: the row parser must find all twelve drills, so a reformatted table cannot pass by matching none.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const matrix = readFileSync(join(REPO, 'docs/release/qualification_matrix.md'), 'utf8');
const section = matrix.slice(matrix.indexOf('### 5.1 Drills (D)'), matrix.indexOf('### 5.2'));
const rows = section.split('\n').filter((l) => /^\| D\d+ \|/.test(l)).map((l) => {
  const cells = l.split(' | ');
  return { id: cells[0].replace(/^\| /, '').trim(), asset: cells.at(-1).replace(/ \|$/, '') };
});

test('the §5.1 table is read: twelve drills, D1 to D12', () => {
  assert.deepEqual(rows.map((r) => r.id), Array.from({ length: 12 }, (_, i) => 'D' + (i + 1)));
});

for (const r of rows) {
  test(`${r.id}: its asset names a drill test that exists and carries a '${r.id} ' (or '${r.id}.n') test, or a NOT DRILLABLE OFFLINE verdict`, () => {
    const files = [...r.asset.matchAll(/`([^`]+\.test\.ts)`/g)].map((m) => m[1]);
    if (/\bPASS\b/.test(r.asset)) assert.ok(files.length, `${r.id} says PASS and names no test: ${r.asset}`);
    if (!files.length) {
      assert.match(r.asset, /NOT DRILLABLE OFFLINE/, `${r.id} names no test and gives no written verdict: ${r.asset}`);
      return;
    }
    for (const f of files) {
      assert.ok(existsSync(join(REPO, f)), `${r.id} names ${f}, which does not exist`);
      const src = readFileSync(join(REPO, f), 'utf8');
      const named = new RegExp(String.raw`Deno\.test\(\s*(?:\{\s*name:\s*)?['\`"]${r.id}[ .]`).test(src);
      assert.ok(named, `${f} has no Deno.test named '${r.id} ...' or '${r.id}.n ...'`);
    }
  });
}
