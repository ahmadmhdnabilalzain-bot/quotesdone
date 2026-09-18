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
