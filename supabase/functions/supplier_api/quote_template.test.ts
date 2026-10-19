// Prevented by: a quote template that stores a price (the founder removed reusable price lists).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { cleanTemplate, PRICE_PATTERN, statesAPrice } from './quote_template.ts';

Deno.test('price fields on the input are dropped, never stored', () => {
  const r = cleanTemplate({ name: 'Tiling', amount: 5000, unit_price: 45, line_headings: [{ description: 'Floor tiling', qty: 10, unit_price: 45, amount: 450 }], warranty: '1 year' });
  assert(r.ok);
  if (!r.ok) return;
  assertEquals(Object.keys(r.template).sort(), ['exclusions', 'inclusions', 'line_headings', 'name', 'payment_terms', 'terms', 'validity', 'warranty']);
  assertEquals(r.template.line_headings, ['Floor tiling']);
  assert(!JSON.stringify(r.template).includes('45'));
});

// Every price shape the review of #1179 found getting through, plus the original ones. A word
// boundary let the glued forms (AED45, 45AED, Dh45) through; the symbols and "per" were not matched.
export const PRICES = [
  'AED 45', 'AED45', '45AED', '45 AED', 'Dh45', 'dh 45', '1,200 dhs', '45 dirhams', 'USD 20', 'Paint USD 20',
  '$45', '$ 45', '45$', '€45', '45 €', '£45', '45 euros', 'EUR45', '300 درهم', 'درهم 300',
  '٤٥ درهم', 'درهم ٤٥', 'AED ٤٥', '۴۵ AED', '٤٥/m2',
  'Tiling 45/m2', '45 / sqm', '45 per sqm', '45 per m2', '12 per unit', '45 AED per sqm', '500/-',
];
export const NOT_PRICES = [
  '50% advance, 50% on completion', '30 days', '1 year on workmanship', 'Excludes MEP works',
  'Grade 60 rebar, 12 mm', 'width 5 m', 'Validity 30 days from date', '50 per cent on order',
  'Payment within 45 days', 'Saradar works, 2 floors', 'Thickness 20 mm', '٤٥ يوم', 'Euro-standard fittings, 3 sets',
];

Deno.test('a price written into any text is refused', () => {
  for (const s of PRICES) {
    assert(statesAPrice(s), `not refused: ${s}`);
    for (const k of ['line_headings', 'terms', 'payment_terms', 'inclusions', 'name']) {
      const r = cleanTemplate({ name: 'Template', [k]: k === 'line_headings' ? [s] : s });
      assert(!r.ok && r.code === 'template_has_price', `${k}: ${s}`);
    }
  }
});

Deno.test('terms that are not prices pass', () => {
  for (const s of NOT_PRICES) assert(!statesAPrice(s), s);
  assert(cleanTemplate({ name: 'Fit-out', payment_terms: '50% advance', validity: '30 days' }).ok);
});

// The SQL CHECK and this file run ONE pattern. Comparing the sources is the parity: the SQL literal
// must equal PRICE_PATTERN character for character, both are applied case-insensitively (~* and flag
// i), and the pattern may use only constructs JavaScript and Postgres ARE read identically. \b and
// \y mean different things in the two engines; lookbehind, named groups, backreferences, \d / \w
// (Unicode in JS with flag u only) and inline flags are refused so the equality cannot hide a
// difference in meaning. A read-only run of PRICES and NOT_PRICES through fn_text_states_a_price's
// pattern on production gave the same verdict for every case (recorded in the PR).
Deno.test('the SQL check runs the same pattern as statesAPrice, character for character', async () => {
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/supplier_quote_templates_carry_structure_never_price.sql', import.meta.url));
  const fn = sql.slice(sql.indexOf('create or replace function public.fn_text_states_a_price'), sql.indexOf('$$;'));
  const m = fn.match(/coalesce\(p, ''\) ~\* '([^']*)'/);
  assert(m, 'fn_text_states_a_price no longer reads coalesce(p, \'\') ~* \'<pattern>\'');
  assertEquals(m![1], PRICE_PATTERN);
  for (const bad of [/\\[byBYdDwWmM<>]/, /\(\?<[=!]/, /\(\?</, /\\[1-9]/, /\(\?[a-z]+\)/])
    assert(!bad.test(PRICE_PATTERN), `the pattern uses ${bad}, which the two engines read differently`);
  assert(/not public\.fn_text_states_a_price/.test(sql));
  // no price-shaped column exists on the table
  const table = sql.slice(sql.indexOf('create table'), sql.indexOf(');', sql.indexOf('create table')));
  assert(!/\b(amount|price|unit_price|rate|total|qty)\b/i.test(table.replace(/fn_text_states_a_price/g, '')), table);
});
