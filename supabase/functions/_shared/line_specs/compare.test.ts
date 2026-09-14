// The technical comparison dataset: line by line, attribute by attribute, flagged against what the
// customer asked for, plus delivery / installation / warranty side by side. Shape = the contract.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/compare.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { technicalComparison } from './compare.ts';
import { labelQuotes } from '../quote_labels.ts';

const now = new Date('2026-09-14T10:00:00Z');
const A = { quote_id: 'qa', label_en: 'Supplier A', label_ar: 'المورّد A', supplier_letter: 'A', option_no: 1,
  lines: [{ line_no: 1, description: 'Wardrobes 18mm MR MDF, HPL finish', amount: 6000 }],
  terms: { lead_time: '21 days', warranty: '2 years on workmanship', scope: 'Supply and installation of wardrobes by our team', price_ex_vat: 6000 } };
const B = { quote_id: 'qb', label_en: 'Supplier B', label_ar: 'المورّد B', supplier_letter: 'B', option_no: 1,
  lines: [{ line_no: 1, description: 'Wardrobe 16mm particle board, melamine finish', amount: 4000 }],
  terms: { lead_time: '6 weeks', warranty: '1 year on parts', scope: 'Supply only', price_ex_vat: 4000 } };

Deno.test('each request line compares every quote attribute by attribute against the request', () => {
  const t = technicalComparison({ category: 'joinery', request_lines: [{ line_no: 1, description: 'Wardrobe 18mm MDF HPL finish', qty: 4, unit: 'nos' }],
    requirements: { installation: 'required', warranty: { min_months: 24 }, delivery_by: '2026-10-14', materials: [{ component: 'wardrobe', attr: 'finish', value: 'no_preference' }] },
    quotes: [A, B], on_hold: 1, now });
  assertEquals([t.contract, t.version, t.on_hold, t.trade], ['technical_comparison', 1, 1, 'joinery']);
  assertEquals(t.quotes.map((q) => q.price_ex_vat), [6000, 4000]);
  assert(!/vat_amount|vat_treatment|supplier_trn|\btrn\b/i.test(JSON.stringify(t)), 'no VAT or TRN field in the customer dataset');
  const row = t.lines[0];
  assertEquals([row.trade, row.request_line!.description], ['joinery', 'Wardrobe 18mm MDF HPL finish']);
  const at = (code: string) => row.attributes.find((a) => a.code === code)!;
  assertEquals(at('material').requested, 'MDF');
  assertEquals(at('material').cells.map((c) => [c.value, c.marker]), [['Moisture-resistant MDF', '✓'], ['Particle board', '≠']]);
  assertEquals(at('thickness_mm').cells.map((c) => [c.value, c.marker]), [['18', '✓'], ['16', '≠']]);
  assertEquals([at('finish').requested_source, ...at('finish').cells.map((c) => c.marker)], ['no_preference', '✓', '✓']);
  const term = (code: string) => t.terms.find((x) => x.code === code)!.cells.map((c) => c.marker);
  assertEquals(term('delivery'), ['✓', '≠']);
  assertEquals(term('installation'), ['✓', '≠']);
  assertEquals(term('warranty'), ['✓', '≠']);
});

Deno.test('a detail a quote does not state is — and a request with no baseline shows the value unflagged', () => {
  const C = { ...A, quote_id: 'qc', lines: [{ line_no: 1, description: 'Wardrobes MDF, HPL finish', amount: 5000 }], terms: { ...A.terms, warranty: '' } };
  const t = technicalComparison({ category: 'joinery', request_lines: [], requirements: null, quotes: [A, C], on_hold: 0, now });
  const thk = t.lines[0].attributes.find((a) => a.code === 'thickness_mm')!;
  assertEquals(thk.cells.map((c) => c.flag), ['stated', 'missing']);
  assertEquals(t.terms.find((x) => x.code === 'warranty')!.cells.map((c) => c.marker), ['', '—']);
});

Deno.test('two options from one supplier are two rows, labelled as that supplier\'s options', () => {
  const l = labelQuotes([{ id: 'x1', supplier_id: 7, option_no: 1 }, { id: 'y', supplier_id: 9 }, { id: 'x2', supplier_id: 7, option_no: 2 }]);
  assertEquals([l.get('x1')!.en, l.get('x2')!.en, l.get('y')!.en], ['Supplier A – Option 1', 'Supplier A – Option 2', 'Supplier B']);
  assertEquals(l.get('x2')!.ar, 'المورّد A – الخيار 2');
  assert(l.get('y')!.multi === false);
});
