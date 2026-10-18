// THE TEST RUNNER FAILS WHEN A BATCH CANNOT START (5 Oct 2026, it_engineer).
//
// MEASURED: on Windows `node scripts/checks/run.mjs` handed every test path to one spawn, Windows answered
// "The command line is too long", and the run exited 0 without executing a test.
//
// WHAT FAILS IF THE CAUSE RETURNS: a spawn error, a null status or a non-zero batch reported as 0; a batch
// longer than the ceiling; a file dropped or duplicated between batches.
//
//   node --test scripts/checks/run_fails_when_a_batch_cannot_start.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { batches, runBatched, MAX_ARGS_CHARS } from './run.mjs';

const files = Array.from({ length: 400 }, (_, i) => `C:/repo/scripts/checks/some_long_test_file_name_${i}.test.mjs`);

test('batches stay under the ceiling and keep every file exactly once, in order', () => {
  const b = batches(files);
  assert.ok(b.length > 1);
  for (const x of b) assert.ok(x.join(' ').length <= MAX_ARGS_CHARS);
  assert.deepEqual(b.flat(), files);
});

test('a spawn error fails the run', () => {
  const tooLong = () => ({ status: null, error: Object.assign(new Error('The command line is too long'), { code: 'E2BIG' }) });
  assert.notEqual(runBatched('node', ['--test'], files, {}, tooLong), 0);
});

test('a missing command is 127, a null status or one failed batch fails, all green is 0', () => {
  assert.equal(runBatched('deno', [], files, {}, () => ({ status: null, error: Object.assign(new Error('x'), { code: 'ENOENT' }) })), 127);
  assert.notEqual(runBatched('node', [], files, {}, () => ({ status: null })), 0);
  let n = 0;
  assert.equal(runBatched('node', [], files, {}, () => ({ status: n++ === 1 ? 3 : 0 })), 3);
  const seen = [];
  assert.equal(runBatched('node', ['--test'], files, {}, (_c, a) => { seen.push(...a.slice(1)); return { status: 0 }; }), 0);
  assert.deepEqual(seen, files);
});
