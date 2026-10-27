// THE HELD REPLAY REASONS AT MOST TWO ROWS AT A TIME (it_engineer, 27 Oct 2026). Measured on production at 20:30Z: the
// tick claimed five held rows and reasoned them under one Promise.all; with every gte-small vector its own embed_ml
// call (#1678) that burst was refused (ai_gateway 503 with no worker, the other fetches threw) and all five came back
// 'model_failed: no reply'. These replay the heartbeat's own call - replayHeld(admin, REPLAY_CLAIM, deps, deliver,
// { maxRows: REPLAY_MAX_ROWS, budgetMs: REPLAY_BUDGET_MS }) - against a queue deeper than one claim, and count how many
// rows are inside think() at once. No network, no env, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { REPLAY_BUDGET_MS, REPLAY_CLAIM, REPLAY_MAX_ROWS, REPLAY_RESERVE_MS, REPLAY_ROW_MS, replayHeld, type LlmReply, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);
const tick = (ms: number) => new Promise((r) => setTimeout(r, ms));

function rig(queued: number, o: { overClaim?: boolean } = {}) {
  let next = 500; let left = queued;
  let inFlight = 0; let peak = 0; const claims: number[] = []; const rows: number[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    // every model call takes a moment, so rows reasoned together overlap the way they do on production
    llm: async (phase): Promise<LlmReply> => {
      inFlight++; peak = Math.max(peak, inFlight);
      await tick(5);
      inFlight--;
      return phase === 'decompose' ? { content: J({ steps: [{ id: 's1', goal: 'g', needs_knowledge: false }], facts: [] }), model: 'm' }
        : { content: J({ answer: 'ZZ DEMO answer.', decision: { choice: 'stop' } }), model: 'm' };
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn, args) => {
      if (fn === 'fn_reason_held_due') {
        const ask = Number(args.p_limit); claims.push(ask);
        // overClaim: a claim that returns more than it was asked for must still not widen the burst
        const n = Math.min(left, o.overClaim ? ask + 3 : ask); left -= n;
        const out = Array.from({ length: n }, () => ({ id: next++, seat: 'ceo', surface: 'ceo.command_intent', created_at: new Date().toISOString(),
          request: { seat: 'ceo', question: 'ZZ DEMO stop?', decision: { name: 'intent', options: [{ id: 'stop', meaning: 'halt' }] } } }));
        rows.push(...out.map((r) => r.id));
        return Promise.resolve({ data: out, error: null });
      }
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      return Promise.resolve({ data: { status: 'applied' }, error: null });
    },
  };
  return { deps, peak: () => peak, claims, rows };
}

Deno.test('the heartbeat\'s replay never has more than two rows in think() at once', async () => {
  const r = rig(6);
  const out = await replayHeld(null, REPLAY_CLAIM, r.deps, undefined, { maxRows: REPLAY_MAX_ROWS, budgetMs: REPLAY_BUDGET_MS }) as { replayed: number };
  assert(out.replayed >= 1, 'it still reasons');
  assert(r.peak() <= 2, `at most two model calls in flight, saw ${r.peak()}`);
  assert(r.claims.every((n) => n <= 2), `no claim asks for more than two rows: ${r.claims}`);
});

Deno.test('a caller that asks for a wide claim is still held to two rows at a time', async () => {
  const r = rig(10);
  await replayHeld(null, 5, r.deps, undefined, { maxRows: 10, budgetMs: 60_000, rowMs: 0 });
  assert(r.peak() <= 2, `saw ${r.peak()}`);
  assert(r.claims.every((n) => n <= 2), `claims ${r.claims}`);
});

Deno.test('a claim that returns more rows than asked does not widen the burst, and drops none of them', async () => {
  const r = rig(10, { overClaim: true });
  const out = await replayHeld(null, 2, r.deps, undefined, { maxRows: 2, budgetMs: 60_000, rowMs: 0 }) as { replayed: number };
  assert(r.peak() <= 2, `saw ${r.peak()}`);
  assertEquals(out.replayed, r.rows.length, 'every claimed row is reasoned: a claim has already counted its try');
});

Deno.test('after the first claim, another starts only while a whole row still fits in the budget', async () => {
  const r = rig(6); let t = 0;
  const now = () => t;
  const deps: ThinkDeps = { ...r.deps, rpc: (fn, args) => { if (fn === 'fn_reason_held_due') t += 40_000; return r.deps.rpc(fn, args); } };
  // budget 90 s, a row 60 s: the first claim (t=40 s) is taken; at t=40 s only 50 s remain, under one row, so no second
  const out = await replayHeld(null, 2, deps, undefined, { maxRows: 20, budgetMs: 90_000, rowMs: 60_000, now }) as { replayed: number };
  assertEquals(r.claims.length, 1);
  assertEquals(out.replayed, 2);
});

Deno.test('no model call of the replay starts past the budget: the row stays held, nothing in flight', async () => {
  const r = rig(2); let t = 0; const calls: string[] = [];
  const deps: ThinkDeps = { ...r.deps,
    llm: (phase, s, i, o) => { calls.push(phase); t += 88_000; return r.deps.llm(phase, s, i, o); } };
  const out = await replayHeld(null, 1, deps, undefined, { maxRows: 1, budgetMs: 90_000, now: () => t }) as { rows: { status: string }[] };
  assertEquals(calls, ['decompose'], 'the synthesis call would have started with 2 s left and was not made');
  assertEquals(out.rows[0].status, 'held');
});

// Review of #1688: the replay runs in its own detached invocation, raced at 120 s. It is handed that run's deadline,
// and its budget is what is left less REPLAY_RESERVE_MS - so a late start claims nothing rather than overrunning.
Deno.test('with a deadline, the budget is what is left of it less the reserve, and a late start claims nothing', async () => {
  const late = rig(4); let t = 0;
  // 120 s run, replay starting 30 s in: 90 - 25 = 65 s left, under one row (90 s) -> nothing claimed, nothing asked
  t = 30_000;
  const out = await replayHeld(null, 2, late.deps, undefined, { maxRows: 20, deadline: 120_000, now: () => t }) as { replayed: number; deferred?: string };
  assertEquals(late.claims.length, 0, 'no row is claimed (a claim would spend one of its three tries)');
  assertEquals(out.replayed, 0);
  assert(out.deferred, 'it says why it waited');
  // the same run starting at once: 120 - 25 = 95 s >= one row -> one claim, and no model call past t0 + 90 s
  const early = rig(4); t = 0;
  // the two rows take 40 s; then 95 - 40 = 55 s is under one row, so the second pair waits for the next tick
  const deps: ThinkDeps = { ...early.deps, rpc: (fn, args) => { if (fn === 'fn_reason_held_resolve') t = 40_000; return early.deps.rpc(fn, args); } };
  await replayHeld(null, 2, deps, undefined, { maxRows: 20, deadline: 120_000, now: () => t });
  assertEquals(early.claims, [2]);
  assert(120_000 - REPLAY_RESERVE_MS >= REPLAY_ROW_MS, 'a fresh detached run has room for one row');
});
