// THE ROUTINE JUDGEMENTS KEEP THEIR CALLER'S DEADLINE (it_engineer, 27 Oct 2026).
// Measured on production: the detached itlater run of 22:01:12Z claimed five supplier_trade_words rows at 22:01:27 and
// judged them one after another at ~60 s each (two model calls of 19-31 s, ai_cost_log); its 120 s cap fired at 22:03:12
// with the drain still going, and rows 334 and 346 were never settled. With a deadline, the drain claims one row at a
// time (JUDGE_CLAIM = 1: beside heldReplay's two, more concurrent calls failed every one at 20:30Z and 21:31Z, review of
// #1693), starts a claim only while a whole row still fits before deadline - JUDGE_RESERVE_MS, and never lets a model
// call run past that line. Without one it is unchanged.
//   deno test --no-lock supabase/functions/_shared/routine_judgements_keep_a_deadline.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { drain, JUDGE_CLAIM, JUDGE_RESERVE_MS, JUDGE_ROW_MS, type Row } from './routine_judgements.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'read what was given', needs_knowledge: false }], facts: [] });
const row = (id: number): Row => ({ id, kind: 'repeat_request', subject_key: 'k' + id, input: { a: 'pipe 2 inch', b: 'pipe 50 mm' }, attempts: 0 });

/** A queue of `n` rows, a model that takes `callMs` of a fake clock per call, and a record of every claim and call. */
function harness(n: number, callMs: number) {
  let t = 0;
  const now = () => t;
  const queue = Array.from({ length: n }, (_, i) => row(i + 1));
  const claims: number[] = [];
  const calls: { at: number; timeoutMs?: number }[] = [];
  let inFlight = 0, maxInFlight = 0;
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true, rule: 'ok' } as unknown as GateAnswer),
    llm: async (phase: Phase, _s, _i, o) => {
      calls.push({ at: t, timeoutMs: o.timeoutMs });
      inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((r) => setTimeout(r, 0));
      t += callMs / Math.max(1, inFlight);            // calls in flight together share the clock, as concurrent calls do
      inFlight--;
      return { content: phase === 'decompose' ? PLAN : 'same: yes', model: 'openai/gpt-6-luna' } as LlmReply;
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      if (fn === 'fn_routine_judgement_due') {
        const k = Number((args as { p_limit: number }).p_limit);
        claims.push(k);
        return Promise.resolve({ data: queue.splice(0, k), error: null });
      }
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { deps, now, claims, calls, left: () => queue.length, maxInFlight: () => maxInFlight, advance: (ms: number) => { t += ms; } };
}

Deno.test('with a deadline: one row a claim, one judgement in flight, and no claim without a whole row of time', async () => {
  const h = harness(5, 30_000);
  const deadline = 120_000;                            // the detached run's DETACHED_MS, started at t = 0
  await drain(h.deps, 5, null, { deadline, now: h.now });
  assertEquals(JUDGE_CLAIM, 1, 'a claim of more than one row puts more think() calls beside the replay\'s two');
  assert(h.claims.length > 0 && h.claims.every((k) => k === 1), `a claim asked for more than one row: ${h.claims}`);
  assertEquals(h.maxInFlight(), 1, 'more than one judgement was in flight at once');
  // every model call started before the line, and none was allowed to run past it
  const line = deadline - JUDGE_RESERVE_MS;
  for (const c of h.calls) {
    assert(c.at < line, `a model call started at ${c.at} ms, past the line ${line}`);
    assert(c.timeoutMs !== undefined && c.at + c.timeoutMs <= line, `a model call could run to ${c.at + (c.timeoutMs ?? Infinity)} ms`);
  }
  assert(h.left() > 0, 'all five rows were taken in one 120 s run - the clock in this test is not binding');
});

Deno.test('with a deadline already too close for one row: nothing is claimed, and the drain says why', async () => {
  const h = harness(5, 30_000);
  h.advance(120_000 - JUDGE_RESERVE_MS - JUDGE_ROW_MS + 1);
  const out = await drain(h.deps, 5, null, { deadline: 120_000, now: h.now });
  assertEquals(h.claims, [], 'a row was claimed (and a try counted) with too little time to judge it');
  assert(out.deferred && /under one judgement/.test(out.deferred), 'the drain did not say why it took nothing');
});

Deno.test('without a deadline the drain is unchanged: one claim of `limit`, rows judged in turn', async () => {
  const h = harness(5, 30_000);
  const out = await drain(h.deps, 5);
  assertEquals(h.claims, [5]);
  assertEquals(h.maxInFlight(), 1);
  assertEquals(out.done + out.held + out.failed_reading, 5);
  assertEquals(out.deferred, undefined);
});
