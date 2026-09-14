// The technical comparison dataset: line by line, attribute by attribute, flagged against the
// customer's intake answers, plus delivery / installation / warranty side by side. Shape = the contract.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/compare.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rankable, rendererView, technicalComparison } from './compare.ts';
import { labelQuotes } from '../quote_labels.ts';
import type { Requirements } from './assess.ts';

const now = new Date('2026-09-14T10:00:00Z');
const A = { quote_id: 'qa', label_en: 'Supplier A', label_ar: 'المورّد A', supplier_letter: 'A', option_no: 1,
  lines: [{ line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000 }],
  terms: { lead_time: '21 days', warranty: '2 years on workmanship', scope: 'Supply and installation of wardrobes by our team', price_ex_vat: 6000 } };
const B = { quote_id: 'qb', label_en: 'Supplier B', label_ar: 'المورّد B', supplier_letter: 'B', option_no: 1,
  lines: [{ line_no: 1, description: 'Wardrobe 16mm particle board, melamine finish', amount: 4000 }],
  terms: { lead_time: '6 weeks', warranty: '1 year on parts', scope: 'Supply only', price_ex_vat: 4000 } };
// The intake's stored object (docs/contracts/intake_answers.md, version 1).
const REQ: Requirements = { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes', min_months: 24 },
  required_by: { flexible: false, date: '2026-10-14' }, materials: [{ component: 'finish', label_en: 'Finish', choice: 'no_preference', choice_en: 'No preference' }] };

Deno.test('each request line compares every quote attribute by attribute against the customer\'s answers', () => {
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: REQ, quotes: [A, B], on_hold: 1, now });
  assertEquals([t.contract, t.version, t.on_hold, t.trade], ['technical_comparison', 1, 1, 'joinery']);
  assertEquals(t.quotes.map((q) => q.price_ex_vat), [6000, 4000]);
  assert(!/vat_amount|vat_treatment|supplier_trn|\btrn\b/i.test(JSON.stringify(t)), 'no VAT or TRN field in the customer dataset');
  const at = (code: string) => t.lines[0].attributes.find((a) => a.code === code)!;
  assertEquals(at('material').cells.map((c) => [c.value, c.marker]), [['Moisture-resistant MDF', '✓'], ['Particle board', '≠']]);
  assertEquals(at('thickness_mm').cells.map((c) => [c.value, c.marker]), [['18', '✓'], ['16', '≠']]);
  assertEquals([at('finish').requested_source, ...at('finish').cells.map((c) => c.marker)], ['no_preference', '✓', '✓']);
  const term = (code: string) => t.terms.find((x) => x.code === code)!;
  assertEquals(term('delivery').cells.map((c) => c.marker), ['✓', '≠']);
  assertEquals([term('installation').requested, ...term('installation').cells.map((c) => c.marker)], ['required', '✓', '≠']);
  // B's 12 months is below the customer's 24-month minimum: ≠, never ✓.
  assertEquals([term('warranty').requested, ...term('warranty').cells.map((c) => c.marker)], ['24 months minimum', '✓', '≠']);
});

Deno.test('the customer\'s named component is its own row: requested value against each quote\'s', () => {
  const req: Requirements = { version: 1, installation: { required: 'no' }, warranty: { required: 'no' },
    materials: [{ component: 'legs_base', label_en: 'Legs or base', label_ar: 'الأرجل أو القاعدة', choice: 'steel', choice_en: 'Steel' }] };
  const S = { ...A, quote_id: 'qs', lines: [{ line_no: 1, description: 'Dining table legs in stainless steel, 40mm, lacquer finish', amount: 900 }], terms: { lead_time: '4 weeks', price_ex_vat: 900 } };
  const Al = { ...B, quote_id: 'qal', lines: [{ line_no: 1, description: 'Dining table legs in aluminium, 40mm, lacquer finish', amount: 700 }], terms: { lead_time: '4 weeks', price_ex_vat: 700 } };
  const t = technicalComparison({ category: 'custom-furniture', request_lines: [{ line_no: 1, description: 'Dining table legs' }], requirements: req, quotes: [S, Al], on_hold: 0, now });
  const legs = t.lines[0].attributes.find((a) => a.code === 'component_legs_base')!;
  assertEquals([legs.requested, legs.requested_source, legs.mandatory, ...legs.cells.map((c) => `${c.value} ${c.marker}`)], ['Steel', 'intake', true, 'Steel ✓', 'Aluminium ≠']);
  assertEquals(t.terms.find((x) => x.code === 'installation')!.cells.map((c) => c.flag), ['not_applicable', 'not_applicable']);
});

