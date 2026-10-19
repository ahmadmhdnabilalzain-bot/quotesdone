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
  const r = await think(m.deps, { context: { audience: 'internal' }, seat: 'ceo', surface: 'test', question: 'Which bank do we use?', stakes: 'high' });
  assertEquals(r.status, 'answered');
  assertEquals(m.calls.map((c) => c.phase), ['decompose', 'synthesise', 'verify']);
  for (const c of m.calls) assertEquals(c.o.sysStable, settledFacts('internal', 'ceo'), c.phase);
  assertEquals(m.calls[0].o.timeoutMs, DECOMPOSE_TIMEOUT_MS);
  assertEquals(m.calls[1].o.max, SYNTH_MAX);
});

Deno.test('a missing or unknown audience gets the public brief, never the internal one (fails closed)', async () => {
  for (const a of [undefined, null, '', 'partner']) assertEquals(settledFacts(a), settledFacts('customer'), String(a));
  assertEquals(settledFacts('founder'), settledFacts('internal'));
  // A request that slips past the type (a held row stored before audience was required) is still sent the public brief.
  const m = mock();
  await think(m.deps, { seat: 'ceo', surface: 'test', question: 'Which bank do we use?', context: {} } as unknown as Parameters<typeof think>[1]);
  for (const c of m.calls) assertEquals(c.o.sysStable, settledFacts('customer'), c.phase);
});

Deno.test('an internal call carries its own seat card; an outside audience never gets any card', async () => {
  // The after-exam miss: it_engineer said the Resend cap was "not established"; its pack holds 50000.
  const it = settledFacts('internal', 'it_engineer');
  assert(it.startsWith(settledFacts('internal')) && it.includes('cap_resend_emails_month 50000'));
  assert(!settledFacts('internal', 'accountant').includes('cap_resend_emails_month'), 'a seat gets its own card, not another seat\'s');
  for (const a of ['customer', 'supplier', 'visitor', undefined, 'partner']) {
    assertEquals(settledFacts(a, 'it_engineer'), settledFacts('customer'), String(a));
    assert(!settledFacts(a, 'it_engineer').includes('operating facts from its own verified pack'), String(a));
  }
  for (const s of ['nobody', '__proto__', 'constructor', null]) assertEquals(settledFacts('internal', s), settledFacts('internal'), String(s));
  const m = mock();
  await think(m.deps, { context: { audience: 'internal' }, seat: 'it_engineer', surface: 'test', question: 'Resend monthly cap?', stakes: 'high' });
  for (const c of m.calls) assertEquals(c.o.sysStable, it, c.phase);
  const x = mock();
  await think(x.deps, { context: { audience: 'customer' }, seat: 'it_engineer', surface: 'test', question: 'Resend monthly cap?', stakes: 'high' });
  for (const c of x.calls) assertEquals(c.o.sysStable, settledFacts('customer'), c.phase);
});

Deno.test('retrieval is told the audience: the company\'s own pack rows are for an internal call only', async () => {
  const sent: Record<string, unknown>[] = [];
  const run = async (context: Record<string, unknown>) => {
    const m = mock();
    m.deps.llm = (phase) => Promise.resolve({ model: 'm', content: phase === 'synthesise' ? J({ answer: 'x', reasoning: [], cited: [], confidence: 0.9 })
      : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
      : J({ steps: [{ id: 's1', goal: 'x', query: 'Resend monthly cap', needs_knowledge: true }], facts: [], high_stakes: false }) } as LlmReply);
    m.deps.rpc = (fn, args) => { if (String(fn).startsWith('fn_reason_retrieve')) sent.push(args as Record<string, unknown>); return Promise.resolve({ data: fn.startsWith('fn_case_recall') ? { cases: [] } : [], error: null }); };
    sent.length = 0;
    await think(m.deps, { context, seat: 'it_engineer', surface: 'test', question: 'Resend monthly cap?' } as unknown as Parameters<typeof think>[1]);
    assert(sent.length > 0, 'retrieval ran');
    return sent.map((a) => a.p_audience);
  };
  for (const a of ['customer', 'supplier', 'visitor', 'internal', 'founder']) assertEquals(await run({ audience: a }), [a]);
  assertEquals(await run({}), [null], 'a missing audience is sent as none, which the routine treats as external');
});
