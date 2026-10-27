// THE HELD REPLAY NEVER RUNS GTE-SMALL IN ITS OWN WORKER (it_engineer, 27 Oct 2026).
//
// Replays the batch that killed production: four seat revisions for the CEO (marketing's November month plan among them)
// claimed in one tick, each planned in five English steps on the multilingual space. On production the detached itlater
// worker ran gte-small in-process for every step and the question (24 runs for the four rows) and the edge runtime
// stopped it at its 2 s CPU cap (shutdown reason CPUTime, 2,091-2,160 ms, 27 Oct 01:17:52, 01:47:34, 02:17:25 UTC)
// before fn_reason_held_resolve could record anything. After three claims the sweep closed each row 'failed' with no
// result, and the plan sat in ceo_reviewing. See the header above defaultDeps in think.ts for the measurements.
//
// The edge runtime is stubbed here: Supabase.ai.Session counts every in-process run. The heartbeat's deps must make
// none. Break it once to see: give heartbeatDeps the in-worker session (drop `{ gte: 'remote' }`) and the count is 24.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/held_replay_keeps_gte_out_of_the_worker.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { heartbeatDeps, replayHeld, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);

// The edge runtime's in-process gte-small, counted.
const inWorker = { sessions: 0, runs: 0 };
// deno-lint-ignore no-explicit-any
(globalThis as any).Supabase = { ai: { Session: class {
  constructor() { inWorker.sessions++; }
  run() { inWorker.runs++; return Promise.resolve(Array.from({ length: 384 }, () => 0.01)); }
} } };

// Four seat revisions, the shape fn_seat_revises_for_the_ceo files (surface <seat>.ceo_revision, a two-option decision).
const SEATS = ['sales_engineer', 'marketing', 'marketing', 'customer_support'];
const rows = SEATS.map((seat, i) => ({
  id: 9100 + i, seat, surface: seat + '.ceo_revision', subject: { handoff_id: 1000 + i }, created_at: new Date().toISOString(),
  request: {
    seat, surface: seat + '.ceo_revision', audience: 'internal',
    question: 'The CEO sent your submission back (round 2). Read each of the CEO\'s reasons. Produce a revised version that answers every one of them.',
    decision: { name: 'revision', options: [{ id: 'revised', meaning: 'the submission is revised' }, { id: 'defended', meaning: 'the submission stands' }] },
    context: { audience: 'internal', case: { path: 'marketing_month_plan', round: 2, ceo_reasons: 'the twelve ideas are word for word the round-1 plan' } },
  },
}));

// The plan the model wrote for 28986: five English steps, every one needing knowledge.
const PLAN = J({ steps: ['Verify pricing and promotional claims.', 'Define attribution and fallback wording.', 'Rebalance the actual idea list around supply.',
  'Confirm required compliance lines.', 'Check the resubmission against every CEO reason.'].map((goal, i) => ({ id: 's' + (i + 1), goal, query: goal, needs_knowledge: true })), facts: [] });
const DRAFT = J({ answer: 'Revised: every CEO reason is answered in the list.', decision: { choice: 'revised' }, cited: [], confidence: 0.7,
  revision: 'the revised plan', answers: 'each reason answered' });

function admin() {
  const rpcs: string[] = [];
  return {
    rpcs,
    rpc: (fn: string) => {
      rpcs.push(fn);
      if (fn === 'fn_kernel_paid_provider_gate') return Promise.resolve({ data: { allowed: true, rule: 'open' }, error: null });
      if (fn === 'fn_reason_held_due') return Promise.resolve({ data: rpcs.filter((f) => f === 'fn_reason_held_due').length === 1 ? rows : [], error: null });
      if (fn === 'fn_ml_read_space') return Promise.resolve({ data: 'ml', error: null });
      if (fn.startsWith('fn_reason_retrieve')) return Promise.resolve({ data: [{ source: 'kb_chunks', id: 1, title: 'pack', excerpt: 'a fact', citation: null, similarity: 0.9, trust: 'reviewed' }], error: null });
      if (fn.startsWith('fn_case_recall')) return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_held_resolve') return Promise.resolve({ data: { status: 'applied' }, error: null });
      return Promise.resolve({ data: 1, error: null });
    },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { value: 'test-credential' }, error: null }) }) }) }),
  };
}

