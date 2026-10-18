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
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(fileURLToPath(new URL('../../supabase/functions/resilience_ping/index.ts', import.meta.url)), 'utf8');

// 18 SEP 2026 — THE ORDER MOVED INTO POSTGRES, SO REACHABILITY GAINED A SECOND HALF.
// The handler no longer walks a fixed `STEPS` array; it runs the order fn_resilience_tick_plan returns,
// and STEP_RUN is a map of name -> runner. A tick is therefore reachable only if it is BOTH declared in
// STEP_RUN and named by a row in public.resilience_step — a step the schedule does not name is never
// planned, so it is dead in a way the old single-list check could not have expressed. Both halves are
// asserted here, statically (the seed file), so this runs in a CI job with no database token;
// scripts/checks/every_tick_step_is_scheduled.mjs asserts the same thing against the LIVE table.
//
// Verified before re-anchoring, so this is a moved anchor and not a softened assertion: 25 ticks
// defined, 25 listed in STEP_RUN, 0 missing, and the live table holds the same 25 rows.
// 21 Sep 2026 (sales_engineer): a step's row may be seeded by the file that builds the step, as
// supplierOutreach is (the_invitations_go_out_every_day_and_a_started_registration_is_followed.sql), so the
// seed is every scripts/sql file that inserts into public.resilience_step — the same rows, read from where
// they are written. every_tick_step_is_scheduled.mjs still checks the live table.
const SQL_DIR = fileURLToPath(new URL('../../scripts/sql/', import.meta.url));
const SEED = readdirSync(SQL_DIR).filter((f) => f.endsWith('.sql'))
  .map((f) => readFileSync(SQL_DIR + f, 'utf8'))
  .filter((s) => s.includes('insert into public.resilience_step'))
  .join('\n');
const stepRun = () => {
  const open = src.indexOf("const STEP_RUN: Record<string, Omit<Step, 'name'>> = {");
  assert.ok(open > 0, 'the STEP_RUN map was not found in resilience_ping/index.ts');
  const close = src.indexOf('\n};', open);
  assert.ok(close > open, 'the STEP_RUN map has no closing brace');
  return src.slice(open, close);
};

