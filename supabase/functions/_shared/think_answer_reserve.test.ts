// THE HELD REPLAY'S ANSWER KEEPS ITS OWN TIME (it_engineer, 10 Nov 2026). Measured on production (llm_attempt, 2-10 Nov):
// 119 of 317 replay answers (internal_judgement on gpt-6-luna-pro, fn resilience_ping) ended 84-88 s after the row's plan
// started, at the 90 s REPLAY_BUDGET_MS, because the plan (~20 s) and the sequential retrieval of 5-6 plan steps (43 s
// median on those rows) had spent the budget and the answer started with what was left. An answered call takes p50
// 22.5 s, p95 34.7 s. These replay that shape on a fake clock: no network, no env, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { MIN_STEP_MS, REPLAY_ANSWER_RESERVE_MS, REPLAY_BUDGET_MS, replayHeld, withDeadline, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);

// ── withDeadline itself ─────────────────────────────────────────────────────────────────────────────────────────
function recorder(t: { now: number }) {
  const calls: { phase: Phase; timeoutMs?: number }[] = [];
  const embeds: string[] = []; const searches: string[] = []; const reads: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase, _s, _i, o) => { calls.push({ phase, timeoutMs: o.timeoutMs }); return Promise.resolve({ content: '{}', model: 'm' }); },
    embed: (x) => { embeds.push(x); return Promise.resolve([0.1]); },
    embedFailure: () => 'embedder said no',
    rpc: () => Promise.resolve({ data: null, error: null }),
    search: (q) => { searches.push(q); return Promise.resolve([{ url: 'https://u.ae', title: 't' }]); },
    read: (u) => { reads.push(u); return Promise.resolve('page'); },
  };
  return { deps, calls, embeds, searches, reads, t };
}

Deno.test('with a reserve, the plan and research end that long before the deadline; the answer keeps the whole deadline', async () => {
  const t = { now: 0 }; const r = recorder(t);
  const d = withDeadline(r.deps, 90_000, MIN_STEP_MS, () => t.now, 40_000);
  await d.llm('decompose', 's', 'i', { taskClass: 'routine_employee_reasoning', seat: 'it_engineer', timeoutMs: 75_000 });
  assertEquals(r.calls[0].timeoutMs, 50_000, 'the planner may run into the answer\'s 40 s');
  t.now = 30_000;
  await d.llm('research', 's', 'i', { taskClass: 'routine_employee_reasoning', seat: 'it_engineer' });
  assertEquals(r.calls[1].timeoutMs, 20_000);
  t.now = 46_000;   // 4 s before the line: under MIN_STEP_MS, so no research call starts
  const late = await d.llm('research', 's', 'i', { taskClass: 'routine_employee_reasoning', seat: 'it_engineer' });
  assertEquals([late.content, r.calls.length], [null, 2]);
  assertMatch(String(late.error), /^turn_deadline: 4000 ms left before the 40000 ms kept for the answer/);
  t.now = 50_000;
  assertEquals(await d.embed('step query', 'gte'), null, 'no embedding starts past the line');
  assertMatch(String(d.embedFailure!('step query', 'gte')), /^turn_deadline/, 'the skipped step says why');
  assertEquals(d.embedFailure!('another', 'gte'), 'embedder said no', 'an embedder failure is still the embedder\'s own reason');
  assertEquals(await d.search!('q'), []);
  assertEquals(await d.read!('https://u.ae'), null);
  assertEquals([r.embeds.length, r.searches.length, r.reads.length], [0, 0, 0]);
  await d.llm('synthesise', 's', 'i', { taskClass: 'internal_judgement', seat: 'it_engineer' });
  assertEquals(r.calls.at(-1), { phase: 'synthesise', timeoutMs: 40_000 }, 'the answer starts with the whole reserve');
});

