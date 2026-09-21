// document_expiry.test.ts — the deterministic expiry reader against the shapes it must handle.
//
//   deno test supabase/functions/_shared/document_expiry.test.ts
//
// The PDF here is built the way scripts/staging/fixtures/licence_pdf.mjs builds the staging
// licence (one page, Helvetica, a plain content stream), once uncompressed and once FlateDecode —
// the two framings a generated or printed-to-PDF UAE licence arrives in.
import { assertEquals } from 'jsr:@std/assert@1';
import { expiryFromText, parseDate, pdfText, readExpiry, textFromContent } from './document_expiry.ts';

const enc = new TextEncoder();
const esc = (s: string) => s.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');

async function pdf(lines: string[], flate = false): Promise<Uint8Array> {
  const body = ['BT', '/F1 11 Tf', '17 TL', '56 800 Td', ...lines.map((l) => `(${esc(l)}) Tj T*`), 'ET'].join('\n');
  let stream = enc.encode(body); let filter = '';
  if (flate) { stream = new Uint8Array(await new Response(new Blob([stream]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer()); filter = ' /Filter /FlateDecode'; }
  const head = enc.encode(`%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n5 0 obj\n<< /Length ${stream.length}${filter} >>\nstream\n`);
  const tail = enc.encode('\nendstream\nendobj\n%%EOF\n');
  const out = new Uint8Array(head.length + stream.length + tail.length);
  out.set(head); out.set(stream, head.length); out.set(tail, head.length + stream.length);
  return out;
}

const LICENCE = [
  'GOVERNMENT OF DUBAI', 'TRADE LICENCE / RUKHSA TIJARIYA',
  'Licence Number        : 1145872',
  'Legal Name            : ZZ DEMO Aluminium And Glass Works L.L.C',
  'Issue Date            : 14/03/2024',
  'Expiry Date           : 13/03/2027',
  'Tax Registration No   : 100447291500003',
  'This licence is valid until the expiry date shown above and must be',
];

Deno.test('parseDate: the printed shapes, day-first, nothing invented', () => {
  assertEquals(parseDate('13/03/2027'), '2027-03-13');
  assertEquals(parseDate('13-03-2027'), '2027-03-13');
  assertEquals(parseDate('2027-03-13'), '2027-03-13');
  assertEquals(parseDate('13 Mar 2027'), '2027-03-13');
  assertEquals(parseDate('13-MAR-2027'), '2027-03-13');
  assertEquals(parseDate('13 March 2027'), '2027-03-13');
  assertEquals(parseDate('March 13, 2027'), '2027-03-13');
  assertEquals(parseDate('31/02/2027'), null);
  assertEquals(parseDate('13/03/27'), null);
  assertEquals(parseDate('no date here'), null);
});

Deno.test('expiryFromText: the date AFTER an expiry keyword, never the issue date', () => {
  const r = expiryFromText(LICENCE.join('\n'));
  assertEquals(r?.expiry, '2027-03-13');
  assertEquals(r?.keyword, 'Expiry Date');
  // issue date alone is not an expiry
  assertEquals(expiryFromText('Issue Date : 14/03/2024\nSigned 01/01/2025'), null);
  // a keyword with no date beside it is skipped, not matched to a date far away
  assertEquals(expiryFromText('valid until the date shown on page 2\n' + 'x'.repeat(200) + '\n13/03/2027'), null);
  // insurance schedule wording
  assertEquals(expiryFromText('Period of insurance: from 01/01/2026 to 31/12/2026')?.expiry, '2026-01-01');
  // Arabic, including Arabic-Indic digits
  assertEquals(expiryFromText('تاريخ الانتهاء: ١٣/٠٣/٢٠٢٧')?.expiry, '2027-03-13');
  assertEquals(expiryFromText('صالحة حتى 2027-03-13')?.expiry, '2027-03-13');
  assertEquals(expiryFromText(''), null);
});

Deno.test('textFromContent: Tj, TJ arrays with kerning, hex strings, and line breaks', () => {
  const t = textFromContent('BT (Expiry Date) Tj T* [(13) -300 (/03/2027)] TJ ET <45786974> Tj');
  assertEquals(t.includes('Expiry Date'), true);
  assertEquals(t.includes('13 /03/2027'), true);
  assertEquals(t.includes('Exit'), true);
});

Deno.test('pdfText + readExpiry: plain and FlateDecode content streams read the same licence', async () => {
  for (const flate of [false, true]) {
    const bytes = await pdf(LICENCE, flate);
    const text = await pdfText(bytes);
    assertEquals(text?.includes('Expiry Date           : 13/03/2027'), true, `flate=${flate}`);
    const r = await readExpiry(bytes, 'application/pdf');
    assertEquals(r?.expiry, '2027-03-13', `flate=${flate}`);
  }
});

Deno.test('readExpiry: an image, a non-PDF and a PDF without an expiry all say null', async () => {
  assertEquals(await readExpiry(enc.encode('\x89PNG....'), 'image/png'), null);
  assertEquals(await readExpiry(enc.encode('hello'), 'application/pdf'), null);
  assertEquals(await readExpiry(await pdf(['GOVERNMENT OF DUBAI', 'Issue Date : 14/03/2024']), 'application/pdf'), null);
});
