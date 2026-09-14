// deno test supabase/functions/_shared/quote_line_compare.test.ts
// Per-line take-off differences are shown, normalised by unit rate — never hidden in a total.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { compareLines, totalsAtOurQuantities } from './quote_line_compare.ts';

const OURS = [
  { key: 'boq_smoke_detector', description: 'Smoke detector', unit: 'nos', qty: 20, qty_status: 'estimated_supplier_to_verify' },
  { key: 'boq_manual_call_point', description: 'Manual call point', unit: 'nos', qty: 10, qty_status: 'customer_confirmed' },
];
const QUOTES = [
  { supplier: 'Supplier A', lines: [{ key: 'boq_smoke_detector', qty: 20, unit_rate: 100 }, { key: 'boq_manual_call_point', qty: 10, unit_rate: 80 }] },
  { supplier: 'Supplier B', lines: [{ key: 'boq_smoke_detector', qty: 14, unit_rate: 110 }, { key: 'boq_manual_call_point', qty: 10, unit_rate: 70 }] },
];

Deno.test('a supplier counting fewer is flagged, not rewarded', () => {
  const c = compareLines(OURS, QUOTES);
  const smoke = c[0];
  assertEquals(smoke.suppliers.map((s) => s.vs_ours), ['same', 'lower']);
  assert(smoke.flags.some((f) => /Supplier B quotes 14 nos, 30% lower than our 20/.test(f)));
  assert(smoke.flags.some((f) => /differ from each other: 14 to 20/.test(f)));
  assert(smoke.flags.some((f) => /estimated from the drawing/.test(f)));
  assertEquals(smoke.cheapest_rate, 'Supplier A');
  assertEquals(c[1].flags, []);
  // At OUR quantities B's lower total disappears: A 20x100+10x80 = 2800, B 20x110+10x70 = 2900.
  const t = totalsAtOurQuantities(c);
  assertEquals([t['Supplier A'].total, t['Supplier B'].total], [2800, 2900]);
});
