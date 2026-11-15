// The technical comparison dataset: line by line, attribute by attribute, flagged against the
// customer's intake answers, plus delivery / installation / warranty side by side. Shape = the contract.
// 23 Sep 2026: a quote reaches the comparison already READ (its values on quote_items.spec, source
// 'reasoned' or 'supplier_portal'; its terms on terms_spec), and ✓ means the SAME value, never a contained one.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/compare.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rankable, rendererView, sameValue, technicalComparison } from './compare.ts';
import { labelQuotes } from '../quote_labels.ts';
import type { Line, Requirements, TermsSpec } from './assess.ts';

const now = new Date('2026-09-14T10:00:00Z');
/** A line as the gate stores it after reading: each value with its source. */
const RL = (line_no: number, description: string, spec: Record<string, string>, amount: number): Line =>
  ({ line_no, description, amount, spec, spec_source: Object.fromEntries(Object.keys(spec).map((k) => [k, 'reasoned' as const])) });
const TS = (inst: 'yes' | 'no', period: string, coverage: string): TermsSpec => ({
  installation: { included: inst, detail: inst === 'yes' ? 'by our team, 5 days' : null, source: 'reasoned' },
  warranty: { period, coverage, source: 'reasoned' } });
const A = { quote_id: 'qa', label_en: 'Supplier A', label_ar: 'المورّد A', supplier_letter: 'A', option_no: 1,
  lines: [RL(1, 'Wardrobes 18mm MR MDF, HPL finish', { material: 'MR MDF', thickness_mm: '18mm', finish: 'HPL', '_names:finish': 'HPL finish' }, 6000)],
  terms: { lead_time: '21 days', price_ex_vat: 6000, terms_spec: TS('yes', '2 years', 'workmanship') } };
const B = { quote_id: 'qb', label_en: 'Supplier B', label_ar: 'المورّد B', supplier_letter: 'B', option_no: 1,
  lines: [RL(1, 'Wardrobe 16mm particle board, melamine finish', { material: 'particle board', thickness_mm: '16mm', finish: 'melamine' }, 4000)],
  terms: { lead_time: '6 weeks', price_ex_vat: 4000, terms_spec: TS('no', '1 year', 'parts') } };
const REQ: Requirements = { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes', min_months: 24 },
  required_by: { flexible: false, date: '2026-10-14' }, materials: [
    { component: 'finish', label_en: 'Finish', choice: 'no_preference', choice_en: 'No preference' },
    { component: 'main', label_en: 'Main material', choice: 'mr_mdf', choice_en: 'MR MDF' }] };

Deno.test('same value is exact: format falls away, containment and a bare first number do not match', () => {
  assert(sameValue('18 mm', '18mm') && sameValue('18', '18 mm') && sameValue('MR-MDF', 'mr mdf') && sameValue('١٨ مم', '18 مم'));
  assert(!sameValue('white', 'off-white'), 'contained is not the same');
  assert(!sameValue('10 mm', '10 m'), 'the same number in another unit is not the same');
  assert(!sameValue('10mm glass, 6mm frame', '10mm'), 'a first number is not the value');
  assert(!sameValue('', ''));
});

Deno.test('each request line compares every quote attribute against the customer\'s answers', () => {
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: REQ, quotes: [A, B], on_hold: 1, now });
  assertEquals([t.contract, t.version, t.on_hold, t.trade], ['technical_comparison', 1, 1, 'joinery']);
  assertEquals(t.quotes.map((q) => q.price_ex_vat), [6000, 4000]);
  assert(!/vat_amount|vat_treatment|supplier_trn|\btrn\b/i.test(JSON.stringify(t)), 'no VAT or TRN field in the customer dataset');
  const at = (code: string) => t.lines[0].attributes.find((a) => a.code === code)!;
  assertEquals(at('material').cells.map((c) => [c.value, c.marker, c.source]), [['MR MDF', '✓', 'reasoned'], ['particle board', '≠', 'reasoned']]);
  assertEquals(at('thickness_mm').cells.map((c) => c.flag), ['stated', 'stated'], 'a BOQ line\'s words are no longer a baseline');
  assertEquals([at('finish').requested_source, ...at('finish').cells.map((c) => c.marker)], ['no_preference', '✓', '✓']);
  const term = (code: string) => t.terms.find((x) => x.code === code)!;
  assertEquals(term('delivery').cells.map((c) => c.marker), ['✓', '≠']);
  assertEquals([term('installation').requested, ...term('installation').cells.map((c) => c.marker)], ['required', '✓', '≠']);
  // B's 12 months is below the customer's 24-month minimum: ≠, never ✓.
  assertEquals([term('warranty').requested, ...term('warranty').cells.map((c) => c.marker)], ['24 months minimum', '✓', '≠']);
});

