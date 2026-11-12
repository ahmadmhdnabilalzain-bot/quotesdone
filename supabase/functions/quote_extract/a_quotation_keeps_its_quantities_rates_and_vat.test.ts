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
import { linesFromText, originOf, quoteFromExtracted, totalsFromText, unkern } from './quote_from_document.ts';
import { generaliseDeep, generaliseLine } from '../_shared/quote_generalise.ts';
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

// THE ORIGIN IS A COUNTRY, NEVER THE BRAND BESIDE IT (review of 12 Nov 2026, blocking finding 2).
Deno.test('a stated origin is read as a known country only, and the customer door keeps only the country', () => {
  for (const [s, want] of [['Country of origin: Grohe Germany', 'Germany'], ['Origin: Daikin Thailand', 'Thailand'], ['Made in Germany Hansgrohe', 'Germany'],
    ['made in UAE by Al Noor Trading LLC', 'UAE'], ['Origin : RAK Ceramics UAE', 'UAE'], ['made in Dubai Investments Park', undefined]] as const) assertEquals(originOf(s), want, s);
  assertEquals(generaliseLine({ description: 'Basin mixer', country_of_origin: 'Grohe Germany' }).country_of_origin, 'Germany');
  assertEquals(generaliseLine({ description: 'Panel', country_of_origin: 'Al Noor Trading LLC' }).country_of_origin, '');
  assertEquals(generaliseDeep({ lines: [{ country_of_origin: 'Daikin Thailand' }] }).lines[0].country_of_origin, 'Thailand');
});

// THE REVIEW'S MONEY CASES (12 Nov 2026, finding 3). Reading kerned labels must never move the ex-VAT price: on every one of
// these the price compared and charged 3% on is the lines' 9,554, as main read it; and a rate is never a VAT amount.
const LINES = '1 PVC wall panels fire rated 34 m2 AED 180.00 AED 6,120.00\n2 Aluminium trims 48 m AED 22.00 AED 1,056.00\n3 Installation labour 34 m2 AED 45.00 AED 1,530.00\n4 Removal of old panels 1 lot AED 848.00 AED 848.00\n';
const DOCS: [string, string, number | null][] = [
  ['VAT in parentheses', LINES + 'Subtotal AED 9,554.00\nV A T (5%) AED 477.70\nGrand T otal AED 10,031.70', 477.7],
  ['no subtotal, VAT in parentheses', LINES + 'V A T (5%) AED 477.70\nGrand T otal AED 10,031.70', 477.7],
  ['"Prices exclude V A T 5%"', LINES + 'T otal AED 9,554.00\nPrices exclude V A T 5%.', null],
  ['"V A T 5% extra", no amount', LINES + 'Subtotal AED 9,554.00\nV A T 5% extra as applicable\nGrand T otal AED 9,554.00', null],
  ['T otal excl / incl', LINES + 'T otal excl. V A T AED 9,554.00\nV A T 5% AED 477.70\nT otal incl. V A T AED 10,031.70', 477.7],
  ['the fixture shape', LINES + 'Subtotal AED 9,554.00\nV A T 5% AED 477.70\nGrand T otal AED 10,031.70', 477.7],
  ['total only, inclusive', LINES + 'Grand T otal (incl. V A T) AED 10,031.70', null],
  ['VAT amount on the next line', LINES + 'TRN 100234567800003\nV A T 5%\nAED 477.70\nGrand T otal AED 10,031.70', 477.7],
  ['the fixture wording above the totals', 'Prices In AED, excluding V A T (V A T 5% shown separately)\n' + LINES + 'Subtotal AED 9,554.00\nV A T 5% AED 477.70\nGrand T otal AED 10,031.70', 477.7],
  ['"All prices exclude V A T 5%" above the totals', 'All prices exclude V A T 5%\n' + LINES + 'Subtotal AED 9,554.00\nV A T 5% AED 477.70\nGrand T otal AED 10,031.70', 477.7],
];
for (const [name, text, vat] of DOCS) {
  Deno.test(`money: ${name} compares at the lines' AED 9,554, VAT ${vat ?? 'not stated'}`, () => {
    const p = quoteFromExtracted({ ok: true, kind: 'pdf', text, tables: [], children: [] } as never, []);
    assertEquals(p.amount, 9554);
    assertEquals(p.vat_amount, vat);
  });
}
Deno.test('a total that names its VAT after the figure is still the total; a rate is never the VAT amount', () => {
  assertEquals(totalsFromText('Total AED 9,554.00 + V A T 5%').total, 9554);
  assertEquals(totalsFromText('TRN 100 234 567 800 003\nVAT 5%\nTotal AED 2,100.00').vat, null);
  assertEquals(totalsFromText('VAT (5%) AED 62.50').vat, 62.5);
});

