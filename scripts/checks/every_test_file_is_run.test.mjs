// 4 AUG 2026. supabase/functions/_shared/attachment.test.ts sat in the repository for a month and
// never executed: run.mjs globbed `*.test.mjs` in one directory, and no workflow ever called
// `deno test`. The file was not failing. It was not passing. It was invisible, and the honest
// answer to "did the audit 9.1 sanitiser tests pass?" was "they never ran".
//
// This asserts the property that would have caught it: every file in this repository that a reader
// would call a test is claimed by a runner run.mjs actually invokes. It imports the real discovery
// function rather than re-implementing its patterns - a guard that restates its subject proves
// only that somebody typed the same thing twice.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { discover, NODE_TEST } from './run.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

test('every file that looks like a test is claimed by a runner', () => {
  const { node, deno, looksLikeATest } = discover();
  const claimed = new Set([...node, ...deno]);
  const orphans = looksLikeATest.filter((f) => !claimed.has(f));
  assert.deepEqual(
    orphans,
    [],
    'these files look like tests but no runner in run.mjs would execute them:\n  '
      + orphans.join('\n  ')
      + '\nGive their extension a runner in run.mjs, or rename them so they stop claiming to be tests.',
  );
});

test('the deno suite is discovered, not merely present on disk', () => {
  const { deno } = discover();
  assert.ok(
    deno.includes('supabase/functions/_shared/attachment.test.ts'),
    'attachment.test.ts is the audit 9.1 sanitiser suite and must be in the deno set. '
      + 'Discovery returned: ' + JSON.stringify(deno),
  );
});

test('every node check in scripts/checks is discovered', () => {
  const { node } = discover();
  const onDisk = fs.readdirSync(HERE).filter((f) => NODE_TEST.test(f)).sort();
  const missed = onDisk.filter((f) => !node.includes('scripts/checks/' + f));
  assert.deepEqual(missed, [], 'discovery walked past these: ' + missed.join(', '));
});
