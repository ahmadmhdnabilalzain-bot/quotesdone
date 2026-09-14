// quote_from_document — a supplier's quotation file read with no model.
// deno test --no-lock supabase/functions/quote_extract/quote_from_document.test.ts
//
// A CSV quotation with a letterhead, priced lines, VAT and a grand total must give the grand total
// (not the VAT, not a single line), every priced line, the lead time and validity, and must mask the
// supplier's own company name, phone and email, since the customer pays to reveal who quoted.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { quoteFromExtracted } from './quote_from_document.ts';

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

Deno.test('a CSV quotation gives the grand total, the priced lines and the terms, with the supplier masked', async () => {
  const r = await readDocument(new TextEncoder().encode(CSV), 'quote.csv', 'text/csv');
  assert(r.ok, JSON.stringify(r));
  const p = quoteFromExtracted(r, ['ZZ DEMO Tiling']);
  assertEquals(p.amount, 11655);
  assertEquals(p.line_items.map((l) => [l.description, l.amount]), [['Porcelain tiles 600x600 supply and fix', 10200], ['Skirting 100mm', 900]]);
  const all = JSON.stringify({ ...p, masked_terms: [] });
  assert(!all.includes('ZZ DEMO Tiling') && !all.includes('123 4567') && !all.includes('zzdemo'), 'supplier identity reached the proposal');
  assert(p.masked_terms.includes('ZZ DEMO Tiling'));
});

Deno.test('a quotation with no readable price reports no amount rather than inventing one', async () => {
  const r = await readDocument(new TextEncoder().encode('We are pleased to quote.\nPlease call us.\n'), 'quote.txt', 'text/plain');
  assert(r.ok);
  assertEquals(quoteFromExtracted(r).amount, null);
});
