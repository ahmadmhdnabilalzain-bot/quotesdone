import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { functionFiles, functionSource, REPO } from './function_sources.mjs';

test('index.ts comes first and tests, checks and fixtures are left out', () => {
  const files = functionFiles('supplier_api');
  assert.equal(files[0], 'supabase/functions/supplier_api/index.ts');
  assert.ok(files.every((f) => !/\.(test|check)\.ts$/.test(f) && !f.includes('/fixtures/')), files.join('\n'));
});

test('the source contains every runtime file byte for byte', () => {
  const src = functionSource('customer_api');
  for (const f of functionFiles('customer_api')) assert.ok(src.includes(readFileSync(join(REPO, f), 'utf8')), f);
});

test('a function that does not exist is an error, never an empty string', () => {
  assert.throws(() => functionSource('no_such_function'), /does not exist/);
});