Deno.test('the customer\'s named component is its own row on the lines reasoning read to name it', () => {
  const req: Requirements = { version: 1, installation: { required: 'not_needed' }, warranty: { required: 'not_needed' },
    materials: [{ component: 'legs_base', label_en: 'Legs or base', label_ar: 'الأرجل أو القاعدة', choice: 'steel', choice_en: 'Steel' }] };
  const legs = (v: string) => ({ '_names:legs_base': 'table legs', component_legs_base: v, thickness_mm: '40mm', finish: 'lacquer' });
  const S = { ...A, quote_id: 'qs', lines: [RL(1, 'Dining table legs in steel', legs('steel'), 900)], terms: { lead_time: '4 weeks', price_ex_vat: 900 } };
  const Al = { ...B, quote_id: 'qal', lines: [RL(1, 'Dining table legs in aluminium', legs('aluminium'), 700)], terms: { lead_time: '4 weeks', price_ex_vat: 700 } };
  const t = technicalComparison({ category: 'custom-furniture', request_lines: [{ line_no: 1, description: 'Dining table legs' }], requirements: req, quotes: [S, Al], on_hold: 0, now });
  const row = t.lines[0].attributes.find((a) => a.code === 'component_legs_base')!;
  assertEquals([row.requested, row.requested_source, row.mandatory, ...row.cells.map((c) => `${c.value} ${c.marker}`)], ['Steel', 'intake', true, 'steel ✓', 'aluminium ≠']);
  assertEquals(t.terms.find((x) => x.code === 'installation')!.cells.map((c) => c.flag), ['not_applicable', 'not_applicable']);
});

Deno.test('a detail a quote does not state is —, and with no baseline the value shows unflagged', () => {
  const C = { ...A, quote_id: 'qc', lines: [RL(1, 'Wardrobes MDF, HPL finish', { material: 'MDF', finish: 'HPL' }, 5000)], terms: { ...A.terms, terms_spec: { installation: A.terms.terms_spec.installation } } };
  const t = technicalComparison({ category: 'joinery', request_lines: [], requirements: null, quotes: [A, C], on_hold: 0, now });
  assertEquals(t.lines[0].attributes.find((a) => a.code === 'thickness_mm')!.cells.map((c) => c.flag), ['stated', 'missing']);
  assertEquals(t.terms.find((x) => x.code === 'warranty')!.cells.map((c) => c.marker), ['', '—']);
});

// Measured 14 Sep 2026 on both live e2e comparisons: every "missing" cell was a quote with no line on
// a row that is another supplier's own item. A quote that does not include an item is not missing a detail of it.
Deno.test('a quote that does not include an item is not_applicable on that row, never missing', () => {
  const W = { ...B, quote_id: 'qw', lines: [B.lines[0], RL(2, 'Kitchen worktop quartz 20mm thick', { material: 'quartz', thickness_mm: '20mm' }, 2500)] };
  const t = technicalComparison({ category: 'joinery', request_lines: [], requirements: null, quotes: [A, W], on_hold: 0, now });
  const worktop = t.lines.find((l) => /worktop/i.test(l.item))!;
  assert(worktop, 'the extra item is its own row');
  const aCells = worktop.attributes.flatMap((at) => at.cells.filter((c) => c.quote_id === 'qa'));
  assert(aCells.length > 0);
  assertEquals([...new Set(aCells.map((c) => c.flag))], ['not_applicable']);
});

