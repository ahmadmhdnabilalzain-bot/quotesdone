// RESILIENCE_PING REPORTS EVERY TICK IT RUNS.
//
// resilience_ping is the heartbeat several seats hang their work on (the accountant's duties, the IT
// engineer's, the outbox). Three builds edited it on 14 Sep 2026 (#638, #641, #645), and a tick that
// runs but is dropped from the healthy result is a tick nobody can see fail. Every `const x = await
// someTick()` inside the handler must appear as a key of the healthy result object.
//
//   node --test scripts/checks/resilience_ping_reports_every_tick.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(fileURLToPath(new URL('../../supabase/functions/resilience_ping/index.ts', import.meta.url)), 'utf8');

test('every tick the handler runs is a key of the healthy result', () => {
  const handler = src.slice(src.indexOf('Deno.serve('));
  const ticks = [...handler.matchAll(/const (\w+) = await \w+Tick\(\);/g)].map((m) => m[1]);
  assert.ok(ticks.length >= 10, `only ${ticks.length} ticks found; the pattern no longer matches the handler`);
  const healthy = handler.match(/if \(healthy\) return J\(\{([^}]*)\}\)/);
  assert.ok(healthy, 'the healthy return was not found');
  const keys = new Set(healthy[1].split(',').map((k) => k.trim().split(':')[0].trim()).filter(Boolean));
  const missing = ticks.filter((t) => !keys.has(t));
  assert.deepEqual(missing, [], 'ticks run but not reported in the healthy result');
});

test('the accountant\'s duties tick is run and reported', () => {
  assert.match(src, /const accountantDuties = await accountantDutiesTick\(\);/);
});