Deno.test('a detail a quote does not state is —, and with no baseline the value shows unflagged', () => {
  const C = { ...A, quote_id: 'qc', lines: [{ line_no: 1, description: 'Wardrobes MDF, HPL finish', amount: 5000 }], terms: { ...A.terms, warranty: '' } };
  const t = technicalComparison({ category: 'joinery', request_lines: [], requirements: null, quotes: [A, C], on_hold: 0, now });
  assertEquals(t.lines[0].attributes.find((a) => a.code === 'thickness_mm')!.cells.map((c) => c.flag), ['stated', 'missing']);
  assertEquals(t.terms.find((x) => x.code === 'warranty')!.cells.map((c) => c.marker), ['', '—']);
});

// Measured 14 Sep 2026 on both live e2e comparisons: every "missing" cell was a quote with no line on
// a row that is another supplier's own item, and the report told the customer "not stated — ask for
// it". A quote that does not include an item is not missing a detail of it.
Deno.test('a quote that does not include an item is not_applicable on that row, never missing', () => {
  const W = { ...B, quote_id: 'qw', lines: [{ line_no: 1, description: 'Wardrobe 16mm particle board, melamine finish', amount: 4000 }, { line_no: 2, description: 'Kitchen worktop quartz 20mm thick', amount: 2500 }] };
  const t = technicalComparison({ category: 'joinery', request_lines: [], requirements: null, quotes: [A, W], on_hold: 0, now });
  const worktop = t.lines.find((l) => /worktop/i.test(l.item))!;
  assert(worktop, 'the extra item is its own row');
  const aCells = worktop.attributes.flatMap((at) => at.cells.filter((c) => c.quote_id === 'qa'));
  assert(aCells.length > 0);
  assertEquals([...new Set(aCells.map((c) => c.flag))], ['not_applicable']);
});

Deno.test('the renderer view is exactly the shape PR #611\'s comparison report reads', () => {
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: REQ, quotes: [A, B], on_hold: 0, now });
  const r = rendererView(t, 'ar');
  assertEquals(r.suppliers, ['Supplier A', 'Supplier B']);
  assertEquals([r.lines[0].line_no, r.lines[0].item, r.lines[0].qty, r.lines[0].unit], [1, 'Wardrobe 18mm MDF HPL finish', 4, 'nos']);
  const thk = r.lines[0].attributes.find((a) => a.key === 'thickness_mm')!;
  assertEquals([thk.label, thk.unit, thk.requested, thk.values['Supplier A'], thk.values['Supplier B']], ['السماكة', 'ملم', '18', { value: '18', flag: 'match' }, { value: '16', flag: 'differs' }]);
  assertEquals([r.terms!.warranty!.values['Supplier B'].flag, Object.keys(r.terms!)], ['differs', ['lead_time', 'installation', 'warranty']]);
});

Deno.test('an incomplete quote can never be ranked: it is removed before the ranking and only counted', () => {
  const D = { ...A, quote_id: 'qd', lines: [{ line_no: 1, description: 'Wardrobes MDF, HPL finish', amount: 3000 }], terms: { ...A.terms, scope: '', notes: 'Installation included' } };
  const r = rankable([A, B, D], 'joinery', null);
  assertEquals([r.rankable.map((q) => q.quote_id), r.held], [['qa', 'qb'], 1]);
  assertEquals(rankable([{ ...A, quote_id: 'qe', terms: { ...A.terms, price_ex_vat: null } }], 'joinery', null), { rankable: [], held: 1 });
});

Deno.test('two options from one supplier are two rows, labelled as that supplier\'s options', () => {
  const l = labelQuotes([{ id: 'x1', supplier_id: 7, option_no: 1 }, { id: 'y', supplier_id: 9 }, { id: 'x2', supplier_id: 7, option_no: 2 }]);
  assertEquals([l.get('x1')!.en, l.get('x2')!.en, l.get('y')!.en], ['Supplier A – Option 1', 'Supplier A – Option 2', 'Supplier B']);
  assertEquals(l.get('x2')!.ar, 'المورّد A – الخيار 2');
});
