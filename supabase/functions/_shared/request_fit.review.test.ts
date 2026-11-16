// request_fit.review.test.ts — the nine findings of the independent review of the comparison branch (15 Nov 2026,
// REVIEW compare @ 4f1ef3b6b), each proved here against the code it found wrong. Seat: sales_engineer.
// Every test fails on 4f1ef3b6b (the commit the review read) and passes on the fix.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/request_fit.review.test.ts
// The other trades' requests are written with the spec keys the live trade_spec_checklist uses (the review read them by
// SELECT): spec_existing_make, spec_vehicle_make_model_and_year, existing warranty, waste removal, "or equivalent" lists,
// pipe material, "not in scope", survey keys.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { INQUIRY_A, journeyA, NOW, QUOTES_A, SUPPLIER_NAMES } from './request_fit.journey_a.fixture.ts';
import { annotateTechnical, enforceFit, fitQuote, hiddenBrandPhrases, hideBrandForModel, hideBrandPhrases, mayRaisePoints, pointsHandoff, recommendation, requestRequirements, siteVisitAsked, withAnswers, type QuoteFit } from './request_fit.ts';
import { generaliseLine } from './quote_generalise.ts';
import { compareDocument } from './quote_documents.ts';
import { deterministicCompare } from '../quote_compare/deterministic.ts';
import { ctxOfQuote, generaliseQuoteTerms } from './quote_generalise.ts';

