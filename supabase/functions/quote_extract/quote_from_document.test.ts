// quote_from_document — a supplier's quotation file read with no model.
// deno test --no-lock supabase/functions/quote_extract/quote_from_document.test.ts
//
// A CSV quotation with a letterhead, priced lines, VAT and a grand total must give the grand total
// (not the VAT, not a single line), every priced line, and must mask the
// supplier's own company name, phone and email, since the customer pays to reveal who quoted.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted, quoteText, rowText } from './quote_from_document.ts';

const CSV = [
  'ZZ DEMO Tiling Contracting LLC,,,,',
  'Tel +971 50 123 4567 · sales@zzdemo.example.invalid,,,,',
  ',,,,',
  'Description,Qty,Unit,Rate (AED),Amount (AED)',
  'Porcelain tiles 600x600 supply and fix,120,sqm,85,10200',
  'Skirting 100mm,45,m,20,900',
  'Subtotal,,,,11100',
  'VAT 5%,,,,555',
  'Grand Total,,,,11655',
  'Lead time: 3 weeks from approval,,,,',
  'Validity: 30 days,,,,',
].join('\n');

// 14 Sep 2026: `amount` is now the price EXCLUDING VAT (founder: VAT details are hidden from the
// customer; the ex-VAT price is compared and charged on). It was the grand total, 11655, before.
Deno.test('a CSV quotation gives the ex-VAT price, the priced lines and the terms, with the supplier masked', async () => {
  const r = await readDocument(new TextEncoder().encode(CSV), 'quote.csv', 'text/csv');
  assert(r.ok, JSON.stringify(r));
  const p = quoteFromExtracted(r, ['ZZ DEMO Tiling']);
  assertEquals([p.amount, p.price_ex_vat, p.subtotal, p.vat_amount, p.total_incl_vat, p.vat_treatment], [11100, 11100, 11100, 555, 11655, 'exclusive']);
  assertEquals(p.line_items.map((l) => [l.description, l.amount]), [['Porcelain tiles 600x600 supply and fix', 10200], ['Skirting 100mm', 900]]);
  const all = JSON.stringify({ ...p, masked_terms: [] });
  assert(!all.includes('ZZ DEMO Tiling') && !all.includes('123 4567') && !all.includes('zzdemo'), 'supplier identity reached the proposal');
  assert(p.masked_terms.includes('ZZ DEMO Tiling'));
  // A reasoned term that carries the supplier's identity is masked like every other field.
  const q = quoteFromExtracted(r, ['ZZ DEMO Tiling'], { conditions: 'Installation by ZZ DEMO Tiling team, call +971 50 123 4567' });
  assert(!q.conditions.includes('ZZ DEMO Tiling') && !q.conditions.includes('123 4567'), q.conditions);
});

