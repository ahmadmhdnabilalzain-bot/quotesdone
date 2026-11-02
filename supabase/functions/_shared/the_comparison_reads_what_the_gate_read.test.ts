// THE COMPARISON READS WHAT THE GATE READ (sales_engineer, 2 Nov 2026).
//
// Measured: journey run 41450058264. Three quotes the hold gate had accepted (status submitted) were all counted
// on hold by quote_compare (on_hold=3, "needs at least two complete quotes"). The ranking re-checks every live quote
// with the same assessment (reveal_guard.ts heldQuoteIds), on the rows the gate persisted, but quote_compare built
// its own item rows and dropped spec_source. Everything the gate's reading wrote is honoured only with source
// 'reasoned' (assess.ts reasoned(): which line names the customer's glass and profile), so the re-check asked those
// components of the quote as a whole and held it. Pure: no database, no model.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { compareItem, heldQuoteIds } from './reveal_guard.ts';
import { assessQuote, READ, type Line } from './line_specs/assess.ts';

const SPEC = { customer_requirements: { version: 1, materials: [{ component: 'glass' }, { component: 'profile' }] } };
const STATED = { glass_thickness: '6mm + 12mm air + 6mm', profile_system: 'Schuco AWS 70', finish: 'RAL 9016 powder coated', standard: 'BS EN 14351-1', brand: 'Schuco', model: 'AWS 70',
  component_glass: 'double glazed glass unit 6mm + 12mm air + 6mm', component_profile: 'Schuco AWS 70 thermal break', [READ.names('glass')]: 'double glazed glass unit', [READ.names('profile')]: 'Schuco AWS 70 thermal break series' };
const reasoned = (s: Record<string, string>) => Object.fromEntries(Object.keys(s).map((k) => [k, 'reasoned']));
const QUOTE = (id: string, x: Record<string, unknown> = {}) => ({ id, status: 'submitted', lead_time: '21 days from order', warranty: '2 years', validity: '30 days', price_ex_vat: 124900,
  terms_spec: { installation: { included: 'yes', detail: 'within 10 working days of delivery', source: 'reasoned' }, warranty: { period: '2 years', coverage: 'manufacturing defects and workmanship', source: 'reasoned' } }, ...x });
// A quote_items row exactly as the gate persisted it (workflow.ts persistSpecs: spec + spec_source).
const ROW = (quote_id: string, spec: Record<string, string>) => ({ quote_id, line_no: 1, description: 'Aluminium sliding windows, Schuco AWS 70 thermal break series, double glazed glass unit 6mm + 12mm air + 6mm',
  qty: 40, unit: 'nos', unit_price: 3122, amount: 124900, spec, spec_source: reasoned(spec) });
// What quote_compare built before 2 Nov: its own row, spec without spec_source.
const OLD_MAPPING = (r: ReturnType<typeof ROW>) => { const { spec_source: _s, ...rest } = compareItem(r); return { ...rest, line_no: rest.line }; };

Deno.test('the gate accepts the quote on its persisted reading', () => {
  const r = ROW('q-ok', STATED);
  const a = assessQuote({ category: 'aluminium', lines: [r as unknown as Line], terms: QUOTE('q-ok') as never, requirements: SPEC.customer_requirements });
  assertEquals(a.missing.map((m) => m.attr), []);
});

Deno.test('a held, filled and accepted quote counts as complete in the comparison; a still-held one is excluded and named', () => {
  const { component_glass: _g, ...noGlass } = STATED;
  const rows = [{ quote: QUOTE('q-filled'), items: [ROW('q-filled', STATED)] }, { quote: QUOTE('q-c'), items: [ROW('q-c', STATED)] },
    { quote: QUOTE('q-held'), items: [ROW('q-held', noGlass)] }];
  const held = heldQuoteIds(rows.map((x) => ({ quote: x.quote, items: x.items.map((it) => ({ ...compareItem(it), line_no: it.line_no })) })), 'aluminium', SPEC);
  assertEquals([...held], ['q-held'], 'only the quote that does not state its glass is held');
});

Deno.test('KNOWN-BAD CONTROL: quote_compare\'s old row mapping (no spec_source) holds every accepted quote', () => {
  const rows = [{ quote: QUOTE('q-a'), items: [ROW('q-a', STATED)] }, { quote: QUOTE('q-b'), items: [ROW('q-b', STATED)] }];
  const held = heldQuoteIds(rows.map((x) => ({ quote: x.quote, items: x.items.map(OLD_MAPPING) })), 'aluminium', SPEC);
  assertEquals(held.size, 2, 'the control did not reproduce run 41450058264');
  assert(compareItem(ROW('q-a', STATED)).spec_source, 'the shared mapping carries spec_source');
});
