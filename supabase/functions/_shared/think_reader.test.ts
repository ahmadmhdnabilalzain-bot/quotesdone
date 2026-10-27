// A reader of the person's own text plans nothing, looks nothing up, has room for its decision, and the quotation's
// readers that do not depend on each other run side by side (13 Oct 2026, measured live: 7 sequential calls, answers cut
// at 900 tokens, the photo turn past 150 s). No network, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import { keepProvenFields, READER_MIN_EVIDENCE, readerOfTheirOwnText, refuse, SYNTH_FOR_READERS, type LlmReply, type Phase, type ThinkDeps } from './think.ts';
import { quoteTerms } from './reasoned_suppliers.ts';
import { forgetReads, readQuote } from './reasoned_matching.ts';
import type { Line } from './line_specs/assess.ts';

const J = (x: unknown) => JSON.stringify(x);
function mock(synth: () => unknown, delayMs = 0) {
  const calls: { phase: Phase; max: unknown }[] = []; let active = 0; let peak = 0;
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: false, rule: 'route_not_registered' } as GateAnswer),
    llm: async (phase, _s, _i, o) => {
      calls.push({ phase, max: (o as { max?: unknown }).max });
      active++; peak = Math.max(peak, active);
      await new Promise((r) => setTimeout(r, delayMs));
      active--;
      const content = phase === 'synthesise' ? J(synth()) : phase === 'verify' ? J({ verdict: 'agree', problems: [] }) : J({ steps: [{ id: 's1', goal: 'x' }], facts: [] });
      return { content, model: 'qwen/qwen3.8-max-0902' } as LlmReply;
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn) => Promise.resolve({ data: fn === 'fn_reason_retrieve' ? [] : fn === 'fn_case_recall' ? { cases: [] } : 1, error: null }),
    search: () => Promise.resolve([]),
    read: () => Promise.resolve(null),
  };
  return { deps, calls, peak: () => peak };
}

Deno.test('a reader plans nothing, retrieves nothing, and has room for its decision', () => {
  const r = readerOfTheirOwnText('read it');
  assertEquals(r.plan!.steps.length, 1);
  assertEquals(r.plan!.steps[0].needs_knowledge, false);
  assert(SYNTH_FOR_READERS > 900 && SYNTH_FOR_READERS <= 4000, 'above think()\'s old 900, within supplier_communication\'s policy cap');
});

Deno.test('the quotation terms are read without a decompose call, with room for the answer', async () => {
  const m = mock(() => ({ answer: 'read', decision: { fields: { validity: { value: '30 days', evidence: 'Validity: 30 days' } } } }));
  const r = await quoteTerms(m.deps, { text: 'Validity: 30 days\nLead time: 3 weeks' });
  assertEquals(r.value?.validity, '30 days');
  assertEquals(m.calls.filter((c) => c.phase === 'decompose' || c.phase === 'research').length, 0, J(m.calls));
  assert(m.calls.filter((c) => c.phase === 'synthesise').every((c) => c.max === SYNTH_FOR_READERS), J(m.calls));
});

Deno.test('readQuote: the terms and the line specs are asked side by side, not one after the other', async () => {
  forgetReads?.();
  const m = mock(() => ({ answer: 'read', decision: { fields: {} } }), 30);
  const lines: Line[] = [{ line_no: 1, description: 'Jotun Fenomastic emulsion 2 coats internal walls', qty: '450', unit: 'm2', unit_price: 20, amount: 9000 } as unknown as Line];
  const rd = await readQuote(m.deps, { quoteId: 'q-parallel', category: 'painting', lines, terms: { lead_time: '3 weeks', warranty: '2 years', terms_spec: {} } as never, requirements: null });
  assert(rd, 'the reading was refused');
  assertEquals(m.calls.filter((c) => c.phase === 'decompose').length, 0);
  assert(m.peak() >= 2, 'the terms and the lines were asked one after the other (peak concurrency ' + m.peak() + ')');
});