Deno.test('an optional detail one supplier states and another does not is optional_not_stated, not n/a', () => {
  const E = { ...A, quote_id: 'qe', lines: [RL(1, 'Wardrobes 18mm MR MDF, HPL finish, 2mm PVC edge banding', { material: 'MR MDF', thickness_mm: '18mm', finish: 'HPL', edge_band: '2mm PVC' }, 6000)] };
  const N = { ...B, quote_id: 'qn', lines: [RL(1, 'Wardrobes 18mm MR MDF, HPL finish', { material: 'MR MDF', thickness_mm: '18mm', finish: 'HPL' }, 5500)], terms: { ...A.terms, price_ex_vat: 5500 } };
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: null, quotes: [E, N], on_hold: 0, now });
  const eb = t.lines[0].attributes.find((a) => a.code === 'edge_band')!;
  assert(eb && !eb.mandatory, 'edge band is an optional detail for joinery');
  assertEquals(eb.cells.map((c) => [c.flag, c.marker]), [['stated', ''], ['optional_not_stated', '○']]);
  const r = rendererView(t, 'en');
  const view = r.lines[0].attributes.find((a) => a.key === 'edge_band')!;
  assertEquals([view.values['Supplier A'].flag, view.values['Supplier B'].flag], ['match', 'optional']);
});

Deno.test('the renderer view is exactly the shape PR #611\'s comparison report reads', () => {
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }], requirements: REQ, quotes: [A, B], on_hold: 0, now });
  const r = rendererView(t, 'ar');
  assertEquals(r.suppliers, ['Supplier A', 'Supplier B']);
  assertEquals([r.lines[0].line_no, r.lines[0].item, r.lines[0].qty, r.lines[0].unit], [1, 'Wardrobe 18mm MDF HPL finish', 4, 'nos']);
  const mat = r.lines[0].attributes.find((a) => a.key === 'material')!;
  assertEquals([mat.requested, mat.values['Supplier A'], mat.values['Supplier B']], ['MR MDF', { value: 'MR MDF', flag: 'match' }, { value: 'particle board', flag: 'differs' }]);
  assertEquals([r.terms!.warranty!.values['Supplier B'].flag, Object.keys(r.terms!)], ['differs', ['lead_time', 'installation', 'warranty']]);
});

Deno.test('an incomplete quote can never be ranked: it is removed before the ranking and only counted', () => {
  const D = { ...A, quote_id: 'qd', lines: [RL(1, 'Wardrobes MDF, HPL finish', { material: 'MDF', finish: 'HPL' }, 3000)] };
  const r = rankable([A, B, D], 'joinery', null);
  assertEquals([r.rankable.map((q) => q.quote_id), r.held], [['qa', 'qb'], 1]);
  assertEquals(rankable([{ ...A, quote_id: 'qe', terms: { ...A.terms, price_ex_vat: null } }], 'joinery', null), { rankable: [], held: 1 });
  // An unread quote (the model hold) is never rankable.
  assertEquals(rankable([{ ...A, quote_id: 'qu', lines: [{ line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000 }] }], 'joinery', null).held, 1);
});

Deno.test('two options from one supplier are two rows, labelled as that supplier\'s options', () => {
  const l = labelQuotes([{ id: 'x1', supplier_id: 7, option_no: 1 }, { id: 'y', supplier_id: 9 }, { id: 'x2', supplier_id: 7, option_no: 2 }], new Map([['7', 'A'], ['9', 'B']]));
  assertEquals([l.get('x1')!.en, l.get('x2')!.en, l.get('y')!.en], ['Supplier A – Option 1', 'Supplier A – Option 2', 'Supplier B']);
  assertEquals(l.get('x2')!.ar, 'المورّد A – الخيار 2');
});