const cell = (value: string) => ({ value, flag: 'stated' });
const reqOf = (category: string, spec: Record<string, unknown>) => requestRequirements({ category, spec });
const codes = (category: string, spec: Record<string, unknown>) => reqOf(category, spec).map((r) => r.code);
const line = (description: string, extra: Record<string, unknown> = {}) => ({ line_no: 1, description, specification: null, brand: null, qty: 1, unit: 'nos', ...extra });

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('1. TR is written only for HVAC capacities, read with trOf(); other units stay as the supplier wrote them', () => {
  const tech = (trade: string, values: Record<string, string>, key = 'capacity') => annotateTechnical({ suppliers: Object.keys(values), lines: [{ line_no: 1, item: 'Supply of unit', attributes: [{ key, requested: null, values: Object.fromEntries(Object.entries(values).map(([s, v]) => [s, cell(v)])) }] }] }, [], {}, trade, 'en');
  // the review's LOCAL cases: "20 litres" -> "20.0 TR", "48 V, 200 Ah" -> "48.0 TR"
  const water = tech('plumbing', { 'Supplier A': '20 litres' });
  assertEquals(water.lines[0].attributes[0].values['Supplier A'].value, '20 litres');
  const battery = tech('general', { 'Supplier A': '48 V, 200 Ah' });
  assertEquals(battery.lines[0].attributes[0].values['Supplier A'].value, '48 V, 200 Ah');
  // HVAC: "24000 BTU" is 2.0 TR, never "24000.0 TR"; a bare number is TR under the TR key only
  const hvac = tech('hvac', { 'Supplier A': '24000 BTU', 'Supplier B': '2 ton', 'Supplier C': '18 kW' });
  assertEquals(Object.values(hvac.lines[0].attributes[0].values).map((c) => c.value), ['2.0 TR', '2.0 TR', '18 kW']);
  const bare = tech('hvac', { 'Supplier A': '1.5', 'Supplier B': '24000 BTU' }, 'capacity_tr');
  assertEquals(Object.values(bare.lines[0].attributes[0].values).map((c) => c.value), ['1.5 TR', '2.0 TR']);
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('2. a service trade keeps its spec rows; only product attributes that do not apply are dropped', () => {
  const vals = (v: string) => ({ 'Supplier A': cell(v), 'Supplier B': cell(v) });
  const t = annotateTechnical({ suppliers: ['Supplier A', 'Supplier B'], lines: [
    { line_no: 1, item: 'Deep cleaning of the villa', attributes: [{ key: 'method', requested: 'Steam and dry', values: vals('Steam') }, { key: 'products', requested: 'Eco-certified', values: vals('Eco-certified') }, { key: 'brand', requested: null, values: vals('Karcher') }] },
    { line_no: 2, item: 'Maintenance contract, monthly', attributes: [{ key: 'crew', requested: '3 cleaners', values: vals('3') }] },
    { line_no: 3, item: 'Testing of the extraction fans', attributes: [{ key: 'method', requested: 'Airflow reading', values: vals('Anemometer') }] },
  ] }, [], {}, 'cleaning', 'en');
  assertEquals(t.lines.length, 3, 'the review: [0 lines kept, 3 dropped]');
  assertEquals((t as { scope_lines_dropped?: number }).scope_lines_dropped, 0);
  assertEquals(t.lines[0].attributes.map((a) => a.key), ['method', 'products'], 'the brand of a service line with nothing asked is dropped');
  // HVAC (journey A) still drops the removal, piping, service and testing lines: their only attributes are product ones
  const { analysis: a } = journeyA('en');
  assertEquals([a.technical.lines.length, a.technical.scope_lines_dropped], [2, 4]);
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('3. other trades get no hard requirement the intake did not record as his requirement for what is supplied', () => {
  // auto parts: the vehicle make is the car the part is for, not a brand list; a Bosch part does not fail
  const auto = reqOf('auto_parts', { spec_vehicle_make_model_and_year: 'Toyota Land Cruiser 2019', spec_part_type: 'Brake pads, front' });
  assertEquals(auto.map((r) => r.code), []);
  const bosch = fitQuote(auto, { quote: {}, lines: [line('Front brake pads', { brand: 'Bosch' })], now: NOW, trade: 'branded_goods' });
  assertEquals(bosch.hard_fails, []);
  // elevators: the existing make, the existing warranty and the removal of the old equipment are not requirements
  assertEquals(codes('elevators', { spec_existing_make: 'Otis', spec_existing_warranty_status: 'ended 3 years ago', spec_old_equipment_removal: 'Yes, remove the old machine', spec_number_of_stops: '6' }), []);
  // electrical: waste removal is not "the old units"; "Schneider or ABB or equivalent" is soft and an equivalent passes
  const elec = reqOf('electrical', { spec_waste_removal: 'Yes, take away all waste', spec_brand_preference: 'Schneider or ABB or equivalent' });
  assertEquals(elec.map((r) => [r.code, r.hard]), [['brand_list', false]]);
  const legrand = fitQuote(elec, { quote: {}, lines: [line('Distribution board 12 way', { brand: 'Legrand' })], now: NOW, trade: 'electrical' });
  assertEquals([legrand.cells.brand_list.status, legrand.hard_fails.length], ['meets', 0]);
  // demolition: waste and debris removal are not "the old units"
  assertEquals(codes('demolition', { spec_waste_removal: 'Yes', spec_debris_disposal: 'To the municipality dump', spec_removal_of_fixtures: 'All fixtures' }), []);
  const demo = fitQuote(reqOf('demolition', { spec_waste_removal: 'Yes' }), { quote: {}, lines: [line('Demolition of internal walls')], now: NOW, trade: 'demolition' });
  assertEquals(demo.hard_fails, []);
  // fire fighting: the pipe material is not a copper allowance
  assertEquals(codes('fire_fighting', { spec_pipe_material: 'Black steel, schedule 40', spec_sprinkler_heads: '120' }), []);
  // batteries: "Inverter not in scope" is not a hard "Inverter units"
  assertEquals(codes('batteries', { spec_inverter: 'Inverter not in scope', spec_capacity: '48 V, 200 Ah' }), []);
  // cleaning: a survey key is not a site-visit ask, and "no preference" is no brand
  const cleaning = { spec_site_survey_done: 'Yes, surveyed last week', spec_products_brand: 'No preference' };
  assertEquals(codes('cleaning', cleaning), []);
  assertEquals(siteVisitAsked(cleaning), false);
  assertEquals(siteVisitAsked({ survey_findings: 'Ceiling void 600 mm' }), false);
  assert(siteVisitAsked(INQUIRY_A.spec), 'journey A still names its site visit');
  // HVAC itself: an existing unit's make is no brand list; journey A's thirteen are unchanged
  assertEquals(codes('hvac', { spec_existing_unit_brand: 'Carrier', spec_refrigerant: 'R32' }), ['refrigerant']);
  assertEquals(requestRequirements(INQUIRY_A).length, 13);
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('4. the PDF scores table reads the date and the fit from request_fit on the model path too; its note matches', () => {
  const { analysis: rules } = journeyA('en');
  // a model-shaped analysis: integer scores, no meets_date, no engine
  const model = structuredClone(rules);
  delete model.engine;
  model.quotes = model.quotes.map((q: Record<string, unknown>) => ({ label: q.label, price: q.price, price_score: 4, delivery_score: 5, quality_score: 5, score_reason: 'x', flags: [] }));
  const d = compareDocument({ analysis: model, inquiry: INQUIRY_A as never, lang: 'en', maskNames: SUPPLIER_NAMES, date: '15 November 2026' });
  // deno-lint-ignore no-explicit-any
  const blocks = (d.body as any).blocks as any[];
  const table = blocks.find((b) => b.t === 'table' && JSON.stringify(b.head).includes('Meets your request'));
  assert(table, 'the scores table is there');
  assert(!JSON.stringify(table.head).includes('Overall'), 'no computed overall on the model path');
  const json = JSON.stringify(table.rows);
  assert(!json.includes('Not stated'), 'the review: "Done by your date: Not stated" for three quotes that met it');
  assertEquals(table.rows.map((r: unknown[]) => (r[4] as { text: string }).text), ['Yes', 'Yes', 'Yes']);
  assert(json.includes('11 of 13 (4.6 / 5)') && json.includes('9 of 13 (4.0 / 5)'), 'the fit score, not the model\'s 5');
  assert(!json.includes('(5.0 / 5)'), 'the review: "9 of 13 (5.0 / 5)"');
  const note = blocks[blocks.indexOf(table) + 1];
  assert(note.t === 'note' && /adviser's judgement of value for money/.test(note.text) && !/5 × the lowest price/.test(note.text), 'the model path\'s method');
  assert(!JSON.stringify(blocks).includes('Price counts for half, scored in proportion to the lowest price'), 'section 2 states the model path\'s method');
  // the rules path keeps its proportional method
  const r = compareDocument({ analysis: rules, inquiry: INQUIRY_A as never, lang: 'en', maskNames: SUPPLIER_NAMES, date: '15 November 2026' });
  assert(JSON.stringify(r.body).includes('5 × the lowest price'));
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('5. enforceFit: a passing quote outside the model\'s top 3 is put first, labels match loosely, and the prose follows', () => {
  const { analysis: rules, fits } = journeyA('en');
  const prices = { 'Supplier A': 12279, 'Supplier B': 15750, 'Supplier C': 17957 };
  const opts = { rules, prices };
  // (a) B left out of the model's shortlist
  const m1 = { top3: [{ rank: 1, label: 'Supplier A', why: 'Cheapest.', tradeoff: '' }, { rank: 2, label: 'Supplier C', why: 'Dearest.', tradeoff: '' }],
    best_value_label: 'Supplier A', bottom_line: 'We recommend Supplier A.', best_value_reason: 'Supplier A is the best value.', advice: 'Go with Supplier A.' };
  enforceFit(m1, fits, 'en', opts);
  assertEquals(m1.top3.map((t) => [t.rank, t.label]), [[1, 'Supplier B'], [2, 'Supplier C'], [3, 'Supplier A']]);
  assertEquals(m1.best_value_label, 'Supplier B');
  // (b) "A" / "C" match their labels
  const m2 = { top3: [{ rank: 1, label: 'A', why: 'Cheapest.', tradeoff: '' }, { rank: 2, label: 'supplier b', why: 'x', tradeoff: '' }], bottom_line: 'We recommend Supplier A.' };
  enforceFit(m2, fits, 'en', opts);
  assertEquals(m2.top3.map((t) => t.label), ['Supplier B', 'Supplier A']);
  // (c) nothing the model wrote for the old first survives where it would contradict the order
  for (const m of [m1, m2] as Record<string, unknown>[]) {
    assert(!/recommend Supplier A|Supplier A is the best|Go with Supplier A/.test(JSON.stringify([m.bottom_line, m.best_value_reason, m.advice])), JSON.stringify(m));
    assert(String(m.bottom_line).startsWith('We place Supplier B first: Supplier A fails your installation warranty'));
    assert(String(m.bottom_line).includes('We recommend Supplier B'));
  }
  assertEquals(m1.best_value_reason, (m1.top3[0] as { why: string }).why);
  // a model ranking that already puts a passing quote first is left as the model wrote it
  const m3 = { top3: [{ rank: 1, label: 'Supplier C', why: 'Mine.', tradeoff: '' }, { rank: 2, label: 'Supplier B', why: 'y', tradeoff: '' }], bottom_line: 'C is best.' };
  enforceFit(m3, fits, 'en', opts);
  assertEquals([m3.top3[0].label, m3.top3[0].why, m3.bottom_line], ['Supplier C', 'Mine.', 'C is best.']);
});

Deno.test('5c. enforceFit keeps the rules ranking\'s first keys: a passing quote with no price, or expired, is not pulled first', () => {
  const { fits } = journeyA('en');
  const model = () => ({ top3: [{ rank: 1, label: 'Supplier A', why: 'Cheapest.', tradeoff: '' }, { rank: 2, label: 'Supplier C', why: 'x', tradeoff: '' }], bottom_line: 'A.' });
  // B (passing) states no price: C (passing, priced) is put first, not B
  const m1 = model();
  enforceFit(m1, fits, 'en', { prices: { 'Supplier A': 12279, 'Supplier B': null, 'Supplier C': 17957 } });
  assertEquals(m1.top3.map((t) => t.label), ['Supplier C', 'Supplier A']);
  // B and C passing, B expired: C first
  const m2 = model();
  enforceFit(m2, fits, 'en', { prices: { 'Supplier A': 12279, 'Supplier B': 15750, 'Supplier C': 17957 }, expired: { 'Supplier B': true } });
  assertEquals(m2.top3[0].label, 'Supplier C');
  // every passing quote unpriced: the priced failing quote keeps its place, labelled as failing
  const m3 = model();
  enforceFit(m3, fits, 'en', { prices: { 'Supplier A': 12279, 'Supplier B': null, 'Supplier C': null } });
  assertEquals(m3.top3[0].label, 'Supplier A');
  assert(m3.top3[0].tradeoff.startsWith('Fails your installation warranty'));
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('5b. a hard requirement the quote does not state never outranks a quote that states it meets it', () => {
  const reqs = requestRequirements(INQUIRY_A);
  const base = QUOTES_A[1];
  // a lump sum (no lines) that states no warranty, cheaper than an itemised quote that states every hard requirement
  const lump = fitQuote(reqs, { quote: { ...base, warranty: null, terms_spec: { delivery: base.terms_spec.delivery, installation: base.terms_spec.installation } }, lines: [], now: NOW, trade: 'hvac' });
  const full = fitQuote(reqs, { quote: base, lines: base.items, now: NOW, trade: 'hvac' });
  assert(lump.hard_open.length > 0 && lump.hard_fails.length === 0 && full.hard_open.length === 0);
  const labelled = [{ label: 'Supplier A', price: 9000, fit: lump }, { label: 'Supplier B', price: 15750, fit: full }];
  const a = deterministicCompare(labelled as never, 'en');
  assertEquals(a.top3.map((t: { label: string }) => t.label), ['Supplier B', 'Supplier A']);
  // and on the model's ranking
  const m = { top3: [{ rank: 1, label: 'Supplier A', why: 'Cheapest by far.', tradeoff: '' }, { rank: 2, label: 'Supplier B', why: 'x', tradeoff: '' }], bottom_line: 'Supplier A is the best value.' };
  enforceFit(m, { 'Supplier A': lump, 'Supplier B': full }, 'en', { rules: a, prices: { 'Supplier A': 9000, 'Supplier B': 15750 } });
  assertEquals(m.top3.map((t) => t.label), ['Supplier B', 'Supplier A']);
  assert(m.bottom_line.startsWith('We place Supplier B first: it states everything you asked for, and Supplier A does not state'), m.bottom_line);
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('6. the open points go to the sales engineer as ONE hand-over per quote; the customer is promised only that QuotesDone asks', () => {
  // FINAL REVIEW FIX 1 (CEO, ruling 1696): no code-written engineer message; a hand-over filed through fn_seat_handoff.
  const { fits } = journeyA('en');
  const d = compareDocument({ analysis: journeyA('en').analysis, inquiry: INQUIRY_A as never, lang: 'en', maskNames: SUPPLIER_NAMES, date: '15 November 2026' });
  const json = JSON.stringify(d.body);
  assert(json.includes('Points QuotesDone asks the supplier to confirm'));
  assert(json.includes('QuotesDone asks the supplier to confirm these points'));
  assert(!/settles|Ask before you reveal|put them to the suppliers|before you reveal, with your identity hidden/.test(json), 'nothing promises more than an ask, nor tells him to ask');
  const ar = JSON.stringify(compareDocument({ analysis: journeyA('ar').analysis, inquiry: INQUIRY_A as never, lang: 'ar', maskNames: SUPPLIER_NAMES, date_ar: '15 نوفمبر 2026' }).body);
  assert(ar.includes('نقاط تطلب QuotesDone من المورّد تأكيدها') && !ar.includes('تتولاها') && !ar.includes('ما تسأل عنه قبل الكشف'));
  assert(!/settles/.test(String(journeyA('en').analysis.advice || '')), 'the advice promises only the ask');
  // ONE hand-over per quote, through the estate's door, keyed on the quote (fn_seat_handoff opens one per kind and subject)
  const h = pointsHandoff(fits['Supplier A'], { inquiry_id: INQUIRY_A.id, quote_id: 'q-a', label: 'Supplier A' })!;
  assertEquals([h.p_from, h.p_to, h.p_type, h.p_subject_table, h.p_subject_id], ['sales_engineer', 'sales_engineer', 'comparison.points', 'quotes', 'q-a']);
  assertEquals(h.p_payload.points.length, 3);
  assert(typeof h.p_payload.summary === 'string' && h.p_payload.summary.length > 0, 'the seat reads a summary (fn_seat_handoff_notes)');
  for (const p of h.p_payload.points) {
    assert(p.key.startsWith('comparison:') && !/[؀-ۿ]/.test(p.supplier) && !/\bYou asked\b/.test(p.supplier), p.supplier);
    // the words the seat and the supplier read (the ids are ours): no supplier, no customer, no site
    for (const n of [...SUPPLIER_NAMES, 'zzd3m0aa', 'villa']) assert(!JSON.stringify([p, h.p_payload.summary, h.p_payload.waiting_for]).toLowerCase().includes(n.toLowerCase()), `"${n}" in the hand-over`);
  }
  // the same points give the same keys on every view, so the handler raises each once
  assertEquals(pointsHandoff(fits['Supplier A'], { inquiry_id: INQUIRY_A.id, quote_id: 'q-a', label: 'Supplier A' })!.p_payload.points.map((p) => p.key), h.p_payload.points.map((p) => p.key));
  // nothing to hand over: no hand-over
  assertEquals(pointsHandoff({ ...fits['Supplier A'], asks: [] }, { inquiry_id: INQUIRY_A.id, quote_id: 'q-a', label: 'Supplier A' }), null);
  // NEVER AFTER A REVEAL OR ONCE THE REQUEST IS CONCLUDED (FIX 1 iv)
  assert(mayRaisePoints({ status: 'quoting' }, false));
  for (const st of ['revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost']) assert(!mayRaisePoints({ status: st }, false), st);
  assert(!mayRaisePoints({ status: 'quoting' }, true), 'a reveal on the request stops it');
  // HIS ANSWER COMES BACK: an answered point shows his words; an unanswered one is "not answered yet"
  const k0 = h.p_payload.points[0].key;
  const answered = withAnswers(fits['Supplier A'], { [k0]: { state: 'answered', answer: 'The price is final; no site visit is needed.' } });
  assertEquals(answered.asks.map((x) => x.state), ['answered', 'asked', 'asked']);
  assertEquals(answered.asks[0].answer, 'The price is final; no site visit is needed.');
  const a = journeyA('en').analysis; const rf = a.request_fit;
  rf.quotes = rf.quotes.map((q: { label: string }) => q.label === 'Supplier A' ? { ...q, asks: answered.asks.map(({ en, ar, state, answer }) => ({ en, ar, state, answer })) } : q);
  const page = JSON.stringify(compareDocument({ analysis: a, inquiry: INQUIRY_A as never, lang: 'en', maskNames: SUPPLIER_NAMES, date: '15 November 2026' }).body);
  assert(page.includes('The price is final; no site visit is needed.') && page.includes('Not answered yet'), 'the answer is on the page beside its point');
  // the customer's analysis carries his copy only
  assert(!JSON.stringify(journeyA('en').analysis.request_fit).includes('Please confirm'));
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('8. the date cell carries the generalised lead time, never the raw one, and is fully Arabic in Arabic', () => {
  const reqs = requestRequirements(INQUIRY_A);
  const q = { ...QUOTES_A[1], lead_time: '10 days, Daikin stock at ZZ DEMO Cool Breeze HVAC hvac 8288bec3 warehouse', terms_spec: { ...QUOTES_A[1].terms_spec, delivery: undefined } };
  const ctx = ctxOfQuote(q.items, [q.supplier_name]);
  const shown = generaliseQuoteTerms({ lead_time: q.lead_time }, ctx).lead_time;
  const f = fitQuote(reqs, { quote: { ...q, lead_time_shown: shown }, lines: q.items, now: NOW, trade: 'hvac' });
  assert(!/Daikin|Cool Breeze/.test(f.cells.date.shown.en), f.cells.date.shown.en);
  assert(f.cells.date.shown.en.startsWith('Yes: 10 days'), f.cells.date.shown.en);
  // with no generalised text, the days only
  const bare = fitQuote(reqs, { quote: q, lines: q.items, now: NOW, trade: 'hvac' });
  assertEquals(bare.cells.date.shown.en, 'Yes: 10 days');
  // Arabic: "نعم: 5 days from LPO" was the review's case
  const { fits } = journeyA('ar');
  for (const l of ['Supplier A', 'Supplier B', 'Supplier C']) assert(!/[A-Za-z]/.test(fits[l].cells.date.shown.ar), fits[l].cells.date.shown.ar);
  assertEquals(fits['Supplier A'].cells.date.shown.ar, 'نعم: 5 أيام');
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('9. no listed brand is identifiable before the reveal (ledger 1588)', () => {
  // journey A: Gree is his only economy Chinese brand; Daikin and Mitsubishi Electric are both premium Japanese
  const { analysis: a, fits } = journeyA('en');
  // per REQUEST (final review FIX 2a): B and C are hidden too, or A is Gree by elimination
  assertEquals([fits['Supplier A'].brand.generic, fits['Supplier A'].brand.hidden, fits['Supplier B'].brand.hidden, fits['Supplier C'].brand.hidden], [null, true, true, true]);
  const brandCells = a.technical.lines.flatMap((l: { attributes: { key: string; values: Record<string, { value: string; note?: string | null }> }[] }) => l.attributes.filter((x) => x.key === 'brand').map((x) => x.values['Supplier A']));
  assert(brandCells.length && brandCells.every((c: { value: string; note?: string | null }) => c.value === 'As you asked; the brand is shown after the reveal' && !c.note), JSON.stringify(brandCells));
  for (const l of ['Supplier B', 'Supplier C']) {
    const cs = a.technical.lines.flatMap((x: { attributes: { key: string; values: Record<string, { value: string }> }[] }) => x.attributes.filter((y) => y.key === 'brand').map((y) => y.values[l]));
    assert(cs.every((c: { value: string }) => c.value === 'As you asked; the brand is shown after the reveal'), l + ' ' + JSON.stringify(cs));
  }
  assert(!/economy Chinese|made in China|premium Japanese|made in Japan/i.test(JSON.stringify(a)), 'no listed tier or origin reaches the analysis');
  assert(!/صينية|صنع في الصين|يابانية|صنع في اليابان/.test(JSON.stringify(journeyA('ar').analysis)), 'nor the Arabic analysis');
  // a single-brand list always identifies the make
  const one = requestRequirements({ category: 'hvac', spec: { spec_brand_preference_or_equivalent_tier: 'Daikin only' } });
  const f = fitQuote(one, { quote: {}, lines: QUOTES_A[1].items, now: NOW, trade: 'hvac' });
  assertEquals([f.cells.brand_list.status, f.cells.brand_list.shown.en, f.brand.generic], ['meets', 'As you asked; the brand is shown after the reveal', null]);
  const rec = recommendation({ label: 'Supplier B', price: 1, fit: f }, [], 'en');
  assert(!/premium|Japanese/.test(rec.bottom), rec.bottom);
  // a brand he did not name is still said plainly (it narrows nothing to one of his)
  const midea: QuoteFit = fitQuote(one, { quote: {}, lines: [line('Wall split 1.5 TR, supply and install', { brand: 'Midea' })], now: NOW, trade: 'hvac' });
  assert(midea.cells.brand_list.shown.en.startsWith('No: '));
});

// ---------------------------------------------------------------------------------------------------------------------------
Deno.test('9b. journey A: A, B and C all read "as you asked"; the model never reads a listed tier or origin; the backstop takes every phrasing', () => {
  const { analysis: a, fits } = journeyA('en');
  // FIX 2a: decided per request, so none of the three can be told apart by tier and origin
  assertEquals(['Supplier A', 'Supplier B', 'Supplier C'].map((l) => fits[l].cells.brand_list.shown.en), Array(3).fill('As you asked; the brand is shown after the reveal'));
  assertEquals(['Supplier A', 'Supplier B', 'Supplier C'].map((l) => fits[l].cells.brand_list.shown.ar), Array(3).fill('كما طلبت؛ تظهر العلامة بعد الكشف'));
  assert(a.bottom_line.startsWith('We recommend Supplier B: one of your listed brands, and it meets'), a.bottom_line);
  // a list where no tier and origin is unique hides nothing (it narrows nothing to one make)
  const two = requestRequirements({ category: 'hvac', spec: { spec_brand_preference_or_equivalent_tier: 'Daikin or Mitsubishi Electric' } });
  assertEquals(fitQuote(two, { quote: {}, lines: QUOTES_A[1].items, now: NOW, trade: 'hvac' }).cells.brand_list.shown.en, 'Yes: premium Japanese brand');
  // FIX 2b, the model's input: A's lines as quote_compare generalises them, then hideBrandForModel
  const qA = QUOTES_A.find((q) => q.supplier_id === 9002)!;
  const ph = hiddenBrandPhrases(fits['Supplier A'], qA.items as never, 'hvac');
  const ctx = ctxOfQuote(qA.items, [qA.supplier_name]);
  const generalised = { label: 'Supplier A', items: qA.items.map((x) => generaliseLine({ ...x, country_of_origin: 'China' }, ctx)), notes: 'Units are Chinese-made, economy brand from China.' };
  assert(/economy Chinese brand/.test(JSON.stringify(generalised)), 'the generaliser alone leaves the tier and origin (the review\'s finding)');
  const model = JSON.stringify(hideBrandForModel(generalised, ph));
  assert(!/economy|Chinese|China|country_of_origin/i.test(model), model);
  assert(model.includes('as the customer asked (shown after the reveal)'));
  // the backstop: the review's 15 English and 4 Arabic phrasings (and the three it already caught), and no "an brand"
  const en = ['Supplier A quotes an economy Chinese brand.', 'A uses a Chinese economy brand.', 'A quotes economy-tier Chinese units.', 'A is a budget Chinese brand.', 'A units are Chinese-made.', 'A: China-made compressors.', 'A: origin China.', 'A: country of origin: China', 'A sources from China.', 'A: made in the PRC.', 'A: Made In China', 'A: manufactured in China.', 'A quotes an economy brand from China.', 'A quotes a Chinese brand.', 'A is the only economy option on your list.', 'A is the cheaper non-Japanese brand on your list.', 'A: economy  Chinese brand (double space)', 'A: Economy Chinese Brand'];
  const all = [ph, hiddenBrandPhrases(fits['Supplier B'], QUOTES_A.find((q) => q.supplier_id !== 9002)!.items as never, 'hvac')];
  for (const t of en) {
    const out = hideBrandPhrases({ x: t }, all).x as string;
    assert(!/economy|budget|chinese|china|prc|japanese/i.test(out), `${t} -> ${out}`);
    assert(!/\ban brand\b/i.test(out), `${t} -> ${out}`);
  }
  const arT = ['يقدّم المورّد A علامة صينية اقتصادية', 'منشأ صيني', 'صنع في الصين', 'مصنوع في الصين', 'بلد المنشأ: الصين'];
  for (const t of arT) { const out = hideBrandPhrases({ x: t }, all).x as string; assert(!/صيني|الصين|اقتصادية/.test(out), `${t} -> ${out}`); }
  // what is not about a hidden brand stays as written
  assertEquals(hideBrandPhrases({ x: 'Supplier D quotes a premium German brand; the UAE market range is AED 15,000-19,000.' }, all).x, 'Supplier D quotes a premium German brand; the UAE market range is AED 15,000-19,000.');
});
