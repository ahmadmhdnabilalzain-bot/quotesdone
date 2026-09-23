// reasoned_matching with a MOCKED model, embedder and database (the think.test.ts pattern). No network, no env,
// no paid call. Every branch: answered each way, and held -> no guess, one question queued with its surface,
// dedupeKey and subject.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from './think.ts';
import { applyReading, catalogueCategoryOf, productsAsked, readQuote, reasonedOffers } from './reasoned_matching.ts';
import { assessQuote, READ, type Line } from './line_specs/assess.ts';
import type { SpecOffer } from './line_specs/no_exact_spec.ts';

type Draft = { answer: string; reasoning?: string[]; decision: { choice?: string; fields?: Record<string, { value: string; evidence: string }> } };
/** A model that decides by `decide(question, systemPrompt)` (the prompt lists the decision's options or fields); `held: true` puts the founder's hold on the gate. */
function mock(decide: (question: string, sys: string) => Draft, o: { held?: boolean } = {}) {
  const holds: Record<string, unknown>[] = []; let calls = 0;
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: true, rule: 'ok' }) as never),
    llm: (phase, sys, input) => {
      calls++;
      const j = JSON.parse(input);
      if (phase === 'decompose') return Promise.resolve({ content: JSON.stringify({ steps: [], facts: [], high_stakes: false }), model: 'm' });
      if (phase === 'synthesise') return Promise.resolve({ content: JSON.stringify({ reasoning: ['s1: read it'], cited: [], confidence: 0.9, ...decide(j.question, sys) }), model: 'm' });
      return Promise.resolve({ content: JSON.stringify({ verdict: 'agree', problems: [] }), model: 'v' });
    },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn, args) => {
      if (fn === 'fn_reason_hold') { holds.push(args); return Promise.resolve({ data: holds.length, error: null }); }
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      return Promise.resolve({ data: [], error: null });
    },
  };
  return { deps, holds, calls: () => calls };
}
const choose = (choice: string) => () => ({ answer: 'Decided on what was written.', decision: { choice } });

Deno.test('catalogue category: the reasoned category, none, and under the hold no route and no model call', async () => {
  const cats = [{ catalog_num: 19, live_name: 'Aluminium & Glass' }, { catalog_num: 7, live_name: 'HVAC' }];
  assertEquals((await catalogueCategoryOf(mock(choose('c19')).deps, { text: 'نحتاج نوافذ ألمنيوم', categories: cats })).value, 19);
  assertEquals((await catalogueCategoryOf(mock(choose('none')).deps, { text: 'hello', categories: cats })).value, 0);
  const h = mock(choose('c7'), { held: true });
  const r = await catalogueCategoryOf(h.deps, { text: 'AC servicing', categories: cats, queue: false });
  assertEquals([r.value, r.result.status, h.calls(), h.holds.length], [null, 'held', 0, 0], 'a public visitor is asked now, nothing queued');
});

Deno.test('products asked: the reasoned product, none, and held -> not scored, one question queued', async () => {
  const products = [{ product_id: 'a1', name: 'Curtain wall profile' }, { product_id: 'b2', name: 'Door closer' }];
  assertEquals((await productsAsked(mock(choose('pa1')).deps, { want: 'curtain walling for a tower', products, inquiryId: 'i1', leadId: 5 })).value, ['a1']);
  assertEquals((await productsAsked(mock(choose('none')).deps, { want: 'painting', products, inquiryId: 'i1', leadId: 5 })).value, []);
  const h = mock(choose('pb2'), { held: true });
  assertEquals((await productsAsked(h.deps, { want: 'x', products, inquiryId: 'i1', leadId: 5 })).value, null);
  assertEquals([h.holds[0].p_surface, h.holds[0].p_dedupe_key, h.holds[0].p_subject], ['sql.fn_supplier_product_match', 'product_match:i1:5', { inquiry_id: 'i1', supplier_id: 5 }]);
});

const OFFER: SpecOffer = { line_no: 1, item: 'Wardrobe', attr: 'thickness_mm', label_en: 'Thickness', label_ar: 'السماكة', requested: '18mm',
  alternatives: [{ option_id: 'o1', value: '18 millimetres', suppliers: 1 }, { option_id: 'o2', value: '16mm', suppliers: 1 }] };
Deno.test('an offer is made ONLY on a reasoned difference; the same spec written differently is not offered; held offers nothing', async () => {
  const diff = await reasonedOffers(mock(choose('all_different')).deps, [OFFER], 'inq-1');
  assertEquals([diff.offers.length, diff.held, diff.same], [1, 0, 0]);
  const same = await reasonedOffers(mock(choose('o1')).deps, [OFFER], 'inq-1');
  assertEquals([same.offers.length, same.same], [0, 1], '"18 millimetres" IS the 18mm asked: that supplier quoted it');
  const h = mock(choose('all_different'), { held: true });
  const held = await reasonedOffers(h.deps, [OFFER], 'inq-1');
  assertEquals([held.offers.length, held.held], [0, 1], 'nobody is offered an alternative on a guess');
  assertEquals([h.holds[0].p_surface, h.holds[0].p_dedupe_key, h.holds[0].p_subject], ['line_specs.same_value', 'spec_offer:inq-1:1:thickness_mm', { inquiry_id: 'inq-1', line_no: 1, attr: 'thickness_mm' }]);
});

