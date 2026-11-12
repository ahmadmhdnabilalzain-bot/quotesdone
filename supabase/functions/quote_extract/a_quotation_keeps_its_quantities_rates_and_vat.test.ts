// A QUOTATION KEEPS ITS QUANTITIES, RATES AND VAT (sales_engineer, 12 Nov 2026; final audit customer_journey H3, fix group
// Q3, ledger 1642). The 8 live quotations of the audit's run d9a04dbc (fixtures/audit_2026_11_12_*.pdf, ZZ DEMO companies,
// every figure invented) each print Qty, Unit, Rate and Amount on every line and a VAT row. The reader kept the totals and
// lost the rest: quote_items.qty, unit, unit_price and country_of_origin were 0 of 56, quotes.vat_amount 0 of 8, so the
// customer's standardised quotation showed blank columns and fn_quote_structured_score failed every quote ("score 55").
// Causes: a line was built as {description, qty: "34 m2", amount} with the rate discarded; and the PDF text layer splits
// kerned letters ("V A T 5%", "Grand T otal"), so no VAT row was recognised.
//   deno test --node-modules-dir=none --allow-read --allow-env supabase/functions/quote_extract/a_quotation_keeps_its_quantities_rates_and_vat.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted, totalsFromText, unkern } from './quote_from_document.ts';
import { workingFromProposal } from '../supplier_api/quote_review/working.ts';

// [file, priced lines, ex-VAT total, VAT amount] as each PDF prints them (Subtotal, VAT 5%).
const QUOTES: [string, number, number, number][] = [
  ['wall_panels_Q1', 4, 9554, 477.7], ['wall_panels_Q2', 4, 7456, 372.8], ['wall_panels_Q3', 4, 12028, 601.4], ['wall_panels_Q5', 4, 10128, 506.4],
  ['villa_hvac_Q1', 10, 94820, 4741], ['villa_hvac_Q2', 10, 71966, 3598.3], ['villa_hvac_Q3', 10, 107099, 5354.95], ['villa_hvac_Q5', 10, 69188, 3459.4],
];
const read = async (name: string) => {
  const bytes = await Deno.readFile(new URL('fixtures/audit_2026_11_12_' + name + '.pdf', import.meta.url));
  const r = await readDocument(bytes, name + '.pdf', 'application/pdf');
  assert(r.ok, name + ': ' + JSON.stringify(r).slice(0, 200));
  return quoteFromExtracted(r as never, []);
};

for (const [name, n, exVat, vat] of QUOTES) {
  Deno.test(`${name}: every line keeps its quantity, unit and rate, and the VAT row is read`, async () => {
    const p = await read(name);
    const priced = p.line_items.filter((l) => l.amount != null);
    assertEquals(priced.length, n);
    for (const l of priced) {
      assert(l.quantity != null && l.quantity > 0, `${name} "${l.description}": no quantity (${l.qty})`);
      assert(l.unit, `${name} "${l.description}": no unit (${l.qty})`);
      assert(l.unit_price != null && l.unit_price > 0, `${name} "${l.description}": no rate`);
      assert(Math.abs(l.quantity! * l.unit_price! - l.amount!) <= 0.01, `${name} "${l.description}": ${l.quantity} x ${l.unit_price} is not ${l.amount}`);
    }
    assertEquals([p.amount, p.price_ex_vat, p.vat_amount], [exVat, exVat, vat], 'the ex-VAT price must not move; the VAT amount is the printed one');
    // the chat's working copy carries the file's own rate and unit
    const w = workingFromProposal(p);
    assertEquals(w.lines.filter((l) => l.amount != null).map((l) => [l.unit, l.unit_price]), priced.map((l) => [l.unit, l.unit_price]));
    assertEquals(w.vat_amount, vat);
  });
}

Deno.test('a line that says where it is made carries that origin; a line that does not, carries none', async () => {
  const p = await read('villa_hvac_Q1');
  const units = p.line_items.filter((l) => /ducted split unit/i.test(l.description));
  assertEquals(units.map((l) => l.country_of_origin), ['Thailand', 'Thailand', 'Thailand']);
  assertEquals(p.line_items.find((l) => /GI ductwork/.test(l.description))?.country_of_origin, undefined, 'the quote-level origin was spread onto local ductwork');
  const panels = (await read('wall_panels_Q1')).line_items.find((l) => /PVC wall panels, fire rated/.test(l.description));
  assertEquals(panels?.country_of_origin, 'Germany');
});

Deno.test('kerned labels are matched as words; ordinary text is left alone', () => {
  assertEquals(unkern('V A T 5% AED 477.70'), 'VAT 5% AED 477.70');
  assertEquals(unkern('Grand T otal AED 10,031.70'), 'Grand Total AED 10,031.70');
  assertEquals(unkern('W arranty 3 years'), 'Warranty 3 years');
  assertEquals(unkern('A supplier quoted. I agree.'), 'A supplier quoted. I agree.');
  const t = totalsFromText('Subtotal AED 9,554.00\nV A T 5% AED 477.70\nGrand T otal AED 10,031.70');
  assertEquals([t.subtotal, t.vat, t.total], [9554, 477.7, 10031.7]);
});
