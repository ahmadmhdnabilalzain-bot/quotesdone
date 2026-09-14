// The hold decision, one test per thing the founder listed: material spec per line, delivery,
// installation (if applicable), warranty (if applicable) — each missing, and each not applicable.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/assess.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessQuote, holdNotice, SEAT_LABEL, validateLineValue, validateTerm, type Line, type Terms } from './assess.ts';
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

Deno.test('a fit-out quote that states every detail passes; each line is read as its own trade', () => {
  const a = aq({ category: 'fitout', lines: FITOUT, terms: TERMS });
  assertEquals(codes(a), []);
  assertEquals(a.held, false);
  assertEquals(a.lines.map((l) => l.trade), ['joinery', 'gypsum', null, 'painting', null]);
  assertEquals(a.lines[0].spec, { material: 'MDF', thickness_mm: '18', finish: 'HPL' });
  assertEquals(a.terms.installation.included, 'yes');
  assertEquals(a.terms.warranty.period, '1 year');
});

Deno.test('(1) a line missing its material specification holds the quote and names the line and the detail', () => {
  const lines = FITOUT.map((l) => (l.line_no === 1 ? { ...l, description: 'Wardrobe MDF carcass, HPL finish' } : l));
  const a = aq({ category: 'fitout', lines, terms: TERMS });
  assertEquals(codes(a), ['1:thickness_mm']);
  assert(a.held);
  assertEquals(a.missing[0].label_ar, 'السماكة');
  assertEquals(a.missing[0].unit, 'mm');
});

Deno.test('(1) a vague value is not a specification', () => {
  const a = aq({ category: 'joinery', lines: [L(1, 'Wardrobe MDF thickness TBD, HPL')], terms: TERMS });
  assertEquals(codes(a), ['1:thickness_mm']);
});

Deno.test('(1) a lump sum with no itemised lines is held for itemisation', () => {
  const a = aq({ category: 'fitout', lines: [L(1, 'Complete fit-out works as per drawings', { amount: 250000 })], terms: TERMS });
  assertEquals(codes(a)[0], 'line_items');
});

Deno.test('(2) no delivery date or lead time, or a vague one, holds the quote', () => {
  for (const lead_time of [null, '', 'ASAP', 'TBD', 'as per schedule']) {
    const a = aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, lead_time } });
    assertEquals(codes(a), ['delivery'], String(lead_time));
  }
  for (const lead_time of ['21 days', '3 weeks', '30 Oct 2026', '2026-10-30', 'Ex-stock', '45 يوم عمل']) assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, lead_time } })), [], lead_time);
});

Deno.test('(3) installation: missing when the trade installs and nothing says whether it is included', () => {
  const lines = [L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { amount: 6000 })];
  const a = aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks', warranty: '1 year workmanship' } });
  assertEquals(codes(a), ['installation_included']);
});

Deno.test('(3) installation: included but with no scope or timeline is held for the detail', () => {
  const lines = [L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { amount: 6000 })];
  const a = aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', notes: 'Installation included' } });
  assertEquals(codes(a), ['installation_detail']);
  const b = aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', notes: 'Installation included, installation in 5 days after delivery' } });
  assertEquals(codes(b), []);
});

Deno.test('(3) installation: supply-only stated is an answer; supply-only requested makes it not applicable', () => {
  const lines = [L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { amount: 6000 })];
  const stated = aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks', warranty: '1 year workmanship', scope: 'Supply only' } });
  assertEquals(codes(stated), []);
  assertEquals(stated.terms.installation.included, 'no');
  const notReq = aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks', warranty: '1 year workmanship' }, requirements: { installation: 'not_required' } });
  assertEquals(codes(notReq), []);
  assertEquals(notReq.terms.installation.applies, false);
});

Deno.test('(3) installation does not apply to a service trade', () => {
  const a = aq({ category: 'cleaning', lines: [L(1, 'Deep cleaning of villa using Diversey products')], terms: { lead_time: '2 days' } });
  assertEquals(a.terms.installation.applies, false);
  assertEquals(codes(a), []);
});

Deno.test('(4) warranty: missing period and coverage, or coverage alone, holds the quote', () => {
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: '' } })), ['warranty_period', 'warranty_coverage']);
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: '2 years' } })), ['warranty_coverage']);
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: 'Manufacturer warranty' } })), ['warranty_period']);
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, warranty: 'ضمان سنتين على المصنعية والمواد' } })), []);
});

Deno.test('(4) warranty does not apply to cleaning, and applies to pest control only for termites', () => {
  const clean = aq({ category: 'cleaning', lines: [L(1, 'Deep cleaning of villa using Diversey products')], terms: { lead_time: '2 days' } });
  assertEquals(clean.terms.warranty.applies, false);
  const roach = aq({ category: 'pest', lines: [L(1, 'Cockroach gel bait treatment, Chemical: Maxforce gel')], terms: { lead_time: '1 day' } });
  assertEquals(codes(roach), []);
  const termite = aq({ category: 'pest', lines: [L(1, 'Pre-construction termite treatment, Chemical: Termidor')], terms: { lead_time: '1 day' } });
  assertEquals(codes(termite), ['warranty_period', 'warranty_coverage']);
});

Deno.test('(5) no exact price excluding VAT holds the quote', () => {
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, price_ex_vat: null } })), ['price_ex_vat']);
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { ...TERMS, price_ex_vat: null } });
  assertEquals([a.missing[0].unit, a.missing[0].label_ar], ['AED', 'السعر الإجمالي غير شامل ضريبة القيمة المضافة']);
  assertEquals(validateTerm('price_ex_vat', 'AED 10,500'), { ok: true, value: '10500' });
  assertEquals(validateTerm('price_ex_vat', 'incl. VAT'), { ok: false, code: 'not_a_number' });
});

Deno.test('the portal accepts only what the gate accepts', () => {
  const thk = TRADES.joinery.attrs.find((a) => a.code === 'thickness_mm')!;
  assertEquals(validateLineValue(thk, '18'), { ok: true, value: '18' });
  assertEquals(validateLineValue(thk, 'thick'), { ok: false, code: 'not_a_number' });
  assertEquals(validateLineValue(thk, 'TBD'), { ok: false, code: 'vague' });
  assertEquals(validateTerm('delivery', 'soon'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('delivery', '21 days'), { ok: true, value: '21 days' });
  assertEquals(validateTerm('warranty_period', 'long'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('installation_included', 'maybe'), { ok: false, code: 'choose_yes_or_no' });
});

Deno.test('the supplier notice names each line and detail, in the supplier language, signed by the sales engineer', () => {
  const lines = FITOUT.map((l) => (l.line_no === 1 ? { ...l, description: 'Wardrobe MDF carcass, HPL finish' } : l));
  const a = aq({ category: 'fitout', lines, terms: { ...TERMS, lead_time: '' } });
  const ar = holdNotice(a, 'ar', 'RFQ1');
  assert(ar.body.includes('البند 1') && ar.body.includes('السماكة') && ar.body.includes(SEAT_LABEL.ar), ar.body);
  const en = holdNotice(a, 'en', 'RFQ1');
  assert(en.body.includes('Line 1') && en.body.includes('Thickness') && en.body.includes('Delivery date') && en.body.includes(SEAT_LABEL.en));
});
