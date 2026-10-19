// Every think() call carries the settled company facts and the founder's rulings (ceo, ledger 1003 stage 2, 19 Oct 2026).
// Measured before: no call carried them, and seats answered settled facts wrongly or "not on record". No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { DECOMPOSE_TIMEOUT_MS, settledFacts, SETTLED_HEADER, SYNTH_MAX, think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock() {
  const calls: { phase: Phase; o: Record<string, unknown> }[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
    llm: (phase, _s, _i, o) => {
      calls.push({ phase, o: o as Record<string, unknown> });
      const content = phase === 'synthesise' ? J({ answer: 'Mashreq, AED 199 plus AED 9.95 VAT a month.', reasoning: ['s1: the settled facts'], cited: [], confidence: 0.9 })
        : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
        : J({ steps: [{ id: 's1', goal: 'x', query: 'x', needs_knowledge: false }], facts: [], high_stakes: true });
      return Promise.resolve({ content, model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_case_recall' ? { cases: [] } : [], error: null }),
  };
  return { deps, calls };
}

Deno.test('the internal brief carries the rulings the seat exam found missing', () => {
  const f = settledFacts('internal');
  assert(f.startsWith(SETTLED_HEADER));
  for (const fact of ['Mashreq', 'AED 199', '24 Jun 2027', 'AED 375,000', 'decided by the CEO seat', 'Exact trade or none', 'social.lead', 'does **not** own']) {
    assert(f.includes(fact), 'missing: ' + fact);
  }
});

Deno.test('an outside audience gets the company brief, never the internal one', () => {
  for (const a of ['customer', 'supplier', 'visitor']) {
    const f = settledFacts(a);
    assert(f.includes('3% reveal fee'), a);
    assert(!f.includes('Mashreq') && !f.includes('settled facts and founder rulings every seat'), a + ' must not receive the internal facts');
  }
});

Deno.test('the plan, every answer pass and the review all carry the settled facts', async () => {
  const m = mock();
  const r = await think(m.deps, { seat: 'ceo', surface: 'test', question: 'Which bank do we use?', stakes: 'high' });
  assertEquals(r.status, 'answered');
  assertEquals(m.calls.map((c) => c.phase), ['decompose', 'synthesise', 'verify']);
  for (const c of m.calls) assertEquals(c.o.sysStable, settledFacts('internal'), c.phase);
  assertEquals(m.calls[0].o.timeoutMs, DECOMPOSE_TIMEOUT_MS);
  assertEquals(m.calls[1].o.max, SYNTH_MAX);
});
