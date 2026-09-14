// The hold decision. The required set is the customer's inquiry first (founder_instruction #142,
// #159), then the trade's general standard: material spec per line, delivery, installation and
// warranty unless the customer explicitly said not needed, the customer's own components, and the
// price excluding VAT — each missing, and each not required.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/assess.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessQuote, holdNotice, requirementsOf, SEAT_LABEL, validateLineValue, validateTerm, type Line, type Requirements, type Terms } from './assess.ts';
import { TRADES } from './model.ts';

const L = (line_no: number, description: string, x: Partial<Line> = {}): Line => ({ line_no, description, ...x });
// Every fixture states its ex-VAT price unless a test is about that price; (5) below removes it.
const aq = (i: Parameters<typeof assessQuote>[0]) => assessQuote({ ...i, terms: { price_ex_vat: 20000, ...i.terms } });
const FITOUT: Line[] = [
  L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { qty: 2, unit_price: 3000, amount: 6000 }),
  L(2, 'Gypsum false ceiling 12.5mm standard gypsum board on 0.6mm GI channels', { amount: 9000 }),
  L(3, 'Preliminaries and site setup', { amount: 1500 }),
  L(4, 'Painting walls Jotun Fenomastic 2 coats matt', { amount: 4000 }),
  L(5, 'Installation labour', { install: 1500, amount: 1500 }),
];
const TERMS: Terms = { lead_time: '4 weeks from approval', warranty: '1 year on workmanship and materials', scope: 'Supply and installation of all fit-out works' };
const codes = (a: ReturnType<typeof assessQuote>) => a.missing.map((m) => (m.scope === 'line' ? `${m.line_no}:${m.attr}` : m.attr));
// The intake's stored object, version 1 (docs/contracts/intake_answers.md).
const R = (x: Partial<NonNullable<Requirements>>): Requirements => ({ version: 1, ...x });
const NONE_NEEDED = R({ installation: { required: 'no' }, warranty: { required: 'no' } });

Deno.test('the intake answers are read where the intake stores them', () => {
  assertEquals(requirementsOf({ customer_requirements: { installation: { required: 'yes' } } })?.installation?.required, 'yes');
  assertEquals(requirementsOf({ requirements: { warranty: { required: 'no' } } })?.warranty?.required, 'no');
  assertEquals(requirementsOf({ summary: 'x' }), null);
});

Deno.test('a fit-out quote that states every detail passes; each line is read as its own trade', () => {
  const a = aq({ category: 'fitout', lines: FITOUT, terms: TERMS });
  assertEquals(codes(a), []);
  assertEquals(a.lines.map((l) => l.trade), ['joinery', 'gypsum', null, 'painting', null]);
  assertEquals(a.lines[0].spec, { material: 'MDF', thickness_mm: '18', finish: 'HPL' });
});

Deno.test('(1) a line missing its material specification holds the quote and names the line and the detail', () => {
  const lines = FITOUT.map((l) => (l.line_no === 1 ? { ...l, description: 'Wardrobe MDF carcass, HPL finish' } : l));
  const a = aq({ category: 'fitout', lines, terms: TERMS });
  assertEquals(codes(a), ['1:thickness_mm']);
  assertEquals([a.missing[0].label_ar, a.missing[0].unit], ['السماكة', 'mm']);
});

Deno.test('(1) a vague value is not a specification, and a lump sum is held for itemisation', () => {
  assertEquals(codes(aq({ category: 'joinery', lines: [L(1, 'Wardrobe MDF thickness TBD, HPL')], terms: TERMS })), ['1:thickness_mm']);
  assertEquals(codes(aq({ category: 'fitout', lines: [L(1, 'Complete fit-out works as per drawings', { amount: 250000 })], terms: TERMS }))[0], 'line_items');
});

Deno.test('(2) no delivery date or lead time, or a vague one, holds the quote', () => {
  for (const lead_time of [null, '', 'ASAP', 'TBD', 'as per schedule']) assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, lead_time } })), ['delivery'], String(lead_time));
  for (const lead_time of ['21 days', '3 weeks', '30 Oct 2026', '2026-10-30', 'Ex-stock', '45 يوم عمل']) assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, lead_time } })), [], lead_time);
});

const WARDROBE = [L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { amount: 6000 })];
Deno.test('(3) installation: the customer asked for it → scope or timeline required', () => {
  const req = R({ installation: { required: 'yes' } });
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '1 year workmanship' }, requirements: req })), ['installation_included']);
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', notes: 'Installation included' }, requirements: req })), ['installation_detail']);
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', notes: 'Installation included, installation in 5 days after delivery' }, requirements: req })), []);
});

Deno.test('(3) installation: "supply only" from the customer → not required; from the supplier it is an answer', () => {
  const notReq = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '1 year workmanship' }, requirements: R({ installation: { required: 'no' } }) });
  assertEquals([codes(notReq), notReq.terms.installation.applies], [[], false]);
  const supplyOnly = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', scope: 'Supply only' } });
  assertEquals([codes(supplyOnly), supplyOnly.terms.installation.included], [[], 'no']);
});

Deno.test('(3)(4) we do not assume: "not sure" and a legacy request with no answer both require installation and warranty, whatever the trade', () => {
  const clean = [L(1, 'Deep cleaning of villa using Diversey products')];
  for (const requirements of [null, R({ installation: { required: 'not_sure' }, warranty: { required: 'not_sure' } })]) {
    assertEquals(codes(aq({ category: 'cleaning', lines: clean, terms: { lead_time: '2 days' }, requirements })), ['installation_included', 'warranty_period', 'warranty_coverage'], JSON.stringify(requirements));
  }
  assertEquals(codes(aq({ category: 'cleaning', lines: clean, terms: { lead_time: '2 days' }, requirements: NONE_NEEDED })), []);
});

