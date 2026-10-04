// Prevented by: a quote template that stores a price (the founder removed reusable price lists).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { cleanTemplate, statesAPrice } from './quote_template.ts';

Deno.test('price fields on the input are dropped, never stored', () => {
  const r = cleanTemplate({ name: 'Tiling', amount: 5000, unit_price: 45, line_headings: [{ description: 'Floor tiling', qty: 10, unit_price: 45, amount: 450 }], warranty: '1 year' });
  assert(r.ok);
  if (!r.ok) return;
  assertEquals(Object.keys(r.template).sort(), ['exclusions', 'inclusions', 'line_headings', 'name', 'payment_terms', 'terms', 'validity', 'warranty']);
  assertEquals(r.template.line_headings, ['Floor tiling']);
  assert(!JSON.stringify(r.template).includes('45'));
});

Deno.test('a price written into any text is refused', () => {
  for (const s of ['AED 45', '1,200 dhs', 'Tiling 45/m2', '300 درهم', 'Paint USD 20', '45 AED per sqm', '500/-'])
    for (const k of ['line_headings', 'terms', 'payment_terms', 'inclusions', 'name']) {
      const r = cleanTemplate({ name: 'Template', [k]: k === 'line_headings' ? [s] : s });
      assert(!r.ok && r.code === 'template_has_price', `${k}: ${s}`);
    }
});

Deno.test('terms that are not prices pass', () => {
  for (const s of ['50% advance, 50% on completion', '30 days', '1 year on workmanship', 'Excludes MEP works', 'Grade 60 rebar, 12 mm'])
    assert(!statesAPrice(s), s);
  assert(cleanTemplate({ name: 'Fit-out', payment_terms: '50% advance', validity: '30 days' }).ok);
});

Deno.test('the SQL check refuses the same prices (kept in step)', async () => {
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/supplier_quote_templates_carry_structure_never_price.sql', import.meta.url));
  assert(/not public\.fn_text_states_a_price/.test(sql));
  // no price-shaped column exists on the table
  const table = sql.slice(sql.indexOf('create table'), sql.indexOf(');', sql.indexOf('create table')));
  assert(!/\b(amount|price|unit_price|rate|total|qty)\b/i.test(table.replace(/fn_text_states_a_price/g, '')), table);
});
