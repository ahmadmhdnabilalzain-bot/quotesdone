// pdf_text / receipt_parse — the checks that matter for a receipt nobody can afford to get wrong.
//
// Two properties are load-bearing here and both are asserted with a POSITIVE CONTROL, because a
// parser that returns '' for everything would pass a "refuses garbage" test on its own:
//   * a PDF with a real text layer IS read (uncompressed and FlateDecode), and the amount, the 5%
//     VAT and the TRN come back off it;
//   * a PDF whose text layer is glyph indices from a font we cannot map is NOT read — looksLikeText
//     refuses it — because garbage containing digits is how a fabricated amount reaches the ledger.
// deno test supabase/functions/_shared/pdf_text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfText, looksLikeText } from './pdf_text.ts';
import { parseReceipt, parseVat, parseTrn } from './receipt_parse.ts';

const LATIN1 = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);

/** A minimal PDF carrying one content stream. `filter` picks raw or FlateDecode. */
async function makePdf(lines: string[], filter: 'none' | 'flate'): Promise<Uint8Array> {
  const content = 'BT /F1 12 Tf 72 720 Td\n' + lines.map((l) => `(${l.replace(/([()\\])/g, '\\$1')}) Tj T*`).join('\n') + '\nET\n';
  let body = LATIN1(content);
  let dict = `<< /Length ${body.length} >>`;
  if (filter === 'flate') {
    const cs = new CompressionStream('deflate');
    const buf = await new Response(new Blob([LATIN1(content) as BlobPart]).stream().pipeThrough(cs)).arrayBuffer();
    body = new Uint8Array(buf);
    dict = `<< /Filter /FlateDecode /Length ${body.length} >>`;
  }
  const head = LATIN1(`%PDF-1.4\n1 0 obj\n${dict}\nstream\n`);
  const tail = LATIN1('\nendstream\nendobj\ntrailer\n%%EOF\n');
  const out = new Uint8Array(head.length + body.length + tail.length);
  out.set(head, 0); out.set(body, head.length); out.set(tail, head.length + body.length);
  return out;
}

const UAE_INVOICE = [
  'DESERT SUPPLIES TRADING LLC',
  'TAX INVOICE',
  'TRN: 100123456700003',
  'Invoice date: 2026-09-03',
  'Subtotal: AED 100.00',
  'VAT (5%): AED 5.00',
  'Total: AED 105.00',
];

Deno.test('an uncompressed PDF text layer is read', async () => {
  const t = await pdfText(await makePdf(UAE_INVOICE, 'none'));
  assert(t.includes('TAX INVOICE'), 'expected the text layer, got: ' + JSON.stringify(t.slice(0, 200)));
  assert(t.includes('AED 105.00'));
});

Deno.test('a FlateDecode PDF text layer is read (positive control for the inflater)', async () => {
  const t = await pdfText(await makePdf(UAE_INVOICE, 'flate'));
  assert(t.includes('TRN: 100123456700003'), 'expected inflated text, got: ' + JSON.stringify(t.slice(0, 200)));
  assert(t.includes('VAT (5%)'));
});

Deno.test('a UAE tax invoice read out of the PDF books its amount, VAT and TRN', async () => {
  const body = await pdfText(await makePdf(UAE_INVOICE, 'flate'));
  const r = parseReceipt({ subject: 'FW: Invoice', body, vendor: 'Desert Supplies', period: 'one_off', today: '2026-09-09' });
  assert(r, 'the receipt should parse');
  assertEquals(r!.amount, 105);
  assertEquals(r!.currency, 'AED');
  assertEquals(r!.vat, 5);
  assertEquals(r!.trn, '100123456700003');
  assertEquals(r!.date, '2026-09-03');
  assertEquals(r!.vendor, 'Desert Supplies');   // reasoned upstream and carried, never derived from the domain
});

Deno.test('VAT is read, never computed, and a TRN is never inferred from a bare number', () => {
  assertEquals(parseVat('Total: AED 105.00', 105), null);          // no VAT line = no VAT
  assertEquals(parseVat('VAT (5%): AED 5.00', 105)?.amount, 5);
  assertEquals(parseVat('VAT: AED 200.00', 105), null);            // larger than the total: not tax
  assertEquals(parseTrn('Order 100123456700003 shipped'), null);   // unlabelled: not a TRN
  assertEquals(parseTrn('TRN 100123456700003'), '100123456700003');
  assertEquals(parseTrn('TRN: 1234567890'), null);                 // 10 digits is not a TRN
});

Deno.test('a text layer we cannot map is refused, so no amount is invented from it', async () => {
  // what an Identity-H subset font actually yields: glyph indices, not letters
  const glyphs = Array.from({ length: 60 }, (_v, i) => String.fromCharCode(1 + (i % 25))).join('');
  const pdf = await makePdf([glyphs + ' 105 00'], 'none');
  assertEquals(await pdfText(pdf), '');
  assert(!looksLikeText(glyphs));
  assert(looksLikeText('Total: AED 105.00 paid on 3 September 2026'));
});

Deno.test('a non-PDF and an encrypted PDF read as nothing, not as a guess', async () => {
  assertEquals(await pdfText(LATIN1('GIF89a not a pdf at all')), '');
  assertEquals(await pdfText(LATIN1('%PDF-1.6\n/Encrypt 9 0 R\nstream\n(Total: USD 99.00) Tj\nendstream')), '');
});
