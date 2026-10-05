// THE CHECK RUNNER NEVER PASSES WITHOUT RUNNING (it_engineer, 5 Oct 2026). On Windows, run.mjs spawned every test
// file in one command, hit "The command line is too long", and reported SUCCESS having run nothing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { batches, ranStatus } from './run.mjs';

test('file lists are split under the command-line limit, and nothing is lost', () => {
  const files = Array.from({ length: 900 }, (_, i) => `C:/Users/x/quotesdone/scripts/checks/a_long_check_name_${i}.test.mjs`);
  const b = batches(files);
  assert.ok(b.length > 1);
  for (const x of b) assert.ok(x.join(' ').length < 8191, 'a batch is over the Windows limit');
  assert.deepEqual(b.flat(), files);
});

test('a spawn error or a missing status is a failure, never a pass', () => {
  assert.equal(ranStatus({ error: new Error('spawn E2BIG'), status: null }, 'x'), 1);
  assert.equal(ranStatus({ status: null, signal: 'SIGKILL' }, 'x'), 1);
  assert.equal(ranStatus({ status: 0 }, 'x'), 0);
  assert.equal(ranStatus({ status: 3 }, 'x'), 3);
});
