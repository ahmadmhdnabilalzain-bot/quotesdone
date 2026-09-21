// quote_from_document — a supplier's quotation file read with no model.
// deno test --no-lock supabase/functions/quote_extract/quote_from_document.test.ts
//
// A CSV quotation with a letterhead, priced lines, VAT and a grand total must give the grand total
// (not the VAT, not a single line), every priced line, the lead time and validity, and must mask the
// supplier's own company name, phone and email, since the customer pays to reveal who quoted.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted, rowText } from './quote_from_document.ts';

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
});

// 21 Sep 2026 (customer audit, finding 12): the audited CSV's note rows were split on their commas
// and joined back with spaces, so the customer's PDF read "electrical fittings painting of walls
// scaffolding above 4m" and "50% advance 50% on completion".
Deno.test('a note row the CSV reader split on its commas keeps them; a priced line is unchanged', async () => {
  const csv = ['Description,Qty,Unit,Rate,Amount', 'Knauf gypsum false ceiling 12.5mm with cove lighting detail,180,m2,95,17100', 'Total,,,,17100',
    'Warranty: 2 years materials and workmanship', 'Payment terms: 50% advance, 50% on completion', 'Exclusions: electrical fittings, painting of walls, scaffolding above 4m'].join('\n');
  const r = await readDocument(new TextEncoder().encode(csv), 'quotation-final.csv', 'text/csv');
  assert(r.ok, JSON.stringify(r));
  const p = quoteFromExtracted(r, []);
  assertEquals(p.exclusions, 'electrical fittings, painting of walls, scaffolding above 4m');
  assertEquals(p.payment_terms, '50% advance, 50% on completion');
  assertEquals(p.warranty, '2 years materials and workmanship');
  assertEquals(p.line_items.map((l) => [l.description, l.amount]), [['Knauf gypsum false ceiling 12.5mm with cove lighting detail', 17100]]);
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
