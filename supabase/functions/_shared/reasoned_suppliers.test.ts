// reasoned_suppliers with a MOCKED model and database: every branch answered each way, and held -> no guess,
// queued (or deliberately not) under the right surface, dedupe key and subject. No network, no paid call.
//   deno test --no-lock supabase/functions/_shared/reasoned_suppliers.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { GateAnswer } from './llm_hold.ts';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { capabilityKinds, ownWordService, priceGuidanceFor, priceQuestion, quoteTerms, readSupplierProfile, reasonQuoteAspects } from './reasoned_suppliers.ts';

const J = (x: unknown) => JSON.stringify(x);
const PLAN = J({ steps: [{ id: 's1', goal: 'read what was written', needs_knowledge: false }], facts: [] });
const HOLD = { allowed: false, rule: 'founder_hold', held: 1, routes: 8 };

function mock(o: { hold?: boolean; synth?: unknown[]; rpc?: Record<string, unknown> }) {
  const rpcs: [string, Record<string, unknown>][] = [];
  const synth = [...(o.synth ?? [])].map((x) => J(x));
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.hold ? HOLD : { allowed: false, rule: 'route_not_registered' }) as GateAnswer),
    llm: (phase: Phase) => {
      const content = phase === 'decompose' ? PLAN : phase === 'synthesise' ? synth.shift() ?? null : J({ verdict: 'agree', problems: [] });
      return Promise.resolve({ content, model: 'qwen/qwen3.8-max-0902' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 77, error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      if (o.rpc && fn in o.rpc) return Promise.resolve({ data: o.rpc[fn], error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { deps, rpcs, held: () => rpcs.filter(([f]) => f === 'fn_reason_hold').map(([, a]) => a) };
}

// ── quote_extract.document ──
const QUOTE = 'Porcelain tiles 600x600 supply and fix 120 sqm 85 10200\nLead time: 3 weeks from approval\nValidity: 30 days\nWe do not include skirting.';
Deno.test('quote terms: each term is the words the file states, and an unstated one is left out', async () => {
  const m = mock({ synth: [{ answer: 'Lead time and validity are stated; the exclusion is skirting.', decision: { fields: {
    lead_time: { value: '3 weeks from approval', evidence: 'Lead time: 3 weeks from approval' },
    validity: { value: '30 days', evidence: 'Validity: 30 days' },
    exclusions: { value: 'skirting', evidence: 'We do not include skirting' } } } }] });
  const r = await quoteTerms(m.deps, { text: QUOTE });
  assertEquals(r.value, { lead_time: '3 weeks from approval', validity: '30 days', exclusions: 'skirting' });
});
Deno.test('quote terms held: nothing read, nothing queued (the supplier types them on the form now)', async () => {
  const m = mock({ hold: true });
  const r = await quoteTerms(m.deps, { text: QUOTE });
  assertEquals(r.value, null);
  assertEquals(m.held().length, 0);
});

// ── sql.fn_price_guidance ──
const TRADES = ['flooring', 'gypsum-false-ceiling', 'waterproofing'];
Deno.test('price: a reasoned trade and item reach fn_price_guidance by key; the question never does', async () => {
  const m = mock({ synth: [{ answer: 'They ask the price of a gypsum ceiling.', decision: { choice: 'gypsum-false-ceiling', fields: { item: { value: 'false ceiling', evidence: 'gypsum false ceiling cost' } } } }] });
  // The database: the trade list for no trade, the trade's bands for a trade.
  const BANDS = { ok: true, trade: 'gypsum-false-ceiling', asked_item: 'false ceiling', bands: [{ item: 'ceiling', low: 35, high: 70 }] };
  const rpc = m.deps.rpc;
  m.deps.rpc = (fn, a) => fn === 'fn_price_guidance' ? (m.rpcs.push([fn, a]), Promise.resolve({ data: a.p_trade == null ? { ok: false, reason: 'needs_reasoning', trades: TRADES } : BANDS, error: null })) : rpc(fn, a);
  const r = await priceGuidanceFor(m.deps, 'what should a gypsum false ceiling cost per square metre in Dubai');
  const calls = m.rpcs.filter(([f]) => f === 'fn_price_guidance').map(([, a]) => a);
  assertEquals(calls[0], { p_trade: null, p_limit: 6 });
  assertEquals(calls[1], { p_trade: 'gypsum-false-ceiling', p_limit: 6, p_asked_item: 'false ceiling' });
  assert(!JSON.stringify(calls).includes('Dubai'), 'the free text never reaches the SQL');
  assertEquals(r, BANDS);
});
Deno.test('price: a question about platform fees is not a price question, and gets no band', async () => {
  const m = mock({ synth: [{ answer: 'They ask about the reveal fee, not a trade price.', decision: { choice: 'not_a_price_question' } }], rpc: { fn_price_guidance: { trades: TRADES } } });
  const r = await priceGuidanceFor(m.deps, 'what fee do suppliers pay');
  assertEquals(r, { ok: false, reason: 'not_a_price_question', asked_item: null });
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_price_guidance').length, 1);
});
Deno.test('price: a price asked of a trade we do not publish is said so, never substituted', async () => {
  const m = mock({ synth: [{ answer: 'They ask the price of a chiller, which is not listed.', decision: { choice: 'other_trade' } }] });
  const r = await priceQuestion(m.deps, { question: 'what does a chiller replacement cost', trades: TRADES });
  assertEquals(r.value, { trade: null, asks_price: true, item: null });
});
Deno.test('price held: reason held, no band, not queued (the visitor is answered from the FAQ now)', async () => {
  const m = mock({ hold: true, rpc: { fn_price_guidance: { trades: TRADES } } });
  const r = await priceGuidanceFor(m.deps, 'how much is waterproofing a roof');
  assertEquals(r, { ok: false, reason: 'held', held: true });
  assertEquals(m.held().length, 0);
  assertEquals(m.rpcs.filter(([f]) => f === 'fn_price_guidance').length, 1, 'no band is fetched on a guess');
});

// ── sql.fn_supplier_twin ──
const SUMMARY = 'We manufacture aluminium windows in our Sharjah factory. We do not install; installation is by others.';
// What this pins is the RULE, not the model: a capability counts only with a value and the words that state it;
// a field the model leaves out (as it must for "we do not install") is false, and a field whose evidence is not
// the supplier's own words is refused by think() and never reaches here (think.test.ts pins refuse()).
Deno.test('capabilities: only what the summary says the company does itself; "we do not install" is not installation', async () => {
  const m = mock({ synth: [{ answer: 'They manufacture; they say they do not install.', decision: { fields: {
    manufacturing: { value: 'manufacture aluminium windows', evidence: 'We manufacture aluminium windows' } } } }] });
  const r = await capabilityKinds(m.deps, { leadId: 9, summary: SUMMARY, summaryMd5: 'a'.repeat(32) });
  assertEquals(r.value, { manufacturing: true, installation: false, maintenance: false, design: false });
  // A model that claims installation with words the summary does not contain is refused, re-asked, and still refused:
  // no reading is invented from it.
  const bad = { answer: 'They install.', decision: { fields: { installation: { value: 'install', evidence: 'we install on site' } } } };
  const m2 = mock({ synth: [bad, bad, bad] });
  assertEquals((await capabilityKinds(m2.deps, { leadId: 9, summary: SUMMARY, summaryMd5: 'a'.repeat(32) })).value, null);
});
Deno.test('capabilities held: no guess, queued under sql.fn_supplier_twin with the lead and the summary md5', async () => {
  const m = mock({ hold: true });
  const r = await capabilityKinds(m.deps, { leadId: 9, summary: SUMMARY, summaryMd5: 'a'.repeat(32) });
  assertEquals(r.value, null);
  const [h] = m.held();
  assertEquals([h.p_surface, h.p_dedupe_key, h.p_subject], ['sql.fn_supplier_twin', 'supplier_twin:9:' + 'a'.repeat(32), { lead_id: 9, summary_md5: 'a'.repeat(32) }]);
});

// ── sql.fn_supplier_portfolio_gaps ──
const CANDS = [{ key: 'gypsum.partitions', label: 'Gypsum partitions' }, { key: 'gypsum.ceilings', label: 'False ceilings' }];
Deno.test('own word: the service it names, or none', async () => {
  let m = mock({ synth: [{ answer: 'The word names false ceilings.', decision: { choice: 'gypsum.ceilings' } }] });
  assertEquals((await ownWordService(m.deps, { supplierId: 5, word: 'أسقف مستعارة', candidates: CANDS })).value, 'gypsum.ceilings');
  m = mock({ synth: [{ answer: 'The phrase names several services at once.', decision: { choice: 'none' } }] });
  assertEquals((await ownWordService(m.deps, { supplierId: 5, word: 'gypsum, ceilings and paint', candidates: CANDS })).value, 'none');
});
Deno.test('own word held: queued under sql.fn_supplier_portfolio_gaps with the supplier and the word', async () => {
  const m = mock({ hold: true });
  assertEquals((await ownWordService(m.deps, { supplierId: 5, word: 'partitions', candidates: CANDS })).value, null);
  const [h] = m.held();
  assertEquals([h.p_surface, h.p_dedupe_key, h.p_subject], ['sql.fn_supplier_portfolio_gaps', 'own_word:5:partitions', { supplier_id: 5, word: 'partitions' }]);
});
Deno.test('readSupplierProfile: records each reading, held ones as held with their queue id; a word with no candidate is "none" without a model', async () => {
  const due = { capability: { summary: SUMMARY, summary_md5: 'b'.repeat(32) }, own_words: ['partitions'], candidates: CANDS };
  let m = mock({ hold: true, rpc: { fn_supplier_readings_due: due } });
  assertEquals(await readSupplierProfile(m.deps, 5), { read: 0, held: 2 });
  const cap = m.rpcs.find(([f]) => f === 'fn_supplier_capability_reading_record')![1];
  assertEquals([cap.p_kinds, cap.p_held_id], [null, 77]);
  const word = m.rpcs.find(([f]) => f === 'fn_supplier_own_word_reading_record')![1];
  assertEquals([word.p_reasoned, word.p_service_key, word.p_held_id], [false, null, 77]);

  m = mock({ hold: true, rpc: { fn_supplier_readings_due: { capability: null, own_words: ['x-ray shielding'], candidates: [] } } });
  assertEquals(await readSupplierProfile(m.deps, 5), { read: 1, held: 0 });
  assertEquals(m.held().length, 0);
  const none = m.rpcs.find(([f]) => f === 'fn_supplier_own_word_reading_record')![1];
  assertEquals([none.p_reasoned, none.p_service_key], [true, null]);
});

// ── sql.trg_quote_quality ──
const DUE = { content_md5: 'c'.repeat(32), spec_group: 'glazing', text: 'Clear tempered glass 10mm, 2400 x 1200, aluminium frame powder coated.',
  aspects: [{ aspect: 'glass', label: 'Glass type & thickness' }, { aspect: 'frame', label: 'Frame material & finish' }, { aspect: 'size', label: 'Dimensions' }] };
Deno.test('quote aspects: stated aspects are recorded by key; an aspect the words merely resemble is not', async () => {
  const m = mock({ synth: [{ answer: 'Glass and frame are stated; the dimensions are stated too.', decision: { fields: {
    glass: { value: 'tempered glass 10mm', evidence: 'Clear tempered glass 10mm' },
    frame: { value: 'aluminium frame powder coated', evidence: 'aluminium frame powder coated' } } } }], rpc: { fn_quote_aspects_due: DUE } });
  assertEquals(await reasonQuoteAspects(m.deps, 'q-1'), { status: 'reasoned', present: ['glass', 'frame'] });
  const rec = m.rpcs.find(([f]) => f === 'fn_quote_aspect_reading_record')![1];
  assertEquals([rec.p_present, rec.p_content_md5], [['glass', 'frame'], 'c'.repeat(32)]);
});
Deno.test('quote aspects held: recorded as held (the verdict stays needs_reasoning), queued under sql.trg_quote_quality', async () => {
  const m = mock({ hold: true, rpc: { fn_quote_aspects_due: DUE } });
  assertEquals(await reasonQuoteAspects(m.deps, 'q-1'), { status: 'held' });
  const rec = m.rpcs.find(([f]) => f === 'fn_quote_aspect_reading_record')![1];
  assertEquals([rec.p_present, rec.p_held_id], [null, 77]);
  const [h] = m.held();
  assertEquals([h.p_surface, h.p_dedupe_key, h.p_subject], ['sql.trg_quote_quality', 'quote_aspects:q-1:' + 'c'.repeat(32), { quote_id: 'q-1', content_md5: 'c'.repeat(32) }]);
});
Deno.test('quote aspects: nothing due -> no model, nothing recorded', async () => {
  const m = mock({});
  assertEquals(await reasonQuoteAspects(m.deps, 'q-2'), { status: 'none_due' });
  assertEquals(m.rpcs.map(([f]) => f), ['fn_quote_aspects_due']);
});
