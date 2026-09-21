// The purge census must be the table it counts: replays the 21 Sep 2026 shapes (a slice counted twice
// after a gateway 524, a slice never counted, a doubled SIZE row) and the clean case.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { censusMismatches } from './purge_census.mjs';

const live = [{ source_kind: 'standard', n: 2026198 }, { source_kind: 'cert', n: 75466 }];

test('a census equal to the table, with one SIZE row, passes', () => {
  assert.deepEqual(censusMismatches([{ source_kind: 'standard', rows: '2026198' }, { source_kind: 'cert', rows: 75466 }], live, 1), []);
});

test('a slice counted twice, a slice never counted, and a doubled SIZE row are each named', () => {
  const bad = censusMismatches([{ source_kind: 'standard', rows: 1114611 }, { source_kind: 'cert', rows: 150932 }], live, 2);
  assert.equal(bad.length, 3);
  assert.match(bad.join('\n'), /cert: census 150932, live 75466 \(counted twice/);
  assert.match(bad.join('\n'), /standard: census 1114611, live 2026198 \(not counted/);
  assert.match(bad.join('\n'), /SIZE .* 2, expected exactly 1/);
});

test('a kind the census never saw, or one the table no longer has, is a mismatch', () => {
  assert.equal(censusMismatches([{ source_kind: 'standard', rows: 2026198 }], live, 1).length, 1);
  assert.equal(censusMismatches([...live.map((r) => ({ source_kind: r.source_kind, rows: r.n })), { source_kind: 'ghost', rows: 5 }], live, 1).length, 1);
});

test('the driver verifies the census, never retries a census write on a 5xx, and slices every kind', () => {
  const src = readFileSync(new URL('./purge_kb_bulk.mjs', import.meta.url), 'utf8');
  assert.match(src, /censusMismatches\(/, 'purge_kb_bulk.mjs no longer checks the census against the table');
  assert.match(src, /await sql\(censusSql\([^\n]*\), 0, false\)/, 'a census INSERT is retried on 5xx again — a 524 can commit behind the error and count twice');
  assert.doesNotMatch(src, /censusSql\(`k\.source_kind <> 'standard'`\)/, 'the unsliced non-standard census request is back');
  const slice = Number((src.match(/const CENSUS_SLICE = (\d+)/) || [])[1]);
  assert.ok(slice > 0 && slice <= 100000, `CENSUS_SLICE ${slice}: the 524 came from a request outliving the ~100 s gateway`);
});