// 21 Sep 2026 (customer audit, finding 12): the audited CSV's note rows were split on their commas
// and joined back with spaces, so the customer's PDF read "electrical fittings painting of walls
// scaffolding above 4m" and "50% advance 50% on completion".
Deno.test('a note row the CSV reader split on its commas keeps them; a priced line is unchanged', async () => {
  const csv = ['Description,Qty,Unit,Rate,Amount', 'Knauf gypsum false ceiling 12.5mm with cove lighting detail,180,m2,95,17100', 'Total,,,,17100',
    'Warranty: 2 years materials and workmanship', 'Payment terms: 50% advance, 50% on completion', 'Exclusions: electrical fittings, painting of walls, scaffolding above 4m'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quotation-final.csv', 'text/csv');
  assert(r.ok, JSON.stringify(r));
  // The note rows keep their commas in the text the reasoning reads (quoteText)...
  const text = quoteText(r);
  assert(text.includes('Exclusions: electrical fittings, painting of walls, scaffolding above 4m'), text);
  assert(text.includes('Payment terms: 50% advance, 50% on completion'), text);
  // ...and no term is read from a label by this module any more (founder_instruction 886-903): with no
  // reasoned terms passed in, the terms stay empty for the supplier to type.
  const bare = quoteFromExtracted(r, []);
  assertEquals([bare.exclusions, bare.payment_terms, bare.warranty, bare.lead_time, bare.validity, bare.conditions], ['', '', '', '', '', '']);
  // The reasoned terms are applied as given, trailing punctuation trimmed.
  const p = quoteFromExtracted(r, [], { exclusions: 'electrical fittings, painting of walls, scaffolding above 4m.', payment_terms: '50% advance, 50% on completion', warranty: '2 years materials and workmanship' });
  assertEquals(p.exclusions, 'electrical fittings, painting of walls, scaffolding above 4m');
  assertEquals(p.payment_terms, '50% advance, 50% on completion');
  assertEquals(p.warranty, '2 years materials and workmanship');
  assertEquals(p.line_items.map((l) => [l.description, l.amount]), [['Knauf gypsum false ceiling 12.5mm with cove lighting detail', 17100]]);
  // 10 Nov 2026 (founder ledger 1589): what the customer reads of the line names no brand, and keeps its origin and spec.
  // (The tier rides in front when _shared/quote_generalise.ts knows it: "premium German brand ...", ledger 1589's
  // '<tier> <origin> brand'. This said the exact string without the tier and failed on main once the tier was added.)
  assert(/^(?:premium |mid-range |economy )?German brand gypsum false ceiling 12\.5mm with cove lighting detail$/.test(String(p.line_items[0].customer_description)), String(p.line_items[0].customer_description));
  assert(p.masked_terms.includes('Knauf'), JSON.stringify(p.masked_terms));
  assertEquals(rowText(['Exclusions: a', ' b', ' c', '', '']), 'Exclusions: a, b, c');
  assertEquals(rowText(['Skirting 100mm', '45', 'm', '20', '900']), 'Skirting 100mm 45 m 20 900');
});

Deno.test('a TRN and a licence number in the file are masked; the TRN is kept for the record only', async () => {
  const csv = ['Description,Qty,Unit,Rate,Amount', 'Porcelain tiles 600x600 supply and fix TRN 100-2345-6789-0003,120,sqm,85,10200', 'Grand Total excluding VAT,,,,10200', 'Trade Licence No. 1234567,,,,', 'Validity: 30 days,,,,'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quote.csv', 'text/csv');
  assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals(p.trn, '100234567890003');
  assertEquals(p.vat_treatment, 'exclusive');
  const shown = JSON.stringify(p.line_items);
  assert(!/2345|1234567/.test(shown), shown);
});

Deno.test('two options in one file come back as two options with their own totals', async () => {
  const csv = ['Description,Qty,Unit,Rate,Amount', 'Option 1 - Daikin,,,,', 'Ducted split 2.5 TR Daikin,2,nos,5000,10000', 'Total,,,,10000', 'Option 2 - Gree,,,,', 'Ducted split 2.5 TR Gree,2,nos,4000,8000', 'Total,,,,8000', 'Prices exclude VAT,,,,'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quote.csv', 'text/csv');
  assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals(p.options, [{ option_no: 1, amount: 10000 }, { option_no: 2, amount: 8000 }]);
  assertEquals(p.line_items.filter((l) => l.amount != null).map((l) => l.option), [1, 2]);
});

Deno.test('a quotation with no readable price reports no amount rather than inventing one', async () => {
  const r = await readDocument(new TextEncoder().encode('We are pleased to quote.\nPlease call us.\n'), 'quote.txt', 'text/plain');
  assert(r.ok);
  assertEquals(quoteFromExtracted(r).amount, null);
});

// Rulings 1207/1208 (13 Oct 2026): a discount row is the supplier's discount — not a priced line, not a condition —
// and the ex-VAT price is the price AFTER it. Before, "Discount,,,,-300" was read as a priced line and the
// subtotal before the discount (2,000) became the price the fee was taken on.
Deno.test('a discount row: gross, discount and the after-discount ex-VAT price, with VAT as stated', async () => {
  const csv = ['Description,Qty,Unit,Rate (AED),Amount (AED)', 'Gypsum partition,20,sqm,100,2000', 'Subtotal,,,,2000',
    'Special discount 15%,,,,-300', 'Net total after discount,,,,1700', 'VAT 5%,,,,85', 'Grand Total,,,,1785'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quote.csv', 'text/csv'); assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals(p.line_items.map((l) => l.description), ['Gypsum partition']);
  assertEquals([p.gross_amount, p.discount_amount, p.price_ex_vat, p.amount, p.vat_amount, p.total_incl_vat, p.vat_treatment], [2000, 300, 1700, 1700, 85, 1785, 'exclusive']);
  assertEquals(p.discount_label, 'Special discount 15%');
  assert(!/discount/i.test(p.conditions));
});
Deno.test('a discount written after the only total, prices excluding VAT: the fee base is after the discount', async () => {
  const csv = ['Description,Qty,Unit,Rate (AED),Amount (AED)', 'Gypsum partition,20,sqm,100,2000', 'Total,,,,2000', 'Discount,,,,300', 'Prices exclude VAT,,,,'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quote.csv', 'text/csv'); assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals([p.gross_amount, p.discount_amount, p.price_ex_vat, p.vat_treatment], [2000, 300, 1700, 'exclusive']);
});

// QA walk, 19 Oct 2026: the supplier's quotation PDF (the walk's own sample, built here the same way) was priced
// at AED 1, because "Total Option 1: AED 11730" gave the option's number as the total; and a two-option PDF came
// back as one quotation. Both are the text path (a PDF's text layer has no table).
import { demoPdfPages } from '../../../scripts/lib/demo_pdf.mjs';
const qaPdf = (options: { title: string; lines: [string, number, number][] }[]) => demoPdfPages([[
  ['ZZ DEMO Painting LLC - Quotation', 16], ['Prices in AED, excluding VAT. Validity: 30 days. Lead time: 3 weeks.', 10],
  ...options.flatMap((o) => [[o.title, 13], ...o.lines.map((l) => [`${l[0]}   ${l[1]} m2 x ${l[2]} = ${l[1] * l[2]}`, 10]),
    [`Total ${o.title}: AED ${o.lines.reduce((s, l) => s + l[1] * l[2], 0)}`, 11]]),
]]) as unknown as Uint8Array;

Deno.test('the walk\'s one-option quotation PDF is priced at its total, never at the option number', async () => {
  const r = await readDocument(qaPdf([{ title: 'Option 1', lines: [['Jotun Fenomastic matt emulsion 2 coats internal walls', 450, 21], ['Jotun Fenomastic matt emulsion 2 coats ceilings', 120, 19]] }]), 'quotation.pdf', 'application/pdf');
  assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals(p.amount, 11730);
});

Deno.test('the walk\'s two-option quotation PDF comes back as two options with their own totals', async () => {
  const r = await readDocument(qaPdf([
    { title: 'Option 1 - Jotun Fenomastic', lines: [['Jotun Fenomastic matt emulsion 2 coats internal walls', 450, 21], ['Jotun Fenomastic matt emulsion 2 coats ceilings', 120, 19]] },
    { title: 'Option 2 - National Paints', lines: [['National Paints matt emulsion 2 coats internal walls', 450, 16], ['National Paints matt emulsion 2 coats ceilings', 120, 15]] }]), 'quotation.pdf', 'application/pdf');
  assert(r.ok);
  const p = quoteFromExtracted(r);
  assertEquals(p.options, [{ option_no: 1, amount: 11730 }, { option_no: 2, amount: 9000 }]);
});

Deno.test('a label number is never the figure: option, item, no., #, and a percentage', async () => {
  const { figureAfter } = await import('./quote_from_document.ts');
  assertEquals(figureAfter(' Option 1: AED 11,730'), 11730);
  assertEquals(figureAfter(' for item 3 - AED 950'), 950);
  assertEquals(figureAfter(' (No. 2) 4,200.50'), 4200.5);
  assertEquals(figureAfter(' incl. 5% VAT: 1,050'), 1050);
  assertEquals(figureAfter(': AED 12,450.00'), 12450);
});

// #1562 review: a year, a reference or a quantity with its unit is never the price; the figure with the currency is.
Deno.test('a year, a reference and a quantity with its unit are never the total', async () => {
  const { figureAfter } = await import('./quote_from_document.ts');
  assertEquals(figureAfter(' (2026): AED 5,000'), 5000);
  assertEquals(figureAfter(' QD-10234: AED 500'), 500);
  assertEquals(figureAfter(' 450 m2: AED 9,450'), 9450);
  assertEquals(figureAfter(': 9,450 AED'), 9450);
});

const textQuote = async (lines: string[]) => {
  const r = await readDocument(new TextEncoder().encode(lines.join('\n')), 'quote.txt', 'text/plain'); assert(r.ok);
  return quoteFromExtracted(r);
};
Deno.test('held, never guessed: a total with no currency', async () => {
  const p = await textQuote(['Gypsum partition 20 m2 @ 100 = 2000', 'Total: 2400']);   // no currency, and the lines do not add up to it
  assertEquals(p.amount, null); assertEquals(p.review_reason, 'total_without_currency');
});
Deno.test('held, never guessed: two totals that disagree with nothing to choose between them', async () => {
  const p = await textQuote(['Gypsum partition 20 m2 @ AED 100 = AED 2000', 'Total: AED 2000', 'Total: AED 2400']);
  assertEquals(p.amount, null); assertEquals(p.review_reason, 'conflicting_totals');
});
Deno.test('a grand total among other totals decides, and is taken', async () => {
  const p = await textQuote(['Gypsum partition 20 m2 @ AED 100 = AED 2000', 'Total: AED 2000', 'Grand total: AED 2000']);
  assertEquals(p.amount, 2000); assertEquals(p.review_reason ?? null, null);
});
Deno.test('held, never guessed: an option total that is not the sum of its lines', async () => {
  const r = await readDocument(qaPdf([
    { title: 'Option 1 - Jotun Fenomastic', lines: [['Jotun Fenomastic matt emulsion 2 coats internal walls', 450, 21]] },
    { title: 'Option 2 - National Paints', lines: [['National Paints matt emulsion 2 coats internal walls', 450, 16]] }]).map((x) => x) as unknown as Uint8Array, 'quotation.pdf', 'application/pdf');
  assert(r.ok);
  // tamper the stated option-2 total so it disagrees with its line (7200)
  const tampered = { ...r } as typeof r;
  const p0 = quoteFromExtracted(r); assertEquals(p0.options.length, 2);
  const text = (r as unknown as { text?: string }).text;
  if (typeof text === 'string') (tampered as unknown as { text: string }).text = text.replace('AED 7200', 'AED 7900');
  const p = quoteFromExtracted(tampered);
  assertEquals(p.review_reason, 'option_total_mismatch'); assertEquals(p.amount, null); assertEquals(p.options, []);
});
Deno.test('a total with no currency is taken when its priced lines add up to it', async () => {
  const p = await textQuote(['Gypsum partition 20 m2 @ 100 = 2000', 'Paint 100 m2 @ 12 = 1200', 'Total: 3200']);
  assertEquals(p.amount, 3200); assertEquals(p.review_reason ?? null, null);
});
Deno.test('lines that corroborate one currency-less total never hide a conflicting second total', async () => {
  const p = await textQuote(['Gypsum partition 20 m2 @ 100 = 2000', 'Paint 100 m2 @ 12 = 1200', 'Total: 3200', 'Total: 2400']);
  assertEquals(p.amount, null); assertEquals(p.review_reason, 'conflicting_totals');
});

// AUDIT OF 10 NOV 2026 (customer_support, founder ruling 1608): three readings that changed the price.
const readCsv = async (csv: string) => { const r = await readDocument(new TextEncoder().encode(csv), 'q.csv', 'text/csv'); assert(r.ok); return quoteFromExtracted(r, []); };

Deno.test('a decimal-comma price list ("3.000,00") is read as three thousand, not three', async () => {
  const p = await readCsv('Description,Qty,Unit,Rate (AED),Amount (AED)\nPump,2,no,"1.500,00","3.000,00"\nGrand Total,,,,"3.000,00"\n');
  assertEquals(p.line_items[0].amount, 3000);
  assertEquals(p.amount, 3000);
  const q = await readCsv('Description,Qty,Unit,Rate (AED),Amount (AED)\nChiller,1,no,"1.250.000","1.250.000"\nGrand Total,,,,"1.250.000"\n');
  assertEquals(q.amount, 1250000);
  // the ordinary shapes are unchanged
  assertEquals((await readCsv('Description,Qty,Unit,Rate (AED),Amount (AED)\nPump,2,no,"1,500.00","3,000.00"\nGrand Total,,,,"3,000.00"\n')).amount, 3000);
});

Deno.test('"Total incl. VAT" is the total, never the VAT amount', async () => {
  const p = await readCsv('Description,Qty,Unit,Rate (AED),Amount (AED)\nPump,2,no,1000,2000\nTotal incl. VAT,,,,2100\n');
  assertEquals(p.vat_amount, null);
  assertEquals(p.vat_treatment, 'inclusive');
});

Deno.test('a quotation priced in another currency is held for the supplier, never read as AED', async () => {
  const p = await readCsv('Description,Qty,Unit,Rate (USD),Amount (USD)\nPump set,2,no,1500,3000\nTotal USD,,,,3000\n');
  assertEquals([p.amount, p.price_ex_vat, p.review_reason], [null, null, 'foreign_currency']);
  // a quotation in AED that mentions another currency is read as it was
  assertEquals((await readCsv('Description,Qty,Unit,Rate (AED),Amount (AED)\nImported pump (USD list price converted),2,no,1500,3000\nGrand Total AED,,,,3000\n')).amount, 3000);
});