// Only the model is replaced: everything else is the deps the heartbeat really runs on.
const model: ThinkDeps['llm'] = (phase: Phase) => Promise.resolve({ content: phase === 'decompose' ? PLAN : phase === 'verify' ? J({ verdict: 'agree', problems: [] }) : DRAFT, model: 'openai/gpt-6-luna-pro' } as LlmReply);

// Out of the test's sandbox (no --allow-net) the remote embedder answers null; stub fetch so a run that does have
// network access never leaves the process either.
const realFetch = globalThis.fetch;
const remote: string[] = [];
globalThis.fetch = ((u: string | URL | Request) => {
  remote.push(String(u));
  return Promise.resolve(new Response(J({ embedding: J(Array.from({ length: 384 }, () => 0.02)), space: 'gte' }), { status: 200 }));
}) as typeof fetch;

Deno.test('four seat revisions replayed in one tick run gte-small in embed_ml, never in the replay\'s own worker', async () => {
  try {
    const a = admin();
    inWorker.sessions = 0; inWorker.runs = 0;
    const out = await replayHeld(a, 5, { ...heartbeatDeps(a), llm: model }) as { replayed: number; rows: { status: string }[] };
    assertEquals(out.replayed, 4);
    assert(out.rows.every((r) => r.status === 'answered'), 'each revision is reasoned and resolved: ' + J(out.rows));
    assertEquals(a.rpcs.filter((f) => f === 'fn_reason_held_resolve').length, 4, 'every claimed row reaches fn_reason_held_resolve');
    assertEquals(inWorker.runs, 0, `the replay ran gte-small ${inWorker.runs} times inside its own worker; on 27 Oct 24 such runs in one tick hit the 2 s CPU cap`);
    assertEquals(inWorker.sessions, 0, 'the replay never loads the gte-small session in its own worker');
  } finally { globalThis.fetch = realFetch; }
});

Deno.test('the heartbeat\'s embedder asks embed_ml for gte-small, the same 384-dimension space', async () => {
  const a = admin();
  inWorker.runs = 0;
  await heartbeatDeps(a).embed('Rebalance the actual idea list around supply.', 'gte');
  await heartbeatDeps(a).embed('a research finding with no space named');
  assertEquals(inWorker.runs, 0);
});

// EVERY STEP OF THE HEARTBEAT BUILDS ITS DEPS WITH heartbeatDeps (it_engineer, 27 Oct 2026). Merging main into #1678
// brought #1659's supportVoiceTick in on defaultDeps(admin, 'resilience_ping'): the in-worker gte-small session, in the
// same worker whose 2 s CPU cap killed the replay. Its writer (aiReply) asks for no embedding today, so nothing burned yet;
// a step that does would be killed the way 28985-28988 were. resilience_ping builds no deps but heartbeatDeps.
Deno.test('resilience_ping builds every reasoning deps with heartbeatDeps, never the in-worker defaultDeps', async () => {
  const src = await Deno.readTextFile(new URL('../resilience_ping/index.ts', import.meta.url));
  const lines = src.split('\n');
  const code = lines.filter((l) => !/^\s*\/\//.test(l)).join('\n');
  const inWorker = lines.flatMap((l, i) => !/^\s*\/\//.test(l) && /defaultDeps\s*\(/.test(l) ? [i + 1] : []);
  assertEquals(inWorker, [], `resilience_ping calls defaultDeps (gte-small in its own worker) at line(s) ${inWorker.join(', ')}; use heartbeatDeps(admin)`);
  assert(/writeOwedDutyMessages\(liveVoiceIO\(admin, heartbeatDeps\(admin\)\)/.test(code), 'the support voice step writes on heartbeatDeps');
  assert(/drainRoutineJudgements\(heartbeatDeps\(admin\)/.test(code), 'the routine judgements drain on heartbeatDeps');
});