// THE MEASURED FAILURE (18 Oct 2026, 5 runs of one ZZ DEMO photographed quotation): a reader that answered every term
// correctly but added a question back was refused twice and HELD, so the review asked again for what the photo stated.
Deno.test('a reader that adds a question back keeps its reading; a non-reader still may not ask back', async () => {
  const asks = { answer: 'The quotation states a 3-week lead time, 30-day validity, and a 2-year warranty covering materials and workmanship.',
    reasoning: ['read: the text states them'], cited: [], confidence: 1, asked_back: 'Please confirm the payment terms.',
    decision: { fields: { validity: { value: '30 days', evidence: 'Validity: 30 days' }, lead_time: { value: '3 weeks', evidence: 'Lead time: 3 weeks' } } } };
  const m = mock(() => asks);
  const r = await quoteTerms(m.deps, { text: 'Validity: 30 days\nLead time: 3 weeks' });
  assertEquals(r.value?.validity, '30 days', 'the reading was dropped because the model asked back: ' + JSON.stringify((r.result as { reason?: string }).reason));
  assertEquals(r.value?.lead_time, '3 weeks');
  assertEquals(m.calls.filter((c) => c.phase === 'synthesise').length, 1, 'a reader was asked to rewrite only because it asked back');
});

// THE SECOND MEASURED FAILURE (18 Oct 2026, 5 more runs of the same photo): ONE field whose evidence was short ("2 coats",
// "Jotun") or whose value was a paraphrase refused every other, correct field with it, so the line specs and the terms
// the photo stated were asked again.
Deno.test('a reader keeps every field its own words prove; a paraphrased or invented field alone is dropped', async () => {
  const text = 'Jotun Fenomastic emulsion 2 coats internal walls\nValidity: 30 days\nPrices exclude VAT';
  const m = mock(() => ({ answer: 'The quotation states its validity and that prices exclude VAT.', reasoning: ['read: stated'], cited: [], confidence: 1, asked_back: null,
    decision: { fields: {
      validity: { value: '30 days', evidence: 'Validity: 30 days' },                       // proven
      lead_time: { value: '3 weeks', evidence: 'Lead time: 3 weeks' },                     // invented: not in the text
      exclusions: { value: 'VAT excluded from the prices', evidence: 'Prices exclude VAT' }, // paraphrase: value not in its evidence
    } } }));
  const r = await quoteTerms(m.deps, { text });
  assertEquals(r.value, { validity: '30 days' }, 'only the proven field survives: ' + JSON.stringify(r.value));
});

Deno.test('readQuote: short verbatim evidence ("2 coats", "Jotun") proves a line spec', async () => {
  forgetReads?.();
  const m = mock(() => ({ answer: 'Line 1 states the brand and the coats.', reasoning: ['read: stated'], cited: [], confidence: 1, asked_back: 'What sheen?',
    decision: { fields: { L1__brand: { value: 'Jotun', evidence: 'Jotun' }, L1__coats: { value: '2 coats', evidence: '2 coats' } } } }));
  const lines: Line[] = [{ line_no: 1, description: 'Jotun Fenomastic emulsion 2 coats internal walls', qty: '450', unit: 'm2', unit_price: 20, amount: 9000 } as unknown as Line];
  const rd = await readQuote(m.deps, { quoteId: 'q-short', category: 'painting', lines, terms: { lead_time: '3 weeks', warranty: '2 years', terms_spec: {} } as never, requirements: null });
  assert(rd, 'the reading was dropped');
  assertEquals(rd!.lines[1]?.brand, 'Jotun', JSON.stringify(rd));
  assertEquals(rd!.lines[1]?.coats, '2 coats');
});

Deno.test('a non-reader keeps the strict rule: one unproven field refuses the draft', () => {
  const draft = { answer: 'x '.repeat(30), reasoning: ['r'], decision: { fields: { brand: { value: 'Jotun', evidence: 'Jotun' } } } };
  const why = refuse(draft as never, { missing: [], sourceIds: new Set(), decision: { name: 'd', fields: [{ key: 'brand', question: 'the brand' }] }, conversationText: 'Jotun paint', requireTrail: false });
  assert(why && /no evidence copied verbatim/.test(why), String(why));
  assertEquals(keepProvenFields(draft as never, { name: 'd', fields: [{ key: 'brand', question: 'the brand' }] }, 'Jotun paint'), [], 'a reader keeps it: "Jotun" is 5 characters, verbatim');
  assertEquals(READER_MIN_EVIDENCE, 4);
});