Deno.test('without a reserve nothing changes: every phase runs to the deadline and nothing is skipped', async () => {
  const t = { now: 50_000 }; const r = recorder(t);
  const d = withDeadline(r.deps, 90_000, MIN_STEP_MS, () => t.now);
  await d.llm('decompose', 's', 'i', { taskClass: 'routine_employee_reasoning', seat: 'it_engineer', timeoutMs: 75_000 });
  assertEquals(r.calls[0].timeoutMs, 40_000);
  assertEquals(await d.embed('x', 'gte'), [0.1]);
  assertEquals((await d.search!('q')).length, 1);
  assertEquals(d.embedFailure, r.deps.embedFailure, 'the deps are the caller\'s own');
});

// ── the replay, in the production shape ───────────────────────────────────────────────────────────────────────────
// Plan 20 s; the question and six plan steps embedded remotely at 7 s each (the question's vector is reused for the
// question-as-asked step); the answer needs 30 s (p90 on production is 31.7 s). With the budget spent first-come, the
// answer starts at 62 s with 28 s left and is cut at the wall, as on production; with the reserve the sixth step's
// embedding is not started, and the answer starts at 55 s with 35 s left.
const PLAN_MS = 20_000, EMBED_MS = 7_000, ANSWER_MS = 30_000;
function replayRig() {
  const t = { now: 0 }; const answers: { timeoutMs?: number; at: number; taskClass: string }[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase, _s, _i, o): Promise<LlmReply> => {
      if (phase === 'decompose') {
        t.now += PLAN_MS;
        return Promise.resolve({ content: J({ steps: Array.from({ length: 6 }, (_, i) => ({ id: 's' + (i + 1), goal: 'g' + i, query: 'ZZ DEMO step ' + i, needs_knowledge: true })), facts: [] }), model: 'openai/gpt-6-luna-pro' });
      }
      answers.push({ timeoutMs: o.timeoutMs, at: t.now, taskClass: o.taskClass });
      // what the gateway does: a call given less than it needs is cut at the wall and answers nothing
      if ((o.timeoutMs ?? Infinity) < ANSWER_MS) { t.now += o.timeoutMs ?? 0; return Promise.resolve({ content: null, model: null, error: 'gateway_http_502:gateway_deadline' }); }
      t.now += ANSWER_MS;
      return Promise.resolve({ content: J({ answer: 'ZZ DEMO the root cause is the stopwatch.', reasoning: ['the answer started late'], cited: [], confidence: 0.8, decision: { choice: 'fix' } }), model: 'openai/gpt-6-luna-pro' });
    },
    embed: () => { t.now += EMBED_MS; return Promise.resolve([0.1, 0.2, 0.3]); },
    rpc: (fn) => {
      if (fn === 'fn_reason_held_due') return Promise.resolve({ data: [{ id: 9001, seat: 'it_engineer', surface: 'it_engineer.postmortem', created_at: new Date().toISOString(),
        request: { seat: 'it_engineer', context: { audience: 'internal' }, question: 'ZZ DEMO what caused the outage?', decision: { name: 'next', options: [{ id: 'fix', meaning: 'fix it' }, { id: 'wait', meaning: 'wait' }] } } }], error: null });
      if (fn === 'fn_reason_held_resolve') return Promise.resolve({ data: { status: 'applied' }, error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { deps, t, answers };
}

Deno.test('a replayed row whose plan and retrieval are slow is still answered: the answer starts with the reserve', async () => {
  const r = replayRig();
  const out = await replayHeld(null, 1, r.deps, undefined, { maxRows: 1, budgetMs: REPLAY_BUDGET_MS, now: () => r.t.now }) as { rows: { status: string }[] };
  assertEquals(out.rows[0].status, 'answered', 'the row was held although its answer would have fitted');
  assertEquals(r.answers.length, 1, 'one answer call: ' + J(r.answers));
  assertEquals(r.answers[0].taskClass, 'internal_judgement');
  assert((r.answers[0].timeoutMs ?? 0) >= REPLAY_ANSWER_RESERVE_MS - EMBED_MS,
    `the answer was given ${r.answers[0].timeoutMs} ms; the reserve is ${REPLAY_ANSWER_RESERVE_MS} ms (one embed may straddle the line)`);
  assert(r.t.now <= REPLAY_BUDGET_MS, `the row ran to ${r.t.now} ms of a ${REPLAY_BUDGET_MS} ms budget`);
});
