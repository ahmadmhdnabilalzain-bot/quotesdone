// deno test --no-lock supabase/functions/resilience_ping/steps.test.ts
import { failureOf, runSteps } from './steps.ts';

const eq = (a: unknown, b: unknown, m: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};

Deno.test('a failed step is one that threw, answered ok:false with an error, or got a 4xx/5xx', () => {
  eq(failureOf({ ok: false, error: 'boom' }), 'boom', 'error');
  eq(failureOf({ status: 401, result: null }), 'HTTP 401', 'the accountant gateway refusal');
  eq(failureOf({ status: 200, ok: false, errors: 2 }), null, 'a seat that staged its own failures is not counted twice');
  eq(failureOf({ due: false }), null, 'not due');
  eq(failureOf(null), null, 'nothing');
  eq(failureOf([{ fn: 'kyc', ok: false }]), null, 'an array is not a step result');
});

Deno.test('one step failing never stops the next, and every failure is named', async () => {
  const ran: string[] = [];
  const { results, failing } = await runSteps([
    { name: 'a', run: () => { ran.push('a'); throw new Error('a broke'); } },
    { name: 'b', run: async () => { ran.push('b'); return { status: 401 }; } },
    { name: 'c', run: async () => { ran.push('c'); return { renewal: { ok: true }, changes: { ok: false, error: 'x' } }; }, nested: true },
    { name: 'd', run: async () => { ran.push('d'); return { due: false }; } },
  ], 0, 1e9, () => 0);
  eq(ran, ['a', 'b', 'c', 'd'], 'all ran');
  eq(failing, [{ name: 'a', error: 'a broke' }, { name: 'b', error: 'HTTP 401' }, { name: 'c.changes', error: 'x' }], 'failures');
  eq(results.d, { due: false }, 'result kept');
});

Deno.test('past the deadline a step is skipped and counted, except the ones that must always run', async () => {
  let clock = 0;
  const { results, failing } = await runSteps([
    { name: 'slow', run: async () => { clock = 200; return {}; } },
    { name: 'late', run: async () => ({ ran: true }) },
    { name: 'outbox', run: async () => ({ flushed: true }), always: true },
  ], 0, 100, () => clock);
  eq(results.late, { skipped: 'deadline' }, 'skipped');
  eq(results.outbox, { flushed: true }, 'always runs');
  eq(failing.map((f) => f.name), ['late'], 'the skip is a failure');
});

// A NESTED STEP THAT FAILS AS A WHOLE IS STILL A FAILURE (18 Sep 2026, it_engineer).
// Found in review of the `orphans` step: the nested branch read only the ENTRIES, so a nested step
// that threw — wrapped as {ok:false, error} by runSteps' own catch — was split into ('ok', false)
// and ('error', '...'), neither readable by failureOf, and the failure disappeared. Same for a
// nested step that returns {ok:false, error} because its gate RPC failed before it had any
// sub-results. Both shapes are what a broken step actually looks like.
Deno.test('a nested step that threw, or failed before it had sub-results, is still named', async () => {
  const { failing } = await runSteps([
    { name: 'threw', run: () => { throw new Error('gate exploded'); }, nested: true },
    { name: 'gate', run: async () => ({ ok: false, error: 'rpc refused' }), nested: true },
    { name: 'partial', run: async () => ({ email_cron: { status: 500 }, wa: { status: 200 } }), nested: true },
  ], 0, 1e9, () => 0);
  eq(failing, [
    { name: 'threw', error: 'gate exploded' },
    { name: 'gate', error: 'rpc refused' },
    { name: 'partial.email_cron', error: 'HTTP 500' },
  ], 'each failure is named once, at the level it happened');
});

// 22 Sep 2026: backupVerify recorded "dropbox_backup reconcile answered HTTP 500" for two days while
// dropbox_backup's reply carried the cause. Replays that exact reply: the step's error must carry it.
import { httpHopError } from './steps.ts';
Deno.test('backupVerify records the error the reconcile answered with, not only its HTTP status', () => {
  const reply = { ok: false, mode: 'reconcile', error: 'apply canceling statement due to statement timeout' };
  const e = httpHopError('dropbox_backup reconcile', 500, reply);
  eq(e, 'dropbox_backup reconcile answered HTTP 500: apply canceling statement due to statement timeout', 'the cause is in the row');
  eq(failureOf({ ok: false, error: e }), e, 'and the step fails with it');
  eq(httpHopError('dropbox_backup reconcile', 502, null), 'dropbox_backup reconcile answered HTTP 502', 'a body that is not JSON still names the status');
});