// THE REVIEW'S LINE CASES (finding 4): nothing null is sent; a quantity x rate that is not the amount keeps only the amount;
// one figure after the unit is the amount (it was multiplied by the quantity: 320 m2 AED 30,400 read as 9,728,000).
Deno.test('a line keeps its amount; quantity and rate only when they multiply to it; nothing null is sent', () => {
  const t = (s: string) => linesFromText(s)[0];
  assertEquals(t('001 Gypsum board partition 320 m2 AED 30,400.00'), { description: 'Gypsum board partition', qty: '320 m2', amount: 30400, quantity: 320, unit: 'm2', unit_price: 95 });
  const bad = t('14 Mismatch line 10 nos 100.00 1,500.00');
  assertEquals([bad.amount, bad.qty, 'quantity' in bad, 'unit_price' in bad, !!bad.mismatch], [1500, '', false, false, true]);
  const ex = { ok: true, kind: 'xlsx', text: '', children: [], tables: [[['Description', 'Qty', 'Unit', 'Rate', 'Amount'], ['Mobilisation', '', '', '', '1,500.00'], ['PVC panels', '34', 'm2', '180', '6120']]] } as never;
  const lines = JSON.parse(JSON.stringify(quoteFromExtracted(ex, []).line_items));
  assertEquals(lines[0], { description: 'Mobilisation', qty: '', amount: 1500 }, 'a null quantity or rate was sent (stored as 0 by numOrNull)');
});

// ROUND 2 OF THE REVIEW (12 Nov 2026). 3a: one figure after a rate marker is the RATE ("320 m2 @ AED 95.00" is 30,400), one
// bare figure after the unit is the AMOUNT; with and without a stated total.
Deno.test('3a: "@ / x / at" before one figure makes it the rate; a bare figure is the amount', () => {
  const t = (s: string) => { const l = linesFromText(s)[0]; return [l.amount, l.quantity, l.unit_price]; };
  assertEquals(t('001 Gypsum board partition 320 m2 @ AED 95.00'), [30400, 320, 95]);
  assertEquals(t('2 Downlights 50 nos @ 120'), [6000, 50, 120]);
  assertEquals(t('3 Cable tray 40 m x AED 55.00'), [2200, 40, 55]);
  assertEquals(t('4 Paint 300 m2 at AED 12.50'), [3750, 300, 12.5]);
  assertEquals(t('5 Gypsum 320 m2 AED 30,400.00'), [30400, 320, 95]);
  const doc = (text: string) => quoteFromExtracted({ ok: true, kind: 'pdf', text, tables: [], children: [] } as never, []).amount;
  assertEquals(doc('Our offer:\n1 Gypsum board partition 320 m2 @ AED 95.00\n2 Downlights 50 nos @ AED 120.00\nPrices exclude VAT.'), 36400);
  assertEquals(doc('001 Gypsum board partition 320 m2 @ AED 95.00\nTotal AED 30,400.00'), 30400);
});

// 3b: a total that is the lines x 1.05 is NOT re-read as VAT-inclusive when the file says VAT is extra, or a non-VAT 5% row
// explains it; and when the reader does re-read a total, the supplier is told in plain words on his form (3c).
Deno.test('3b/3c: a 5% row or "VAT extra" keeps the stated total; a re-read total and a mismatched line are told to the supplier', () => {
  const doc = (text: string) => quoteFromExtracted({ ok: true, kind: 'pdf', text, tables: [], children: [] } as never, []);
  for (const tail of ['Contingency 5%: AED 477.70\nNet Total AED 10,031.70\nVAT extra.', 'Overheads 5% AED 477.70\nGrand T otal AED 10,031.70\nV A T extra as applicable',
    'Overheads and profit 5% AED 477.70\nTotal AED 10,031.70 (excluding VAT)\nVAT will be added at the prevailing rate.']) {
    const p = doc(LINES + tail);
    assertEquals([p.amount, p.vat_amount], [10031.7, null], tail);
    assertEquals(p.warnings, undefined, 'nothing was re-read, so nothing to tell');
  }
  const re = doc(LINES + 'Grand T otal (incl. V A T) AED 10,031.70');
  assertEquals(re.amount, 9554);
  assert(re.warnings?.some((w) => /AED 10,031\.70 is your priced lines plus 5% VAT/.test(w) && /AED 9,554\.00/.test(w)), JSON.stringify(re.warnings));
  const mm = doc('1 Valves 10 nos AED 100.00 AED 900.00\nTotal AED 900.00');
  assert(mm.warnings?.some((w) => /quantity times the rate is not the line amount/.test(w)), JSON.stringify(mm.warnings));
});