Deno.test('(4) warranty: missing period and coverage, or coverage alone, holds the quote; a short one is stated, not held', () => {
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: '' } })), ['warranty_period', 'warranty_coverage']);
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: '2 years' } })), ['warranty_coverage']);
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: 'ضمان سنتين على المصنعية والمواد' } })), []);
  // Below the customer's 24-month minimum: stated, so not held — the comparison marks it ≠ (compare.test).
  const short = aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: '12 months on workmanship' }, requirements: R({ warranty: { required: 'yes', min_months: 24 } }) });
  assertEquals([codes(short), short.terms.warranty.months], [[], 12]);
});

// Custom furniture: the customer named steel legs and had no preference for the top.
const FURNITURE = R({ installation: { required: 'no' }, warranty: { required: 'no' }, materials: [
  { component: 'top_body', label_en: 'Top or main body', label_ar: 'السطح أو الجسم الرئيسي', choice: 'no_preference', choice_en: 'No preference' },
  { component: 'legs_base', label_en: 'Legs or base', label_ar: 'الأرجل أو القاعدة', choice: 'steel', choice_en: 'Steel', choice_ar: 'حديد (ستيل)' },
] });
Deno.test('(1+) a material the customer named for a component is required on the line that names it', () => {
  const ok = aq({ category: 'custom-furniture', lines: [L(1, 'Dining table top 20mm solid oak, lacquer finish'), L(2, 'Dining table legs in stainless steel, 40mm, lacquer finish')], terms: { lead_time: '4 weeks' }, requirements: FURNITURE });
  assertEquals(codes(ok), []);
  assertEquals([ok.lines[0].spec.component_top_body, ok.lines[1].spec.component_legs_base], ['Wood', 'Steel']);
  // The legs line is no longer asked a board type: the customer's component says what material means there.
  assert(!ok.lines[1].asked.includes('material'));
  const noLegMaterial = aq({ category: 'custom-furniture', lines: [L(1, 'Dining table top 20mm solid oak, lacquer finish'), L(2, 'Dining table legs, 40mm, lacquer finish')], terms: { lead_time: '4 weeks' }, requirements: FURNITURE });
  assertEquals(codes(noLegMaterial), ['2:component_legs_base']);
  assertEquals(noLegMaterial.missing[0].label_ar, 'المادة — الأرجل أو القاعدة');
});

Deno.test('(1+) "no preference" still requires the supplier to state a value', () => {
  const a = aq({ category: 'custom-furniture', lines: [L(1, 'Dining table top 20mm, lacquer finish'), L(2, 'Dining table legs in steel, 40mm, lacquer finish')], terms: { lead_time: '4 weeks' }, requirements: FURNITURE });
  assertEquals(codes(a), ['1:component_top_body']);
});

Deno.test('(1+) a component no line names is asked of the quote as a whole', () => {
  const a = aq({ category: 'custom-furniture', lines: [L(1, 'Dining table top 20mm solid oak, lacquer finish')], terms: { lead_time: '4 weeks' }, requirements: FURNITURE });
  assertEquals(codes(a), ['component:legs_base']);
  const filled = aq({ category: 'custom-furniture', lines: [L(1, 'Dining table top 20mm solid oak, lacquer finish')], terms: { lead_time: '4 weeks', terms_spec: { components: { legs_base: { value: 'Powder-coated steel', source: 'supplier_portal' } } } }, requirements: FURNITURE });
  assertEquals(codes(filled), []);
});

Deno.test('(5) no exact price excluding VAT holds the quote', () => {
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, price_ex_vat: null } });
  assertEquals([codes(a), a.missing[0].unit], [['price_ex_vat'], 'AED']);
  assertEquals(validateTerm('price_ex_vat', 'AED 10,500'), { ok: true, value: '10500' });
});

Deno.test('the portal accepts only what the gate accepts', () => {
  const thk = TRADES.joinery.attrs.find((a) => a.code === 'thickness_mm')!;
  assertEquals(validateLineValue(thk, '18'), { ok: true, value: '18' });
  assertEquals(validateLineValue(thk, 'thick'), { ok: false, code: 'not_a_number' });
  assertEquals(validateLineValue(thk, 'TBD'), { ok: false, code: 'vague' });
  assertEquals(validateTerm('delivery', 'soon'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('warranty_period', 'long'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('installation_included', 'maybe'), { ok: false, code: 'choose_yes_or_no' });
  assertEquals(validateTerm('component:legs_base', 'Powder-coated steel'), { ok: true, value: 'Powder-coated steel' });
});

Deno.test('the supplier notice names each line and detail, in the supplier language, signed by the sales engineer', () => {
  const lines = FITOUT.map((l) => (l.line_no === 1 ? { ...l, description: 'Wardrobe MDF carcass, HPL finish' } : l));
  const a = aq({ category: 'fitout', lines, terms: { ...TERMS, lead_time: '' } });
  const ar = holdNotice(a, 'ar', 'RFQ1');
  assert(ar.body.includes('البند 1') && ar.body.includes('السماكة') && ar.body.includes(SEAT_LABEL.ar), ar.body);
  const en = holdNotice(a, 'en', 'RFQ1');
  assert(en.body.includes('Line 1') && en.body.includes('Thickness') && en.body.includes('Delivery date') && en.body.includes(SEAT_LABEL.en));
});
