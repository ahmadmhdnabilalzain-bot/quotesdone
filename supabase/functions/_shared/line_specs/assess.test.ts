// The hold decision. The required set is the customer's inquiry first (founder_instruction #142,
// #159), then the trade's general standard: material spec per line, delivery, installation and
// warranty unless the customer explicitly chose not needed, the customer's own components, and the
// price excluding VAT — each missing, and each not required.
//
// 23 Sep 2026 (decision point 30): nothing here reads a supplier's words. A line's values, its trade in a
// composite quote, "no material", "does not apply" and "names the customer's component" arrive as what
// REASONING read (applyReading, source 'reasoned') or as what the supplier STATED in keyed fields. An
// unread quote is held with every detail asked — the case under the model hold.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/assess.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessQuote, deliveryOf, holdNotice, materialNames, READ, requirementsOf, SEAT_LABEL, validateLineValue, validateTerm, warrantyPeriod, type Line, type Requirements, type Terms, type TermsSpec } from './assess.ts';
import { applyReading, type QuoteReading } from '../reasoned_matching.ts';
import { TRADES } from './model.ts';

const L = (line_no: number, description: string, x: Partial<Line> = {}): Line => ({ line_no, description, ...x });
/** Assess after a reading, as the gate does; every fixture states its ex-VAT price unless a test is about it. */
function aq(i: { category: string | null; lines: Line[]; terms?: Terms; requirements?: Requirements; read?: QuoteReading['lines']; readTerms?: TermsSpec }) {
  const terms = { price_ex_vat: 20000, ...i.terms };
  const r = applyReading(i.lines, terms.terms_spec, i.read || i.readTerms ? { lines: i.read ?? {}, terms: i.readTerms ?? {} } : null);
  return assessQuote({ category: i.category, lines: r.lines, terms: { ...terms, terms_spec: r.terms_spec }, requirements: i.requirements });
}
const codes = (a: ReturnType<typeof assessQuote>) => a.missing.map((m) => (m.scope === 'line' ? `${m.line_no}:${m.attr}` : m.attr));
const R = (x: Partial<NonNullable<Requirements>>): Requirements => ({ version: 1, ...x });
const NONE_NEEDED = R({ installation: { required: 'not_needed' }, warranty: { required: 'not_needed' } });
const TERMS_READ: TermsSpec = { installation: { included: 'yes', detail: 'installation in 5 days', source: 'reasoned' }, warranty: { period: '1 year', coverage: 'workmanship and materials', source: 'reasoned' } };

const FITOUT: Line[] = [
  L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { qty: 2, unit_price: 3000, amount: 6000 }),
  L(2, 'Gypsum false ceiling 12.5mm standard gypsum board on 0.6mm GI channels', { amount: 9000 }),
  L(3, 'Preliminaries and site setup', { amount: 1500 }),
];
// What reasoning read from FITOUT, the supplier's own words as each value.
const FITOUT_READ: QuoteReading['lines'] = {
  1: { [READ.trade]: 'joinery', material: 'MDF', thickness_mm: '18mm', finish: 'HPL' },
  2: { [READ.trade]: 'gypsum', board_type: 'standard gypsum board', thickness_mm: '12.5mm', frame: '0.6mm GI channels', [READ.na('dimensions')]: 'false ceiling' },
  3: { [READ.trade]: 'none' },
};

Deno.test('the intake answers are read where the intake stores them', () => {
  assertEquals(requirementsOf({ customer_requirements: { installation: { required: 'yes' } } })?.installation?.required, 'yes');
  assertEquals(requirementsOf({ requirements: { warranty: { required: 'no' } } })?.warranty?.required, 'no');
  assertEquals(requirementsOf({ summary: 'x' }), null);
});