// The quotation, read: the supplier's words carry every value as verbatim evidence.
const LINES: Line[] = [{ line_no: 1, description: 'Wardrobe 18mm MR MDF carcass, HPL finish', amount: 6000 }, { line_no: 2, description: 'Installation labour', amount: 800 }];
const TERMS = { lead_time: '3 weeks', warranty: '2 years on workmanship and hardware', scope: 'Supply and installation by our own team', price_ex_vat: 6800 };
const ev = (value: string, evidence: string) => ({ value, evidence });
function reader(question: string, sys: string): Draft {
  if (sys.includes('installation_included (')) return { answer: 'Terms stated.', decision: { fields: {
    installation_included: ev('Supply and installation', 'Supply and installation by our own team'), installation_detail: ev('by our own team', 'installation by our own team'),
    warranty_period: ev('2 years', '2 years on workmanship'), warranty_coverage: ev('workmanship and hardware', 'workmanship and hardware') } } };
  const f: Record<string, { value: string; evidence: string }> = {};
  if (question.includes('LINE 1:')) Object.assign(f, { L1__material: ev('MR MDF', '18mm MR MDF carcass'), L1__thickness_mm: ev('18mm', '18mm MR MDF carcass'), L1__finish: ev('HPL', 'HPL finish') });
  if (question.includes('LINE 2:')) f.L2__not_material = ev('Installation labour', 'Installation labour');
  return { answer: 'Line details stated.', decision: { fields: f } };
}
Deno.test('readQuote: values with evidence, "no material", the terms — and the gate passes the quote on them', async () => {
  const m = mock(reader);
  const rd = (await readQuote(m.deps, { quoteId: 'q1', category: 'joinery', lines: LINES, terms: TERMS, requirements: null }))!;
  assertEquals(rd.lines[1], { material: 'MR MDF', thickness_mm: '18mm', finish: 'HPL' });
  assertEquals(rd.lines[2], { [READ.notMaterial]: 'Installation labour' });
  assertEquals([rd.terms.installation?.included, rd.terms.warranty?.coverage], ['yes', 'workmanship and hardware']);
  const ap = applyReading(LINES, null, rd);
  const a = assessQuote({ category: 'joinery', lines: ap.lines, terms: { ...TERMS, terms_spec: ap.terms_spec }, requirements: null });
  assertEquals([a.held, a.missing], [false, []]);
  assertEquals(a.lines[0].source.thickness_mm, 'reasoned');
});

Deno.test('readQuote: a composite line\'s trade is reasoned among the trades it may be; "none" carries no material', async () => {
  const m = mock((q, sys) => sys.includes('no trade material') ? { answer: 'It is joinery.', decision: { choice: q.includes('Wardrobe') ? 'joinery' : 'none' } } : reader(q, sys));
  const rd = (await readQuote(m.deps, { quoteId: 'q2', category: 'fitout', lines: LINES, terms: TERMS, requirements: null }))!;
  assertEquals([rd.lines[1][READ.trade], rd.lines[2][READ.trade]], ['joinery', 'none']);
});

Deno.test('readQuote UNDER THE HOLD: null, ONE question queued for the quote, and the gate holds it with every detail asked', async () => {
  const h = mock(reader, { held: true });
  assertEquals(await readQuote(h.deps, { quoteId: 'q3', category: 'joinery', lines: LINES, terms: TERMS, requirements: null }), null);
  assertEquals(h.holds.length, 1);
  assertEquals([h.holds[0].p_surface, h.holds[0].p_dedupe_key, h.holds[0].p_subject], ['line_specs.assess', 'quote_read:q3', { quote_id: 'q3' }]);
  const a = assessQuote({ category: 'joinery', lines: applyReading(LINES, null, null).lines, terms: TERMS, requirements: null });
  assert(a.held && a.missing.some((x) => x.line_no === 1 && x.attr === 'thickness_mm'), 'nothing was guessed from the words');
});

Deno.test('applyReading never overwrites what the supplier stated himself', () => {
  const l: Line[] = [{ line_no: 1, description: 'x', spec: { thickness_mm: '19' }, spec_source: { thickness_mm: 'supplier_portal' } }];
  const ap = applyReading(l, { delivery: { value: '10 days', source: 'supplier_portal' } }, { lines: { 1: { thickness_mm: '18mm', finish: 'HPL' } }, terms: { delivery: { value: '3 weeks', source: 'reasoned' } } });
  assertEquals([ap.lines[0].spec?.thickness_mm, ap.lines[0].spec_source?.thickness_mm, ap.lines[0].spec_source?.finish], ['19', 'supplier_portal', 'reasoned']);
  assertEquals(ap.terms_spec.delivery?.value, '10 days');
});

Deno.test('a value the quotation does not say is refused by the validator, never written in', async () => {
  const m = mock((q, sys) => sys.includes('installation_included (') ? reader(q, sys)
    : { answer: 'Line details stated.', decision: { fields: { L1__thickness_mm: ev('20mm', '20mm MR MDF carcass') } } });
  assertEquals(await readQuote(m.deps, { quoteId: 'q4', category: 'joinery', lines: [LINES[0]], terms: TERMS, requirements: null }), null);
  assertEquals(m.holds[0].p_dedupe_key, 'quote_read:q4');
});
