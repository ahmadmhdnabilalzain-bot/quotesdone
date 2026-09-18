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

// EVERY CALLER MUST OUTWAIT THE DEADLINE THE FUNCTION DECLARES.
//
// Measured 17 Sep 2026: the external watchdog had been red for four days over a healthy system. The
// GitHub job ran `curl -m 30`, the Vercel route waited `AbortSignal.timeout(30_000)`, and the function
// declares DEADLINE_MS = 110_000 with sub-timeouts of 55 s inside individual ticks. So neither caller
// could EVER see the answer once one tick ran long: 4/4 workflow failures on 14, 15, 16 and 17 Sep,
// every one `curl: (28) ... 30002 ms`, against 194 successful function runs in the same 48 hours, and
// the Vercel cron log permanently 502. This is the one watchdog that exists because an in-cluster
// check cannot detect a total outage, and a real Supabase outage would have looked identical to it.
//
// The reason it shipped is that nothing compared the three numbers. This does. It reads the deadline
// out of the function and both caller timeouts out of their own files, so raising the deadline without
// raising the callers fails here rather than in four days of silence.
// ONE MATCH, OR THE CHECK DOES NOT KNOW WHICH NUMBER IT READ. `.exec` takes the first hit, so a
// second `curl -m` or a second AbortSignal.timeout — a retry, or a stale value left in a comment
// above the real one — would have this check validate the wrong one and pass over a regression.
const only = (re, text, what) => {
  const all = [...text.matchAll(new RegExp(re, re.flags.includes('g') ? re.flags : re.flags + 'g'))];
  assert.equal(all.length, 1, `expected exactly one ${what}, found ${all.length}`);
  return Number(String(all[0][1]).replace(/_/g, ''));
};

test('both callers wait longer than the deadline the function declares', () => {
  const deadline = only(/const DEADLINE_MS = ([\d_]+)/, src, 'DEADLINE_MS declaration in resilience_ping/index.ts');
  assert.ok(deadline > 0, 'DEADLINE_MS was not found in resilience_ping/index.ts');

  const wf = readFileSync(fileURLToPath(new URL('../../.github/workflows/resilience-ping.yml', import.meta.url)), 'utf8');
  const curlMs = only(/curl [^\n]*-m (\d+)/, wf, 'curl -m timeout in resilience-ping.yml') * 1000;
  assert.ok(curlMs > 0, 'the workflow no longer calls curl with an -m timeout');
  assert.ok(curlMs > deadline,
    `the GitHub watchdog waits ${curlMs} ms for a function that runs to ${deadline} ms; it can never see the answer`);

  const route = readFileSync(fileURLToPath(new URL('../../src/app/api/resilience-ping/route.ts', import.meta.url)), 'utf8');
  const abortMs = only(/AbortSignal\.timeout\(([\d_]+)\)/, route, 'AbortSignal.timeout in the resilience-ping route');
  assert.ok(abortMs > 0, 'the Vercel route no longer sets an AbortSignal timeout');
  assert.ok(abortMs > deadline,
    `the Vercel route waits ${abortMs} ms for a function that runs to ${deadline} ms; its cron log can only ever show 502`);

  // maxDuration is the platform's own kill, and it binds before the fetch timeout does.
  const maxDurMs = only(/export const maxDuration = (\d+)/, route, 'maxDuration export in the resilience-ping route') * 1000;
  assert.ok(maxDurMs > 0, 'the Vercel route declares no maxDuration, so the platform default (well under the deadline) applies');
  assert.ok(maxDurMs >= abortMs,
    `maxDuration is ${maxDurMs} ms but the route waits ${abortMs} ms; the platform kills the route before its own timeout fires`);
});