Deno.test('a read fit-out quote that states every detail passes; each line is the trade reasoning read', () => {
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { lead_time: '4 weeks' }, read: FITOUT_READ, readTerms: TERMS_READ });
  assertEquals(codes(a), []);
  assertEquals(a.lines.map((l) => [l.trade, l.material]), [['joinery', true], ['gypsum', true], [null, false]]);
  assertEquals(a.lines[0].source.thickness_mm, 'reasoned');
  assert(!a.lines[1].asked.includes('dimensions'), 'a conditional attribute reasoning found not to apply is not asked');
});

Deno.test('UNDER THE HOLD (nothing read): the quote is held and every detail is asked — never passed on a guess', () => {
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { lead_time: '4 weeks', warranty: '1 year' } });
  assert(a.held);
  // A composite line with no reading asks its exact specification; the preliminaries line is asked too (safe).
  assertEquals(codes(a).filter((c) => c.endsWith(':specification')), ['1:specification', '2:specification', '3:specification']);
  // A single-trade quote asks the trade's mandatory core on every line, conditional ones included.
  const j = aq({ category: 'joinery', lines: [L(1, 'Wardrobe 18mm MDF carcass, HPL finish')], terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED });
  assertEquals(codes(j), ['1:material', '1:thickness_mm', '1:finish']);
});

Deno.test('what the supplier stated in keyed fields releases the hold without any reading', () => {
  const lines = [L(1, 'Wardrobe', { spec: { material: 'MDF', thickness_mm: '18', finish: 'HPL' }, spec_source: { material: 'supplier_portal', thickness_mm: 'supplier_portal', finish: 'supplier_portal' } })];
  assertEquals(codes(aq({ category: 'joinery', lines, terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED })), []);
});

Deno.test('a reading key the SUPPLIER typed is ignored: only reasoning can say a line carries no material', () => {
  const typed = [L(1, 'Wardrobe', { spec: { [READ.notMaterial]: 'labour' }, spec_source: { [READ.notMaterial]: 'supplier_portal' } })];
  const a = aq({ category: 'joinery', lines: typed, terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED });
  assert(a.lines[0].material && a.held);
  const read = aq({ category: 'joinery', lines: [L(1, 'Installation labour')], read: { 1: { [READ.notMaterial]: 'Installation labour' } }, terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED });
  assertEquals([read.lines[0].material, codes(read)], [false, ['line_items']]);
});

Deno.test('"no material" in the supplier\'s own words skips the specs only when the line\'s shape agrees (3 Nov 2026)', () => {
  // Before: any reasoned READ.notMaterial skipped every spec question, whatever else the line said.
  const said = (description: string, words: string, x: Partial<Line> = {}) =>
    aq({ category: 'joinery', lines: [L(1, description, x)], read: { 1: { [READ.notMaterial]: words } }, terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED });
  const tiles = said('Wardrobe MDF carcass labour only no material', 'labour only no material');
  assertEquals([tiles.lines[0].material, codes(tiles)], [true, ['1:material', '1:thickness_mm', '1:finish']]);
  assert(said('Installation labour 2400x600', 'Installation labour').lines[0].material, 'a dimension');
  assert(said('Fixing labour', 'labour', { notes: 'x', spec: { material: 'MDF' }, spec_source: { material: 'supplier_portal' } }).lines[0].material, 'a stated value');
  assert(said('Wardrobe', 'labour only').lines[0].material, 'words the line does not carry');
  // a material word of the line's own trade, from the catalogue's options (tiling: ceramic, porcelain, marble ...)
  const tiling = (description: string, words: string, x: Partial<Line> = {}) =>
    aq({ category: 'tiling', lines: [L(1, description, x)], read: { 1: { [READ.notMaterial]: words } }, terms: { lead_time: '3 weeks' }, requirements: NONE_NEEDED });
  assert(tiling('Installation of ceramic tiles - labour only', 'labour only').lines[0].material, 'names a tiling material, not priced as labour');
  assert(tiling('Ceramic tiles 60x60 (labour only)', 'labour only').lines[0].material, 'a dimension');
  // service lines of any length skip their specs (review of #1836: the one-other-word rule held every one of these)
  for (const d of ['Delivery charges to Abu Dhabi site', 'Installation charges for 12 doors', 'Lump sum for preliminaries and site setup',
    'Site cleaning after completion of works', 'Removal and disposal of existing wardrobes', 'Labour charges for installation of 3 wardrobes'])
    assertEquals(said(d, d).lines[0].material, false, d);
  // ordinary labour and transport lines are not material (review of #1836): the unit says nothing either way
  assertEquals(said('Transport to site', 'Transport').lines[0].material, false);
  assertEquals(said('Tile laying labour', 'Tile laying labour', { unit: 'm2' }).lines[0].material, false);
  assertEquals(said('Labour charges for fixing', 'Labour charges for fixing', { unit: 'nos' }).lines[0].material, false);
  assertEquals(said('Installation of ceramic tiles - labour only', 'labour only', { unit: 'm2', labour: 1500 }).lines[0].material, false);
  assertEquals(said('Site supervision and labour', 'Site supervision and labour').lines[0].material, false);
});

