// A BACKGROUND JUDGEMENT HAS THE TIME HIGH EFFORT TAKES (it_engineer, 12 Nov 2026; founder ledger 1642; final audit 2026-11-12
// section 3, E6). Since the 11 Nov raise to high, marketing's internal_judgement was lost 4 of 4 at 46.7-47.2 s (think/deps.ts
// gave every call that named none 45 s, a 47 s gateway wall) and the independent reviewer answered p50 53.1 s. An internal
// audience's answer and review now get INTERNAL_CALL_TIMEOUT_MS (think/tunables.ts carries the measurement); a call that names
// its own timeout keeps it, a customer's call keeps the 45 s default, and a caller's clock still cuts (withDeadline).
// No network, no paid call.
import { assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { think, withDeadline, type LlmReply, type Phase, type ThinkDeps } from './think.ts';
import { DECOMPOSE_TIMEOUT_MS, INTERNAL_CALL_TIMEOUT_MS, INTERNAL_RUN_DEADLINE_MS } from './think/tunables.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock() {
  const calls: { phase: Phase; timeoutMs?: number }[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, _s, _i, o) => {
      calls.push({ phase, timeoutMs: o.timeoutMs });
      const content = phase === 'synthesise' ? J({ answer: 'ZZ DEMO the trend is relevant to fit-out buyers.', reasoning: ['s1'], cited: [], confidence: 0.9 })
        : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
        : J({ steps: [{ id: 's1', goal: 'x', query: 'x', needs_knowledge: false }], facts: [], high_stakes: false });
      return Promise.resolve({ content, model: 'openai/gpt-6-luna-pro' } as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_case_recall' ? { cases: [] } : [], error: null }),
  };
  return { deps, calls };
}
const ask = (audience: string) => ({ context: { audience } as never, seat: 'marketing' as const, surface: 'marketing.zz_demo_trend', question: 'ZZ DEMO is this trend relevant?', stakes: 'high' as const });

Deno.test('an internal judgement: the answer and the independent review get the background limit, the planner keeps its own', async () => {
  const m = mock();
  await think(m.deps, ask('internal'));
  const by = (p: Phase) => m.calls.filter((c) => c.phase === p).map((c) => c.timeoutMs);
  assertEquals(by('synthesise').length > 0 && by('synthesise').every((t) => t === INTERNAL_CALL_TIMEOUT_MS), true, JSON.stringify(m.calls));
  assertEquals(by('verify'), [INTERNAL_CALL_TIMEOUT_MS]);
  assertEquals(by('decompose').every((t) => t === DECOMPOSE_TIMEOUT_MS), true);
  assertEquals(INTERNAL_CALL_TIMEOUT_MS > 83_491 && INTERNAL_CALL_TIMEOUT_MS > 93_491, true, 'over the measured answer p95 and the reviewer p90');
});

Deno.test("a customer's or the founder's judgement keeps the per-call default; a caller's clock still cuts a background call", async () => {
  for (const a of ['customer', 'founder']) {
    const m = mock();
    await think(m.deps, ask(a));
    assertEquals(m.calls.filter((c) => c.phase === 'synthesise' || c.phase === 'verify').every((c) => c.timeoutMs === undefined), true, a + ': ' + JSON.stringify(m.calls));
  }
  const m = mock(); const t0 = Date.now();
  await think(withDeadline(m.deps, t0 + 60_000), ask('internal'));
  assertEquals(m.calls.filter((c) => c.phase === 'synthesise').every((c) => (c.timeoutMs ?? 0) <= 60_000), true, JSON.stringify(m.calls));
});

// THE RUN HAS ONE DEADLINE (review of 12 Nov 2026, finding 1): an answer that spends the run leaves no time for the review; the
// review is not started, and the answer comes back verified 'not_run' with the deadline as the reason: said, never silent.
Deno.test('an internal run ends by its deadline: a review with no time left is recorded as not run, with the reason', async () => {
  const realNow = Date.now; const t0 = realNow(); let clock = t0;
  const m = mock();
  const base = m.deps.llm;
  // the answer takes all but 1 s of the run (the clock is read through Date.now, which withDeadline captured)
  m.deps.llm = (phase, s, i, o) => { if (phase === 'synthesise') clock = t0 + INTERNAL_RUN_DEADLINE_MS - 1_000; return base(phase, s, i, o); };
  try {
    Date.now = () => clock;
    const r = await think(m.deps, ask('internal'));
    assertEquals(m.calls.some((c) => c.phase === 'verify'), false, 'the review was started past the deadline');
    assertEquals(r.status, 'answered');
    assertEquals(r.verified?.status, 'not_run');
    assertEquals(/turn_deadline/.test(String(r.verified?.notes)), true, String(r.verified?.notes));
  } finally { Date.now = realNow; }
});
