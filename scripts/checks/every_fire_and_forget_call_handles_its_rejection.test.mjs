// EVERY FIRE-AND-FORGET CALL HANDLES ITS REJECTION (10 Nov 2026, it_engineer, founder ledger 1605).
//
// WHY. Deno treats an unhandled promise rejection as fatal unless an 'unhandledrejection' listener prevents it, and no
// edge function here registers one (grep, 10 Nov 2026: 0). A call that is neither awaited nor given a .catch/.then
// therefore turns a failed log write or a refused internal POST into a dead isolate, and every request that isolate
// was serving fails with it. An awaited call is handled by the caller's try or by the platform's 500.
//
// MEASURED 10 Nov 2026. Statement-level calls with no await in supabase/functions (not tests): 3, all deliberate and
// all handled: customer_api/actions/inquiry_create.ts and customer_api/index.ts (the compliance_archive repair POST,
// .catch) and site_assistant/index.ts (the readability log, .then(ok, err)). So this asserts what is true today and
// holds it: 0 unhandled.
//
// WHAT IT MATCHES. A statement that STARTS with fetch(, timedFetch(, safeFetch(, admin.rpc(, admin.from(,
// supabase.rpc( or supabase.from( (optionally after `void`), is not a continuation of the line above (an array
// element, an argument, an assignment, an arrow body, a return or an await), and carries neither .catch( nor .then(
// before the statement ends (a line ending in `;`, at most 8 lines on).
//
// LIMIT, stated: a text scan. A promise kept in a variable and dropped, or a floating call written mid-line, is not
// seen. It is a floor, not a type-aware no-floating-promises rule (deno lint has none that needs no type information).
//
//   node --test scripts/checks/every_fire_and_forget_call_handles_its_rejection.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = join(import.meta.dirname, '..', '..');
const FN = join(ROOT, 'supabase', 'functions');
const walk = (d) => readdirSync(d).flatMap((e) => {
  const p = join(d, e);
  return statSync(p).isDirectory() ? walk(p) : (/\.ts$/.test(e) && !/\.(test|check)\.ts$/.test(e) ? [p] : []);
});

const START = /^\s*(void\s+)?(fetch|timedFetch|safeFetch|admin\.(rpc|from)|supabase\.(rpc|from))\(/;
const CONTINUES = /[[,(=?:&|]$|=>$|\breturn$|\bawait$/;

/** Statement-level calls in `src` that are not awaited and handle no rejection. */
export function unhandledFloating(src) {
  const L = src.split('\n'); const hits = [];
  for (let i = 0; i < L.length; i++) {
    if (!START.test(L[i])) continue;
    let j = i - 1; while (j >= 0 && (/^\s*$/.test(L[j]) || /^\s*\/\//.test(L[j]))) j--;
    if (j >= 0 && CONTINUES.test(L[j].trimEnd())) continue;
    let stmt = ''; for (let k = i; k < Math.min(L.length, i + 9); k++) { stmt += L[k] + '\n'; if (/;\s*(\/\/.*)?$/.test(L[k])) break; }
    if (!/\.(catch|then)\(/.test(stmt)) hits.push({ line: i + 1, text: L[i].trim().slice(0, 140) });
  }
  return hits;
}

test('the scanner flags a floating call and passes a handled, awaited or nested one', () => {
  assert.equal(unhandledFloating("  fetch(url, { method: 'POST' });").length, 1);
  assert.equal(unhandledFloating("  void admin.rpc('fn_x', {});").length, 1);
  assert.equal(unhandledFloating("  admin.rpc('fn_x', {\n    p: 1 });").length, 1);
  assert.equal(unhandledFloating("  fetch(url).catch(() => {});").length, 0);
  assert.equal(unhandledFloating("  admin.rpc('fn_x', {\n    p: 1 })\n    .then(() => {}, () => {});").length, 0);
  assert.equal(unhandledFloating("  await fetch(url);").length, 0);
  assert.equal(unhandledFloating("  const [a, b] = await Promise.all([\n    admin.from('t').select('id'),\n    admin.rpc('fn_y'),\n  ]);").length, 0);
});

test('no edge function leaves a fire-and-forget call without a rejection handler', () => {
  const found = walk(FN).flatMap((f) => unhandledFloating(readFileSync(f, 'utf8'))
    .map((h) => `${relative(ROOT, f).replace(/\\/g, '/')}:${h.line}  ${h.text}`));
  assert.deepEqual(found, [], `await it, or give it .catch(), or hand it to EdgeRuntime.waitUntil with a .catch():\n${found.join('\n')}`);
});