Deno.test('(1) a line whose reading did not find a detail holds the quote and names the line and the detail', () => {
  const read = { ...FITOUT_READ, 1: { [READ.trade]: 'joinery', material: 'MDF', finish: 'HPL' } };
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { lead_time: '4 weeks' }, read, readTerms: TERMS_READ });
  assertEquals(codes(a), ['1:thickness_mm']);
  assertEquals([a.missing[0].label_ar, a.missing[0].unit], ['السماكة', 'mm']);
});

Deno.test('(2) delivery: a lead time or a date by its format; anything else holds the quote', () => {
  for (const lead_time of [null, '', 'ASAP', 'TBD', 'as per schedule', 'Ex-stock']) assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { lead_time }, read: FITOUT_READ, readTerms: TERMS_READ })), ['delivery'], String(lead_time));
  for (const lead_time of ['21 days', '3 weeks', '30 Oct 2026', '2026-10-30', '45 يوم عمل']) assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, terms: { lead_time }, read: FITOUT_READ, readTerms: TERMS_READ })), [], lead_time);
  assertEquals(deliveryOf('3 weeks')?.days, 21);
  // A delivery reasoning read from the quotation counts the same.
  assertEquals(codes(aq({ category: 'fitout', lines: FITOUT, read: FITOUT_READ, readTerms: { ...TERMS_READ, delivery: { value: '21 days', source: 'reasoned' } } })), []);
});

const WARDROBE = [L(1, 'Wardrobe 18mm MDF carcass, HPL finish', { amount: 6000 })];
const WARDROBE_READ = { 1: { material: 'MDF', thickness_mm: '18mm', finish: 'HPL' } };
const W_ONLY: TermsSpec = { warranty: { period: '1 year', coverage: 'workmanship', source: 'reasoned' } };
Deno.test('(3) installation: required → included (read or stated) with scope or timeline; a priced installation is included', () => {
  const req = R({ installation: { required: 'yes' } });
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, requirements: req, read: WARDROBE_READ, readTerms: W_ONLY })), ['installation_included']);
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, requirements: req, read: WARDROBE_READ, readTerms: { ...W_ONLY, installation: { included: 'yes', source: 'reasoned' } } })), ['installation_detail']);
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, requirements: req, read: WARDROBE_READ, readTerms: { ...W_ONLY, installation: { included: 'yes', detail: 'installation in 5 days after delivery', source: 'reasoned' } } })), []);
  const priced = [L(1, 'Wardrobe', { amount: 6000 }), L(2, 'Fixing', { install: 800 })];
  assertEquals(codes(aq({ category: 'joinery', lines: priced, terms: { lead_time: '3 weeks' }, requirements: req, read: { ...WARDROBE_READ, 2: { [READ.notMaterial]: 'Fixing' } }, readTerms: W_ONLY })), []);
});

