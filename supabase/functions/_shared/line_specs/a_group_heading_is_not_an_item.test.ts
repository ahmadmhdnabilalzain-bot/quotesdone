// A GROUP HEADING IS NOT AN ITEM (sales_engineer, 2 Nov 2026).
//
// Measured on the comparison journey (run 41441003027, on #1799): the two-option quotation was held with code
// quote_review_changes because its lines 1 and 3, "Option 1: standard system" and "Option 2: premium system" (no
// quantity, no price), were asked glass_type, glass_thickness and profile_system as if they were windows. Real
// suppliers write option and section headings, so genuine quotations were held. The rule is structural, not a word
// list: a line with no quantity and no price, followed by a priced line, labels the lines under it. It is asked
// nothing; its items are asked everything. Pure: no model, no network.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { assessQuote, type Line } from './assess.ts';
import { reviewQuotation, type Working } from '../../supplier_api/quote_review.ts';

const GLAZED = { glass_type: 'Double glazed unit', glass_thickness: '6mm + 12mm air + 6mm', profile_system: 'Schuco AWS 70', finish: 'RAL 9016 powder coated', standard: 'BS EN 14351-1', brand: 'Schuco', model: 'AWS 70' };
const src = (s: Record<string, string>) => Object.fromEntries(Object.keys(s).map((k) => [k, 'reasoned' as const]));
const item = (line_no: number, description: string, spec: Record<string, string>, amount: number): Line => ({ line_no, description, qty: 40, unit: 'nos', unit_price: amount / 40, amount, spec, spec_source: src(spec) });
const head = (line_no: number, description: string): Line => ({ line_no, description });
const TERMS = { lead_time: '21 days', warranty: '2 years', price_ex_vat: 118500,
  terms_spec: { installation: { included: 'yes' as const, detail: 'within 10 working days', source: 'reasoned' as const }, warranty: { period: '2 years', coverage: 'manufacturing defects and workmanship', source: 'reasoned' as const } } };
const TWO_OPTIONS = [head(1, 'Option 1: standard system'), item(2, 'Aluminium sliding windows, Schuco AWS 70', GLAZED, 118500),
  head(3, 'Option 2: premium system'), item(4, 'Aluminium sliding windows, Technal Soleal', { ...GLAZED, profile_system: 'Technal Soleal' }, 142000)];
const missingOf = (lines: Line[]) => assessQuote({ category: 'aluminium', lines, terms: TERMS, requirements: null }).missing.map((m) => `${m.line_no ?? 'q'}:${m.attr}`);

Deno.test('a two-option quotation with headings is assessed on its items: nothing is asked of a heading', () => {
  const a = assessQuote({ category: 'aluminium', lines: TWO_OPTIONS, terms: TERMS, requirements: null });
  assertEquals(missingOf(TWO_OPTIONS), []);
  assertEquals(a.held, false);
  assertEquals(a.lines.map((l) => [l.line_no, l.material, l.group]), [[1, false, null], [2, true, 'Option 1: standard system'], [3, false, null], [4, true, 'Option 2: premium system']]);
});

Deno.test('a section heading with no option word is a heading too: the rule is the shape, not a word', () => {
  const lines = [head(1, 'GROUND FLOOR'), item(2, 'Aluminium sliding windows, Schuco AWS 70', GLAZED, 118500)];
  assertEquals(missingOf(lines), []);
});

Deno.test('a real item missing glass_type is still held, naming it on that item', () => {
  const { glass_type: _g, ...noGlass } = GLAZED;
  const lines = [head(1, 'Option 1: standard system'), item(2, 'Aluminium sliding windows, Schuco AWS 70', noGlass, 118500)];
  assertEquals(missingOf(lines), ['2:glass_type']);
});

Deno.test('KNOWN-BAD CONTROL: a line WITH a quantity or a price is an item, and is asked every spec', () => {
  const priced = [{ ...head(1, 'Option 1: standard system'), qty: 1 }, item(2, 'Aluminium sliding windows, Schuco AWS 70', GLAZED, 118500)];
  assert(missingOf(priced).includes('1:glass_type'), 'a line with a quantity must be asked: ' + missingOf(priced).join(','));
  // A last line with no quantity and no price labels nothing (no priced line follows): it stays a line, and is asked.
  const trailing = [item(1, 'Aluminium sliding windows, Schuco AWS 70', GLAZED, 118500), head(2, 'Glass to be clear')];
  assert(missingOf(trailing).includes('2:glass_type'), 'an unpriced line with no item under it is asked: ' + missingOf(trailing).join(','));
});

Deno.test('the quotation review (rule 8) no longer holds the two-option quotation for its headings', () => {
  const w = { lines: TWO_OPTIONS.map((l) => ({ description: l.description, qty: l.qty ?? null, unit: l.unit ?? null, unit_price: l.unit_price ?? null, amount: l.amount ?? null, spec: l.spec ?? null, spec_source: l.spec_source ?? null })),
    lead_time: TERMS.lead_time, warranty: TERMS.warranty, validity: '30 days', terms_spec: TERMS.terms_spec, price_ex_vat: 118500, amount: 118500, vat_treatment: 'exclusive',
    option_totals: { 1: 118500, 2: 142000 }, boq_excluded: {}, qty_explained: {} } as unknown as Working;
  const r = reviewQuotation({ id: 'zz', category: 'aluminium', spec: null, boq_rows: [] } as never, w);
  assertEquals(r.issues.filter((i) => i.code === 'spec').map((i) => `${i.line_no}:${i.attr}`), []);
});
