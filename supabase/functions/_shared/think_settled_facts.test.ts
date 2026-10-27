// Every think() call carries the settled company facts and the founder's rulings (ceo, ledger 1003 stage 2, 19 Oct 2026).
// Measured before: no call carried them, and seats answered settled facts wrongly or "not on record". No network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { audienceOf, DECOMPOSE_TIMEOUT_MS, settledFacts, SETTLED_HEADER, SYNTH_MAX, think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

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
  for (const a of ['customer', 'supplier', 'visitor', 'internal', 'founder']) assertEquals(await run({ audience: a }), [a, a]);   // the planned step and the question as asked
  assertEquals(await run({}), ['visitor', 'visitor'], 'a missing audience is sent as a visitor: one fallback, external');
  assertEquals(await run({ audience: 'partner' }), ['visitor', 'visitor'], 'an unknown audience is a visitor too');
});

// prevented by: this test. Before #1591's follow-up a missing audience read the brief and retrieval as external but the
// case-memory text, the model class and the prompt label as internal. Every reader must reach the same verdict.
Deno.test('one fallback: brief, retrieval, case text and model class agree on every audience, named or not', async () => {
  const SECRET = 'ZZ DEMO other customer inquiry 4711 for 40 aluminium windows';
  for (const a of [undefined, null, '', 'partner', 'Internal', 'customer', 'supplier', 'visitor', 'internal', 'founder']) {
    const seen = { facts: [] as string[], retrieve: [] as unknown[], classes: [] as string[], caseText: false };
    const deps: ThinkDeps = {
      gate: () => Promise.resolve({ allowed: true } as unknown as GateAnswer),
      llm: (phase, _s, input, o) => {
        const oo = o as Record<string, unknown>;
        seen.facts.push(String(oo.sysStable)); if (phase === 'synthesise') { seen.classes.push(String(oo.taskClass)); if (String(input).includes(SECRET)) seen.caseText = true; }
        return Promise.resolve({ model: 'm', content: phase === 'synthesise' ? J({ answer: 'x', reasoning: [], cited: [], confidence: 0.9 })
          : phase === 'verify' ? J({ verdict: 'agree', problems: [] })
          : J({ steps: [{ id: 's1', goal: 'x', query: 'q', needs_knowledge: true }], facts: [], high_stakes: true }) } as LlmReply);
      },
      embed: () => Promise.resolve([0.1, 0.2, 0.3]),
      rpc: (fn, args) => {
        if (String(fn).startsWith('fn_reason_retrieve')) seen.retrieve.push((args as Record<string, unknown>).p_audience);
        return Promise.resolve({ data: String(fn).startsWith('fn_case_recall') ? { cases: [{ case_id: 1, seat: 'ceo', case_kind: 'quote', situation: SECRET, finalised: true, similarity: 0.95 }] } : [], error: null });
      },
    };
    await think(deps, { seat: 'ceo', surface: 'test', question: 'What happened on that job?', context: a === undefined ? {} : { audience: a } } as unknown as Parameters<typeof think>[1]);
    const internal = a === 'internal' || a === 'founder';
    const tag = String(a);
    assertEquals(audienceOf(a) === 'internal' || audienceOf(a) === 'founder', internal, tag);
    for (const f of seen.facts) assertEquals(f, internal ? settledFacts(a as string, 'ceo') : settledFacts('visitor'), tag + ' brief');
    assert(seen.retrieve.length > 0, tag + ' retrieval ran');
    for (const p of seen.retrieve) assertEquals(p === 'internal' || p === 'founder', internal, tag + ' p_audience ' + String(p));
    assertEquals(seen.caseText, internal, tag + ' case text');
    for (const c of seen.classes) assertEquals(c === 'internal_judgement', internal, tag + ' model class ' + c);
  }
});