Deno.test('(3) installation: "supply_only" from the customer → not required; "no" read from the supplier is an answer', () => {
  const notReq = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, requirements: R({ installation: { required: 'supply_only' } }), read: WARDROBE_READ, readTerms: W_ONLY });
  assertEquals([codes(notReq), notReq.terms.installation.applies], [[], false]);
  const supplyOnly = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, read: WARDROBE_READ, readTerms: { ...W_ONLY, installation: { included: 'no', source: 'reasoned' } } });
  assertEquals([codes(supplyOnly), supplyOnly.terms.installation.included], [[], 'no']);
});

Deno.test('(3)(4) we do not assume: "not_sure" and a legacy request with no answer both require installation and warranty', () => {
  const clean = [L(1, 'Deep cleaning of villa using Diversey products')];
  const read = { 1: { method: 'Deep cleaning', products: 'Diversey' } };
  for (const requirements of [null, R({ installation: { required: 'not_sure' }, warranty: { required: 'not_sure' } })]) {
    assertEquals(codes(aq({ category: 'cleaning', lines: clean, terms: { lead_time: '2 days' }, requirements, read })), ['installation_included', 'warranty_period', 'warranty_coverage'], JSON.stringify(requirements));
  }
  assertEquals(codes(aq({ category: 'cleaning', lines: clean, terms: { lead_time: '2 days' }, requirements: NONE_NEEDED, read })), []);
});

Deno.test('(4) warranty: the period by its format, what it covers only as read or stated', () => {
  const inst: TermsSpec = { installation: { included: 'yes', detail: 'in 5 days', source: 'reasoned' } };
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '' }, read: WARDROBE_READ, readTerms: inst })), ['warranty_period', 'warranty_coverage']);
  // A period in the warranty field is its format; its coverage is not read from the words any more.
  assertEquals(codes(aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', warranty: '2 years parts and labour' }, read: WARDROBE_READ, readTerms: inst })), ['warranty_coverage']);
  assertEquals(warrantyPeriod('ضمان سنتين'), { months: 24, period: '2 years' });
  const short = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks' }, requirements: R({ warranty: { required: 'yes', min_months: 24 } }), read: WARDROBE_READ,
    readTerms: { ...inst, warranty: { period: '12 months', coverage: 'workmanship', source: 'reasoned' } } });
  assertEquals([codes(short), short.terms.warranty.months], [[], 12]);
});

// Custom furniture: the customer named steel legs and had no preference for the top.
const FURNITURE = R({ installation: { required: 'not_needed' }, warranty: { required: 'not_needed' }, materials: [
  { component: 'top_body', label_en: 'Top or main body', label_ar: 'السطح أو الجسم الرئيسي', choice: 'no_preference', choice_en: 'No preference' },
  { component: 'legs_base', label_en: 'Legs or base', label_ar: 'الأرجل أو القاعدة', choice: 'steel', choice_en: 'Steel', choice_ar: 'حديد (ستيل)' },
] });
const TABLE = [L(1, 'Dining table top 20mm solid oak, lacquer finish'), L(2, 'Dining table legs in stainless steel, 40mm, lacquer finish')];
const JOIN = { thickness_mm: '20mm', finish: 'lacquer' };
Deno.test('(1+) a material the customer named for a component is required on the line reasoning read to name it', () => {
  const read = { 1: { ...JOIN, [READ.names('top_body')]: 'table top', component_top_body: 'solid oak' }, 2: { ...JOIN, [READ.names('legs_base')]: 'table legs', component_legs_base: 'stainless steel' } };
  const ok = aq({ category: 'custom-furniture', lines: TABLE, terms: { lead_time: '4 weeks' }, requirements: FURNITURE, read });
  assertEquals(codes(ok), []);
  assertEquals([ok.lines[0].spec.component_top_body, ok.lines[1].spec.component_legs_base], ['solid oak', 'stainless steel']);
  assert(!ok.lines[1].asked.includes('material'), 'the legs line is not asked a board type');
  const noLeg = aq({ category: 'custom-furniture', lines: TABLE, terms: { lead_time: '4 weeks' }, requirements: FURNITURE, read: { ...read, 2: { ...JOIN, [READ.names('legs_base')]: 'table legs' } } });
  assertEquals(codes(noLeg), ['2:component_legs_base']);
  assertEquals(noLeg.missing[0].label_ar, 'المادة — الأرجل أو القاعدة');
});

