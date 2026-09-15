// RESILIENCE_PING RUNS AND REPORTS EVERY TICK IT DEFINES.
//
// resilience_ping is the heartbeat several seats hang their work on (the accountant's duties, the IT
// engineer's, the outbox). Three builds edited it on 14 Sep 2026 (#638, #641, #645), and a tick that
// runs but is dropped from the result is a tick nobody can see fail.
//
// 15 Sep 2026: the handler runs its ticks from ONE ordered STEPS list and returns every step's result
// by name (steps.ts runSteps), so a run tick cannot be left out of the result any more. What can still
// go wrong is a tick that is DEFINED and never listed, so that is what this asserts, plus that both
// returns carry the results and the failures.
//
//   node --test scripts/checks/resilience_ping_reports_every_tick.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(fileURLToPath(new URL('../../supabase/functions/resilience_ping/index.ts', import.meta.url)), 'utf8');

test('every tick the file defines is a step the handler runs', () => {
  const defined = [...src.matchAll(/async function (\w+Tick)\(/g)].map((m) => m[1]);
  assert.ok(defined.length >= 10, `only ${defined.length} ticks found; the pattern no longer matches the file`);
  const list = src.slice(src.indexOf('const STEPS'), src.indexOf('Deno.serve('));
  assert.ok(list.length > 0, 'the STEPS list was not found before the handler');
  const listed = new Set([...list.matchAll(/run: (\w+Tick)\b/g)].map((m) => m[1]));
  const missing = defined.filter((t) => !listed.has(t));
  assert.deepEqual(missing, [], 'ticks defined but never run');
});

test('both returns carry every step result and the failures', () => {
  const handler = src.slice(src.indexOf('Deno.serve('));
  const returns = [...handler.matchAll(/return J\(\{ ok: true, healthy: (true|false)[^\n]*/g)].map((m) => m[0]);
  assert.equal(returns.length, 2, 'the healthy and unhealthy returns were not both found');
  for (const r of returns) assert.match(r, /\.\.\.results/, 'a return drops the step results');
  for (const r of returns) assert.match(r, /failing/, 'a return drops the failing steps');
});

test('the accountant\'s duties tick is run and reported', () => {
  assert.match(src, /name: 'accountantDuties', run: accountantDutiesTick/);
});