test('every tick the file defines is a step the handler runs', () => {
  const defined = [...src.matchAll(/async function (\w+Tick)\(/g)].map((m) => m[1]);
  assert.ok(defined.length >= 10, `only ${defined.length} ticks found; the pattern no longer matches the file`);
  // A slow step is KICKED from STEP_RUN and run from the DETACHED map in its own invocation (12 Oct 2026),
  // so a tick named there is run too; the map is the one place, its kick is STEP_RUN's `kickDetached('<name>')`.
  const dOpen = src.indexOf('const DETACHED: Record<');
  const detached = dOpen > 0 ? src.slice(dOpen, src.indexOf('\n};', dOpen)) : '';
  const listed = new Set([...(stepRun() + detached).matchAll(/run: (\w+Tick)\b/g)].map((m) => m[1]));
  for (const [, k] of detached.matchAll(/^ {2}(\w+): \{ run:/gm)) {
    assert.ok(stepRun().includes(`kickDetached('${k}')`), `detached step ${k} is never kicked from STEP_RUN`);
  }
  assert.deepEqual(defined.filter((t) => !listed.has(t)), [], 'ticks defined but never run');
});

test('every step the handler declares is one the schedule can plan', () => {
  const keys = [...stepRun().matchAll(/^ {2}(\w+): \{\s*run:/gm)].map((m) => m[1]);
  assert.ok(keys.length >= 10, `only ${keys.length} steps found in STEP_RUN; the pattern no longer matches`);
  const unscheduled = keys.filter((k) => !new RegExp("\\('" + k + "',\\s+interval").test(SEED));
  assert.deepEqual(unscheduled, [], 'steps the handler can run that public.resilience_step never names');
  // and the other way: a row for a step the code does not have fails every tick, for ever
  const seeded = [...SEED.matchAll(/^ {2}\('(\w+)',\s+interval/gm)].map((m) => m[1]);
  assert.deepEqual(seeded.filter((s) => !keys.includes(s)), [], 'the schedule names steps the handler does not have');
});

test('both returns carry every step result and the failures', () => {
  const handler = src.slice(src.indexOf('Deno.serve('));
  const returns = [...handler.matchAll(/return J\(\{ ok: true, healthy: (true|false)[^\n]*/g)].map((m) => m[0]);
  assert.equal(returns.length, 2, 'the healthy and unhealthy returns were not both found');
  for (const r of returns) assert.match(r, /\.\.\.results/, 'a return drops the step results');
  for (const r of returns) assert.match(r, /failing/, 'a return drops the failing steps');
});

// The property has not changed — the accountant's duty pass must be wired into the heartbeat and must
// come back in the response — only the shape it is written in. It is now a STEP_RUN entry plus a row in
// the schedule, and both are asserted rather than the one literal the old list happened to spell.
test('the accountant\'s duties tick is run and reported', () => {
  assert.match(stepRun(), /accountantDuties: \{ run: accountantDutiesTick \}/, 'accountantDutiesTick is not a step');
  assert.match(SEED, /\('accountantDuties',\s+interval/, 'the schedule never names accountantDuties, so it is never planned');
});

// 18 Sep 2026 — THE ORPHAN STEP'S TWO WAYS OF LOSING A FAILURE, both found in independent review
// before they shipped. `orphans` is a `nested` step, so steps.ts asks failureOf about each ENTRY, and
// failureOf reads only `ok`/`error`/`status` at the TOP of that entry. Two shapes defeat it:
//   * a deferral written as a plain note — the budget runs out, the entry has no `ok` and no
//     `status`, and `sanctions` (last in the priority list, and the one compliance obligation there)
//     could be starved every tick for ever in silence. That is outbox starvation (#691) one level down.
//   * a callee answering HTTP 200 with {ok:false, error:'…'} — which is how all of these report a
//     refusal — recorded as {status:200, body:{…}}, where failureOf cannot see it. That is
//     quote_compare's {ok:false} at HTTP 200, the estate's oldest instance of this bug.
// Both are asserted at the source, because the alternative is importing a module that needs a live
// Deno runtime and service-role environment variables.
test('a deferred orphan job is shaped as a failure failureOf can read', () => {
  const tick = src.slice(src.indexOf('async function orphanTick'), src.indexOf('async function tableExportTick'));
  assert.ok(tick.length > 0, 'orphanTick was not found before tableExportTick');
  // NOT a doesNotMatch on the old shape: this file's own comment above names it, and a check that
  // greps source matches its own prose (apply-discipline, 9 Sep 2026). The positive assertion is the
  // one that has teeth — replace the shape and it fails.
  assert.match(tick, /ok: false, error: 'deferred/, 'a deferred job does not report {ok:false, error:...}');
  // and it must not start a job it cannot afford to finish, or the budget is decoration
  assert.match(tick, /left\(\) < need/, 'the budget check does not account for the job about to run');
});

test('the orphan step lifts a body-level failure out of an HTTP 200', () => {
  const tick = src.slice(src.indexOf('async function orphanTick'), src.indexOf('async function tableExportTick'));
  assert.match(tick, /const inner = r\.status < 400 \? failureOf\(b\) : null/, 'call() no longer inspects the response body');
  assert.match(tick, /inner\s*\n?\s*\?\s*\{ ok: false, error:/, 'a failed body is not lifted to the top of the entry');
  assert.match(src, /import \{[^}]*failureOf[^}]*\} from '\.\/steps\.ts'/, 'failureOf is not imported');
});

// EVERY CALLER MUST OUTWAIT THE DEADLINE THE FUNCTION DECLARES.
//
// Measured 17 Sep 2026: the external watchdog had been red for four days over a healthy system. The
// GitHub job ran `curl -m 30`, the Vercel route waited `AbortSignal.timeout(30_000)`, and the function
// declared DEADLINE_MS = 110_000 with sub-timeouts of 55 s inside individual ticks. So neither caller
// (110_000 is what it said on 17 Sep; it is 95_000 since 22 Sep 2026, CONN-02, where runSteps also
// gained a ceiling on how long a step may still be WAITED on. The check below reads the live number
// out of the file, so it needs no edit when that changes — this sentence is the measurement's date.)
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