Deno.test('(1+) a component no line was read to name is asked of the quote as a whole; stated there, it passes', () => {
  const read = { 1: { ...JOIN, material: 'Solid wood', [READ.names('top_body')]: 'table top', component_top_body: 'solid oak' } };
  const a = aq({ category: 'custom-furniture', lines: [TABLE[0]], terms: { lead_time: '4 weeks' }, requirements: FURNITURE, read });
  assertEquals(codes(a), ['component:legs_base']);
  const filled = aq({ category: 'custom-furniture', lines: [TABLE[0]], terms: { lead_time: '4 weeks', terms_spec: { components: { legs_base: { value: 'Powder-coated steel', source: 'supplier_portal' } } } }, requirements: FURNITURE, read });
  assertEquals(codes(filled), []);
});

Deno.test('a material named only by its key takes the catalogue names, in both languages', () => {
  assertEquals(materialNames({ component: 'glass' }), { en: 'Glass', ar: 'الزجاج' });
  assertEquals(materialNames({ component: 'glass', label_en: 'Glazing', label_ar: 'الزجاج المزدوج' }), { en: 'Glazing', ar: 'الزجاج المزدوج' });
  assertEquals(materialNames({ component: 'no_such_part' }), { en: 'no such part', ar: 'no such part' });
});

Deno.test('(5) no exact price excluding VAT holds the quote', () => {
  const a = aq({ category: 'joinery', lines: WARDROBE, terms: { lead_time: '3 weeks', price_ex_vat: null }, requirements: NONE_NEEDED, read: WARDROBE_READ });
  assertEquals([codes(a), a.missing[0].unit], [['price_ex_vat'], 'AED']);
  assertEquals(validateTerm('price_ex_vat', 'AED 10,500'), { ok: true, value: '10500' });
});

Deno.test('the portal checks the SHAPE of a typed value, as the gate reads it', () => {
  const thk = TRADES.joinery.attrs.find((a) => a.code === 'thickness_mm')!;
  assertEquals(validateLineValue(thk, '18'), { ok: true, value: '18' });
  assertEquals(validateLineValue(thk, 'thick'), { ok: false, code: 'not_a_number' });
  assertEquals(validateLineValue(thk, '--'), { ok: false, code: 'vague' });
  assertEquals(validateTerm('delivery', 'soon'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('warranty_period', 'long'), { ok: false, code: 'not_concrete' });
  assertEquals(validateTerm('installation_included', 'maybe'), { ok: false, code: 'choose_yes_or_no' });
  assertEquals(validateTerm('component:legs_base', 'Powder-coated steel'), { ok: true, value: 'Powder-coated steel' });
});

Deno.test('the supplier notice names each line and detail, in the supplier language, signed by the sales engineer', () => {
  const read = { ...FITOUT_READ, 1: { [READ.trade]: 'joinery', material: 'MDF', finish: 'HPL' } };
  const a = aq({ category: 'fitout', lines: FITOUT, terms: { lead_time: '' }, read, readTerms: TERMS_READ });
  const ar = holdNotice(a, 'ar', 'RFQ1');
  assert(ar.body.includes('البند 1') && ar.body.includes('السماكة') && ar.body.includes(SEAT_LABEL.ar), ar.body);
  const en = holdNotice(a, 'en', 'RFQ1');
  assert(en.body.includes('Line 1') && en.body.includes('Thickness') && en.body.includes('Delivery date') && en.body.includes(SEAT_LABEL.en));
});
