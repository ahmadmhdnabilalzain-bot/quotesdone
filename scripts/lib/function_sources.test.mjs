import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { functionFiles, functionSource, sharedModuleFiles, sharedModuleSource, REPO } from './function_sources.mjs';

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

test('a split shared module reads as its barrel first, then every runtime file of its folder, byte for byte', () => {
  const files = sharedModuleFiles('think');
  assert.equal(files[0], 'supabase/functions/_shared/think.ts');
  assert.ok(files.length > 1 && files.slice(1).every((f) => f.startsWith('supabase/functions/_shared/think/') && !/\.(test|check)\.ts$/.test(f)), files.join('\n'));
  assert.deepEqual(files.slice(1), [...files.slice(1)].sort());
  const src = sharedModuleSource('think');
  for (const f of files) assert.ok(src.includes(readFileSync(join(REPO, f), 'utf8')), f);
  assert.ok(src.indexOf(readFileSync(join(REPO, files[0]), 'utf8')) === 0, 'the barrel comes first');
});

test('a shared module that does not exist is an error, never an empty string', () => {
  assert.throws(() => sharedModuleSource('no_such_module'), /does not exist/);
});