// 21 Sep 2026: duty:heartbeat:backupVerify was closed 15 minutes after each failure because the step
// (every 6 h) was not due on the next tick. Replays that state: it must stay failing until it passes.
import { carriedFailures } from './steps.ts';
Deno.test('a failed step that was not due this tick is still failing, until a run passes', () => {
  const state = [
    { step: 'backupVerify', last_started_at: '2026-09-21T17:16:11Z', last_ok_at: '2026-09-20T03:31:10Z' },
    { step: 'outbox', last_started_at: '2026-09-21T17:31:00Z', last_ok_at: '2026-09-21T17:31:00Z' },
    { step: 'weekly', last_started_at: '2026-09-21T15:00:00Z', last_ok_at: null },
    { step: 'never', last_started_at: null, last_ok_at: null },
  ];
  const c = carriedFailures(state, { outbox: 900 }, []);
  eq(c.map((f) => f.name), ['backupVerify', 'weekly'], 'the two whose last attempt failed');
  eq(c.every((f) => f.carried === true), true, 'marked carried');
  eq(carriedFailures(state, { backupVerify: 9000 }, []).map((f) => f.name), ['weekly'], 'a step that ran this tick is judged by this tick');
  eq(carriedFailures(state, {}, [{ name: 'weekly.x', error: 'e' }]).map((f) => f.name), ['backupVerify'], 'not named twice');
  eq(carriedFailures([{ step: 'backupVerify', last_started_at: '2026-09-21T23:16:00Z', last_ok_at: '2026-09-21T23:16:00Z' }], {}, []), [], 'closes once a run passes');
});

import { ALWAYS_FLOOR_POOL_MS, stepCapMs } from './steps.ts';

// CONN-02 (22 Sep 2026, it_engineer). The deadline used to be read ONCE, before a step started, so a step
// admitted at 109.9 s could then wait its own 55 s timeout on top and the tick returned at up to ~165 s
// against a 150 s platform cap. These two tests pin the arithmetic and the abandonment.
Deno.test('the cap is what is left of the deadline plus the reserve, with a shared floor for always steps', () => {
  eq(stepCapMs(109_000, 95_000, false), 11_000, 'a step starting at 109s of a 95s deadline gets 11s of the 120s ceiling');
  eq(stepCapMs(10_000, 95_000, false), 110_000, 'an early step is bounded by the ceiling, not by nothing');
  eq(stepCapMs(140_000, 95_000, false), -20_000, 'past the ceiling a normal step gets nothing (raceCap floors it at 0)');
  eq(stepCapMs(140_000, 95_000, true), ALWAYS_FLOOR_POOL_MS, 'a mail drain past the ceiling still gets the floor, never unbounded');
  // THE POOL IS SHARED. Three always steps each granted the full floor would put the worst tick at
  // 95 + 25 + 10 + 10 + 10 = 150 s, the platform cap exactly.
  eq(stepCapMs(140_000, 95_000, true, 25_000, 4_000), 4_000, 'the second drain gets only what the first left');
  eq(stepCapMs(140_000, 95_000, true, 25_000, 0), 0, 'the third drain gets nothing once the pool is spent');
});

Deno.test('three always steps past the ceiling share one floor, they do not each get one', async () => {
  // Scaled by 1000 so the test costs milliseconds, not the real 10 s pool: deadline 100 ms, reserve
  // 20 ms (a 120 ms ceiling), pool 200 ms. All three start already past the ceiling and never resolve,
  // so each is in floor territory and the pool is the only thing bounding them.
  const hang = (name: string) => ({ name, always: true, run: () => new Promise<never>(() => {}) });
  const t0 = Date.now() - 200;
  const began = Date.now();
  const { failing } = await runSteps([hang('it'), hang('outbox'), hang('archive')], t0, 100, Date.now, 20, 200);
  const waited = Date.now() - began;
  eq(failing.length, 3, 'all three are named as abandoned, none is silently skipped');
  // The three together cannot exceed the pool. Per-step floors would make this about 3x 200 ms; the
  // bar is 600 ms so scheduling noise cannot decide the verdict but a per-step grant still fails it.
  if (waited > 600) throw new Error('three always steps waited ' + waited + 'ms against a shared 200ms floor');
  if (ALWAYS_FLOOR_POOL_MS !== 10_000) throw new Error('the real pool moved without its comment: ' + ALWAYS_FLOOR_POOL_MS);
});

Deno.test('a never-resolving step started past the deadline is abandoned, not waited on', async () => {
  // Real time, scaled down by 1000: deadline 200 ms, reserve 100 ms, started at 190 ms => a 110 ms cap.
  // The step never resolves, so if the cap did not fire this test would hang instead of failing. At the
  // real numbers this is a step admitted at 109 s being abandoned by 120 s, well inside the 125 s bar.
  const t0 = Date.now() - 190;
  const began = Date.now();
  const { failing, results } = await runSteps(
    [{ name: 'hangs', run: () => new Promise<never>(() => {}) }], t0, 200, Date.now, 100);
  const waited = Date.now() - began;
  if (waited > 800) throw new Error('waited ' + waited + 'ms: the step was not abandoned at its cap');
  eq(failing.length, 1, 'the abandoned step is a failure, not a silent pass');
  if (!String(failing[0].error).includes('abandoned')) throw new Error('unexpected error text: ' + failing[0].error);
  eq((results.hangs as { ok?: boolean })?.ok, false, 'the result records the abandonment');
});
