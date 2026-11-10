import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { functionFiles, functionModuleFiles, functionModuleSource, functionSource, REPO, sharedModuleFiles, sharedModuleSource } from './function_sources.mjs';

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

test('a shared module that is still one file reads as that file alone', () => {
  assert.deepEqual(sharedModuleFiles('money'), ['supabase/functions/_shared/money.ts']);
});

test('the quote documents module reads as its barrel first, then its folder', () => {
  const files = sharedModuleFiles('quote_documents');
  assert.equal(files[0], 'supabase/functions/_shared/quote_documents.ts');
  assert.ok(files.length > 1, 'the folder _shared/quote_documents/ is part of the module');
  assert.ok(files.slice(1).every((f) => f.startsWith('supabase/functions/_shared/quote_documents/') && !/\.(test|check)\.ts$/.test(f)), files.join('\n'));
});

test('a split module reads its barrel first, then the folder in path order, and leaves tests out', () => {
  const files = functionModuleFiles('marketing/duties');
  assert.equal(files[0], 'supabase/functions/marketing/duties.ts');
  assert.ok(files.length > 1 && files.slice(1).every((f) => f.startsWith('supabase/functions/marketing/duties/') && !/\.(test|check)\.ts$/.test(f)), files.join('\n'));
  assert.deepEqual(files.slice(1), [...files.slice(1)].sort());
  const src = functionModuleSource('marketing/duties');
  for (const f of files) assert.ok(src.includes(readFileSync(join(REPO, f), 'utf8')), f);
});

test('a shared module is its barrel plus _shared/<name>/', () => {
  const files = sharedModuleFiles('document_expiry');
  assert.equal(files[0], 'supabase/functions/_shared/document_expiry.ts');
  assert.ok(files.slice(1).every((f) => f.startsWith('supabase/functions/_shared/document_expiry/')), files.join('\n'));
  assert.ok(sharedModuleSource('document_expiry').includes(readFileSync(join(REPO, files[0]), 'utf8')));
  assert.throws(() => sharedModuleSource('no_such_module'), /does not exist/);
});
