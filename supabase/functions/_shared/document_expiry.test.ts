// document_expiry.test.ts — the deterministic expiry reader against the shapes it must handle.
//
//   deno test supabase/functions/_shared/document_expiry.test.ts
//
// The PDF here is built the way scripts/staging/fixtures/licence_pdf.mjs builds the staging
// licence (one page, Helvetica, a plain content stream), once uncompressed and once FlateDecode —
// the two framings a generated or printed-to-PDF UAE licence arrives in.
import { assertEquals } from 'jsr:@std/assert@1';
import { expiryFromText, licenceNameFromText, parseDate, pdfText, readExpiry, readLicenceName, textFromContent } from './document_expiry.ts';

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

// 24 Sep 2026: the licence's printed company name, for the sales engineer's name check.
Deno.test('licenceNameFromText: legal name first, same line only, null when unlabelled', () => {
  const lic = 'Trade Name            : Al Meydan Aluminium And Glass Works\nLegal Name            : Al Meydan Aluminium And Glass Works L.L.C\nExpiry Date : 13/03/2027';
  assertEquals(licenceNameFromText(lic), 'Al Meydan Aluminium And Glass Works L.L.C');
  assertEquals(licenceNameFromText('Trade Name: Nasser Metal Works'), 'Nasser Metal Works');
  assertEquals(licenceNameFromText('الاسم التجاري: الميدان للألمنيوم'), 'الميدان للألمنيوم');
  assertEquals(licenceNameFromText('Legal Name:\nExpiry 2027-01-01'), null);
  assertEquals(licenceNameFromText('Al Meydan Aluminium LLC'), null);
});

Deno.test('readLicenceName: reads the name off a text-layer licence PDF, null for an image', async () => {
  assertEquals(await readLicenceName(await pdf(['Legal Name : ZZ Demo Works L.L.C', 'Expiry Date : 13/03/2027'], true), 'application/pdf'), 'ZZ Demo Works L.L.C');
  assertEquals(await readLicenceName(new Uint8Array([0xff, 0xd8]), 'image/jpeg'), null);
});

// A SCANNED LICENCE STILL YIELDS ITS NAME (24 Sep 2026, sales_engineer): code reads no name off an image, so the
// stored scan goes to the vision model; a low-confidence read is not a name (the review then holds it).
import { licenceModelPayload, licenceNameFromModel } from './document_expiry.ts';

Deno.test('a scanned licence (image, no text layer) is sent from storage to the model when code read no name', async () => {
  const jpg = { bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]), mime: 'image/jpeg' };
  assertEquals(await readLicenceName(jpg.bytes, jpg.mime), null);
  const p = licenceModelPayload({}, jpg, null);
  assertEquals(p?.images.length, 1);
  assertEquals((p?.images[0] as { b64: string; mime: string }).mime, 'image/jpeg');
  assertEquals((p?.images[0] as { b64: string }).b64, btoa(String.fromCharCode(...jpg.bytes)));
  const pdf = licenceModelPayload({}, { bytes: new Uint8Array([37, 80, 68, 70]), mime: 'application/pdf' }, null);
  assertEquals(pdf?.file_b64, btoa('%PDF'));
  // Code already read the name, or nothing is stored: nothing to send. What the request carried always goes.
  assertEquals(licenceModelPayload({}, jpg, 'Al Meydan LLC'), null);
  assertEquals(licenceModelPayload({}, null, null), null);
  assertEquals(licenceModelPayload({ file_b64: 'QQ==', mime: 'image/png' }, jpg, 'x')?.file_b64, 'QQ==');
});

Deno.test('the model name counts only when confident and a real name', () => {
  assertEquals(licenceNameFromModel({ legal_name: ' Al Meydan Aluminium LLC ', confidence: 'high' }), 'Al Meydan Aluminium LLC');
  assertEquals(licenceNameFromModel({ legal_name: 'الميدان للألمنيوم', confidence: 'medium' }), 'الميدان للألمنيوم');
  assertEquals(licenceNameFromModel({ legal_name: 'Al Meydan LLC', confidence: 'low' }), null);
  assertEquals(licenceNameFromModel({ legal_name: '', confidence: 'high' }), null);
  assertEquals(licenceNameFromModel(null), null);
});

Deno.test('readLicenceName: a PDF that places each line with its own Tm reads the name (28 Sep 2026)', async () => {
  // The shape scripts/lib/demo_pdf.mjs writes: one BT, and `1 0 0 1 x y Tm` before every line. Before
  // the fix the whole page read as one line and the name was never found (licence_name_unread).
  const lines = ['TRADE LICENCE', 'Licence No.: ZZDEMO-1', 'Company Name: ZZ DEMO Walk en desktop', 'Legal Type: Limited Liability Company'];
  const body = ['BT', ...lines.map((l, i) => `/F1 12 Tf\n1 0 0 1 60 ${780 - 20 * i} Tm\n(${esc(l)}) Tj`), 'ET'].join('\n');
  const s = enc.encode(body);
  const head = enc.encode(`%PDF-1.4\n5 0 obj\n<< /Length ${s.length} >>\nstream\n`), tail = enc.encode('\nendstream\nendobj\n%%EOF\n');
  const out = new Uint8Array(head.length + s.length + tail.length); out.set(head); out.set(s, head.length); out.set(tail, head.length + s.length);
  assertEquals(await readLicenceName(out, 'application/pdf'), 'ZZ DEMO Walk en desktop');
});
