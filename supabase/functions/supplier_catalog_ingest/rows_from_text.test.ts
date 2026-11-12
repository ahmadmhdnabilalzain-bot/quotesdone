// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_catalog_ingest/rows_from_text.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { productsFromText } from './rows_from_text.ts';

Deno.test('a priced line is a product; totals, prose and unpriced lines are not', () => {
  const rows = productsFromText([
    'ZZ DEMO Trading - Price List 2026',
    'Porcelain tile 600x600 PT-6060 AED 45.50 / sqm',
    'Ceramic adhesive 20kg bag 32 AED',
    'Gypsum board 12mm',
    'Total AED 77.50',
    'Prices valid 30 days',
  ].join('\n'));
  assertEquals(rows.map((r) => [r.name, r.model, r.unit, r.price]), [
    ['Porcelain tile 600x600 PT-6060', 'PT-6060', 'sqm', 45.5],
    ['Ceramic adhesive 20kg bag', null, null, 32],
  ]);
});

Deno.test('Arabic dirham and thousands separators', () => {
  const [r] = productsFromText('مضخة مياه 1,250 درهم');
  assertEquals(r.price, 1250);
  assertEquals(r.name, 'مضخة مياه');
});
