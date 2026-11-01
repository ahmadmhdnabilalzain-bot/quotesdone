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
  // insurance schedule wording: a period ends on its SECOND date (28 Oct 2026; this line asserted the start date,
  // 2026-01-01, as the expiry until the production document walk offered "expires 1 Jan 2026" for a 2026 policy)
  assertEquals(expiryFromText('Period of insurance: from 01/01/2026 to 31/12/2026')?.expiry, '2026-12-31');
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

// ── AN IMAGE IS NEVER INFLATED TO LOOK FOR TEXT (28 Oct 2026, supplier-journey audit run fceb5876) ────────────────────
// The browser audit's blurry scan (686 kB: one 2483x3265 RGB image and its soft mask, both FlateDecode) ended
// supplier_portal save_documents at the edge's CPU cap (HTTP 546). The reader inflated every pixel to look for text.
// Here: a page whose image XObject is 16 MB of pixels (a few kB deflated) beside a content stream that draws the licence.
async function pdfWithImage(): Promise<Uint8Array> {
  const pixels = new Uint8Array(4000 * 4000);   // 16 MB of grey: deflates to a few kB, inflates to 16 MB
  const img = new Uint8Array(await new Response(new Blob([pixels]).stream().pipeThrough(new CompressionStream('deflate'))).arrayBuffer());
  const text = enc.encode(['BT', '/F1 11 Tf', '56 800 Td', `(${esc('Licence Number : ZZ-546')}) Tj`, 'ET'].join('\n'));
  const parts: Uint8Array[] = [
    enc.encode(`%PDF-1.4\n4 0 obj\n<< /Type /XObject /Subtype /Image /Width 4000 /Height 4000 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length ${img.length} >>\nstream\n`),
    img, enc.encode(`\nendstream\nendobj\n5 0 obj\n<< /Length ${text.length} >>\nstream\n`), text, enc.encode('\nendstream\nendobj\n%%EOF\n'),
  ];
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0; for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

Deno.test('an image stream is never inflated to look for text; the page text is still read (S4 blurry scan, HTTP 546)', async () => {
  const bytes = await pdfWithImage();
  const Real = globalThis.DecompressionStream;
  let inflated = 0;
  globalThis.DecompressionStream = class extends Real { constructor(f: CompressionFormat) { super(f); inflated++; } };
  try {
    assertEquals(await pdfText(bytes), 'Licence Number : ZZ-546');
    assertEquals(inflated, 0, 'the image was inflated: 16 MB of pixels read as if they could hold text');
  } finally {
    globalThis.DecompressionStream = Real;
  }
});

// Review of #1726: the image test reads only the stream's OWN dictionary, so text after an image-like neighbour is kept.
Deno.test('a text stream after an object naming /Subtype /Image, or after an image whose stream keyword ends in a lone CR, is still read', async () => {
  const text = enc.encode(['BT', '/F1 11 Tf', '56 800 Td', `(${esc('Expiry Date: 13/03/2027')}) Tj`, 'ET'].join('\n'));
  const cat = (ps: Uint8Array[]) => { const o = new Uint8Array(ps.reduce((n, p) => n + p.length, 0)); let i = 0; for (const p of ps) { o.set(p, i); i += p.length; } return o; };
  const neighbour = cat([enc.encode('%PDF-1.4\n6 0 obj\n<< /Type /Annot /Subtype /Image /Rect [0 0 1 1] >>\nendobj\n'),
    enc.encode(`5 0 obj\n<< /Length ${text.length} >>\nstream\n`), text, enc.encode('\nendstream\nendobj\n%%EOF\n')]);
  const loneCr = cat([enc.encode('%PDF-1.4\n3 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /Filter /DCTDecode /Length 4 >>\nstream\r'),
    new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), enc.encode(`\nendstream\nendobj\n5 0 obj\n<< /Length ${text.length} >>\nstream\n`), text, enc.encode('\nendstream\nendobj\n%%EOF\n')]);
  assertEquals(await pdfText(neighbour), 'Expiry Date: 13/03/2027');
  assertEquals(await pdfText(loneCr), 'Expiry Date: 13/03/2027');
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

// 7 Oct 2026 (sales_engineer, accuracy suite ledger 1162): the two-column table layout, and every labelled field.
import { licenceFieldsFromText, licenceNeedsModel, mergeLicenceReads, readLicenceFields } from './document_expiry.ts';
const tablePdf = (rows: [string, string][]) => {
  // each label and each value is its own BT..ET with its own Tm, on the same baseline: how a table licence is drawn
  const body = rows.map(([k, v], i) => `BT /F1 10 Tf 1 0 0 1 60 ${700 - 22 * i} Tm (${esc(k)}) Tj ET\nBT /F1 10 Tf 1 0 0 1 230 ${700 - 22 * i} Tm (${esc(v)}) Tj ET`).join('\n');
  const s = enc.encode(body);
  const head = enc.encode(`%PDF-1.4\n5 0 obj\n<< /Length ${s.length} >>\nstream\n`), tail = enc.encode('\nendstream\nendobj\n%%EOF\n');
  const out = new Uint8Array(head.length + s.length + tail.length); out.set(head); out.set(s, head.length); out.set(tail, head.length + s.length);
  return out;
};
Deno.test('a table licence (label and value placed apart on one baseline) reads every field; before the fix the name was held', async () => {
  const f = await readLicenceFields(tablePdf([['Licence Number', '1023757'], ['Legal Name', 'ZZ DEMO Dune Plumbing LLC'], ['Trade Name', 'ZZ DEMO Dune Plumbing'],
    ['Legal Form', 'Limited Liability Company'], ['Issuing Authority', 'Dubai Department of Economy and Tourism'], ['Issue Date', '03 Mar 2025'],
    ['Expiry Date', '02 Mar 2027'], ['Business Activities', 'Plumbing and Sanitary Installation, Building Waterproofing Works']]), 'application/pdf');
  assertEquals(f.licence_no, '1023757');
  assertEquals(f.legal_name_en, 'ZZ DEMO Dune Plumbing LLC');
  assertEquals(f.trade_name, 'ZZ DEMO Dune Plumbing');
  assertEquals(f.emirate, 'Dubai');                     // from the authority: the licence prints no emirate line
  assertEquals([f.issue_date, f.expiry_date], ['2025-03-03', '2027-03-02']);
  assertEquals(f.activities, ['Plumbing and Sanitary Installation', 'Building Waterproofing Works']);
  assertEquals(licenceNeedsModel(f), false);
});
Deno.test('labels are whole words, the legal name is never the trade name, and nothing unlabelled is read', () => {
  const f = licenceFieldsFromText('Licence Number: DMCC-104477\nEstablishment Name: ZZ DEMO Sidra Lifts Est\nTrade Name: ZZ DEMO Sidra Lifts\nValid Until: 12/04/2027');
  assertEquals(f.licence_no, 'DMCC-104477');
  assertEquals(f.legal_name_en, 'ZZ DEMO Sidra Lifts Est');
  assertEquals(f.expiry_date, '2027-04-12');
  const g = licenceFieldsFromText('Trade Name: ZZ DEMO Only Trade\nTRN: 100000000000003\nGeneral Trading');
  assertEquals([g.legal_name_en, g.licence_no, g.activities, g.emirate], [null, null, null, null]);
  assertEquals(licenceNeedsModel(g), true);
});
Deno.test('merge: code first, the model only fills what code left unread, a low-confidence name is not a name', () => {
  const { merged, source } = mergeLicenceReads({ legal_name_en: 'ZZ DEMO A LLC', licence_no: null, expiry_date: '2027-01-01' },
    { legal_name: 'ZZ DEMO B LLC', license_number: '777', expiry_date: '2029-09-09', license_authority: 'Jebel Ali Free Zone Authority', confidence: 'high' });
  assertEquals([merged.legal_name_en, merged.licence_no, merged.expiry_date, merged.emirate], ['ZZ DEMO A LLC', '777', '2027-01-01', 'Dubai']);
  assertEquals([source.legal_name_en, source.licence_no], ['code', 'model']);
  assertEquals(mergeLicenceReads(null, { legal_name: 'ZZ DEMO C LLC', confidence: 'low' }).merged.legal_name_en, null);
  // an Arabic-only licence: the model's Arabic name is the Arabic name, never the English one the gate compares
  const ar = mergeLicenceReads(null, { legal_name: 'زد زد ديمو الواحة', legal_name_ar: 'زد زد ديمو الواحة', confidence: 'high' }).merged;
  assertEquals([ar.legal_name_en, ar.legal_name_ar], [null, 'زد زد ديمو الواحة']);
});

// A PERIOD ENDS ON ITS SECOND DATE (28 Oct 2026, sales_engineer). The production document walk uploaded an insurance
// schedule printing "Period of Insurance: From 01/01/2026 To 31/12/2026" and the Documents tab offered the START date
// as the expiry. Every range shape a UAE schedule, certificate or licence prints; a single date is unchanged.
Deno.test('expiryFromText: a period of cover or validity reads its END date', () => {
  const cases: [string, string][] = [
    ['Period of Insurance: From 01/01/2026 To 31/12/2026\nExpiry Date: 31/12/2026', '2026-12-31'],
    ['PERIOD OF INSURANCE  01/01/2026 TO 31/12/2026', '2026-12-31'],
    ['Licence Validity: 15/03/2025 - 14/03/2028', '2028-03-14'],
    ['Validity: 15 Mar 2025 – 14 Mar 2028', '2028-03-14'],
    ['Validity 2025-03-15 until 2028-03-14', '2028-03-14'],
    ['Valid to: 09/02/2027', '2027-02-09'],
    ['صلاحية: 15/03/2025 إلى 14/03/2028', '2028-03-14'],
    ['Expiry Date: 14/03/2028\nIssue Date: 15/03/2025', '2028-03-14'],
  ];
  for (const [text, want] of cases) assertEquals(expiryFromText(text)?.expiry, want, text);
});

// A TABLE IS READ BY ITS COLUMNS (1 Nov 2026, sales_engineer; measured on 28 Oct in the independent review of #1708).
// A licence printing its dates as a header row over a value row read the ISSUE date as its expiry, and supplier_api and
// supplier_portal write a licence's expiry from this reader without asking the supplier: a valid licence was recorded
// as expired. Of the readings asserted in the next three tests, 55 fail on the reader before this fix (main at
// 141f2bc), checked one assertion at a time. Fourteen pass there by design: the two pins of what the text layer draws
// (pdfText is not changed here), the three guards at the end of the third test, and nine readings main already had
// right that the first version of this fix lost (review of #1733: two blank-cell tables, the seven "kept"). Main read the 33 PDFs of the
// synthetic corpus (scripts/e2e/document_intake_corpus.mjs) exactly as this reader does: expiry, keyword, issue date.
Deno.test('expiryFromText: a table reads the expiry label\'s own column, or nothing — never the issue date', () => {
  const cases: [string, string | null][] = [
    // the header row the review measured, and the shapes a text layer draws it in
    ['Issue Date   Expiry Date\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Issue Date Expiry Date\n15/03/2025 14/03/2028', '2028-03-14'],
    ['Issue Date | Expiry Date\n15/03/2025 | 14/03/2028', '2028-03-14'],
    ['Issue Date   Expiry Date\n\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Licence No   Issue Date   Expiry Date\n1145872   15/03/2025   14/03/2028', '2028-03-14'],
    ['Issue Date   Expiry Date   Renewal Date\n15/03/2025   14/03/2028   14/02/2028', '2028-03-14'],
    ['Registration Date   Licence Expiry Date\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Valid From   Valid To\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Issue Date   Validity\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Please check the issue date and the expiry date.\nIssue Date   Expiry Date\n15/03/2025   14/03/2028', '2028-03-14'],
    // an English label beside its Arabic twin is one column; Arabic alone reads the same
    ['Issue Date تاريخ الإصدار   Expiry Date تاريخ الانتهاء\n15/03/2025   14/03/2028', '2028-03-14'],
    ['تاريخ الإصدار   تاريخ الانتهاء\n15/03/2025   14/03/2028', '2028-03-14'],
    // a table drawn column by column (the labels stacked, then the dates), and one drawn on a single line
    ['Issue Date\nExpiry Date\n15/03/2025\n14/03/2028', '2028-03-14'],
    ['Issue Date\n\nExpiry Date\n15/03/2025\n14/03/2028', '2028-03-14'],
    ['Issue Date\nتاريخ الإصدار\nExpiry Date\nتاريخ الانتهاء\n15/03/2025\n14/03/2028', '2028-03-14'],
    ['Issue Date   Expiry Date   15/03/2025   14/03/2028', '2028-03-14'],
    // otherwise nothing is read, and the model or a person reads the document
    ['Issue Date   Expiry Date\n15/03/2025', null],
    ['Issue Date   Expiry Date\n15/03/2025   N/A', null],
    ['Issue Date Expiry Date 15/03/2025', null],
    ['Expiry Date   Issue Date\n14/03/2028', null],
    ['Issue Date   Expiry Date\n15/03/2025   14/03/2028   01/01/2026', null],
    ['Cover   Issue Date   Expiry Date\nLiability   01/01/2026   31/12/2026\nMotor   01/03/2026   28/02/2027', null],
    ['Issue Date   Expiry Date\n(dd/mm/yyyy)   (dd/mm/yyyy)\n15/03/2025   14/03/2028', null],
    ['Issue Date\n\nExpiry Date\n\n15/03/2025\n\n14/03/2028', null],
    // an expiry before its own row's issue date: the columns are not in reading order (right-to-left text drawn in
    // visual order); a range would take its later date, a table has no such reading
    ['Issue Date   Expiry Date\n14/03/2028   15/03/2025', null],
    // a date is never read for a keyword when it is another label's: one stands between them, or the date shares
    // its row with a date under a label this reader does not know
    ['Expiry Date: as per the schedule\nIssue Date: 15/03/2025', null],
    ['Period of Insurance\nFrom   To\n01/01/2026   31/12/2026', null],
    // REVIEW OF #1733: a value is paired with its label by its POSITION in the row, never by counting dates. A blank
    // cell ("-", "N/A") under a known label let a date under an unknown one take its place: these read 01/06/2029.
    ['Issue Date   Expiry Date   Next Inspection\n-   14/03/2028   01/06/2029', '2028-03-14'],
    ['Issue Date   Expiry Date   Next Inspection Date\nN/A   14/03/2028   01/06/2029', '2028-03-14'],
    ['Issue Date   Membership Date   Expiry Date\n15/03/2025   14/03/2028', null],
    ['Printed 01/11/2026   Issue Date   Expiry Date\n15/03/2025   14/03/2028', null],
    ['Membership Date   Expiry Date\n15/03/2025   14/03/2028', '2028-03-14'],
    ['Membership Date   Expiry Date\n15/03/2025   14/03/2028\n16/03/2025   15/03/2028', null],
    ['Issue Date   Expiry Date\n15/03/2025 (1446/09/15)   14/03/2028 (1449/09/14)', '2028-03-14'],
    // one label naming both dates reads the later, and nothing with one date
    ['Issue/Expiry Date: 15/03/2025 / 14/03/2028', '2028-03-14'],
    ['Issue & Expiry Date: 15/03/2025 & 14/03/2028', '2028-03-14'],
    ['Issue/Expiry Date: 15/03/2025', null],
    // ...and never another label's later date (re-review of #1733)
    ['Issue/Expiry Date: 15/03/2025   Next Inspection: 01/06/2029', null],
    ['Issue/Expiry Date: 15/03/2025\nPrinted on 01/11/2026', null],
    ['Issue/Expiry Date: 15/03/2025\nAudit: 01/06/2029', null],
    ['Expiry Date / Print Date: 01/11/2026', null],
    // a value cell split in two by its own double space shifts every date one place: nothing is read
    ['Licence No   Issue Date   Expiry Date   Remarks\nCN  1145872   15/03/2025   14/03/2028', null],
    ['Licence No   Issue Date   Expiry Date\nCN  1145872   15/03/2025', null],
    // a table printed on one line reads only when nothing but labels, dates and separators share the line
    ['Issue Date   Expiry Date   Next Inspection   -   14/03/2028   01/06/2029', null],
    ['Issue Date   Expiry Date   Next Inspection   14/03/2028   01/06/2029', null],
    ['Issue Date Expiry Date Next Inspection 14/03/2028 01/06/2029', null],
    ['Issue Date | Expiry Date | Next Inspection: 14/03/2028 | 01/06/2029', null],
    // a cell that says it is blank, and a note under a column only counted, do not stop a reading
    ['Issue Date   Expiry Date   Next Inspection\nn.a.   14/03/2028   01/06/2029', '2028-03-14'],
    ['Issue Date   Expiry Date   Next Inspection\nNot Applicable   14/03/2028   01/06/2029', '2028-03-14'],
    ['Issue Date   Expiry Date   Renewal Date\n15/03/2025   14/03/2028   TBA', '2028-03-14'],
  ];
  for (const [text, want] of cases) assertEquals(expiryFromText(text)?.expiry ?? null, want, text);
});

Deno.test('readExpiry + readLicenceFields: a licence PDF drawn as a header row, or column by column, reads its expiry', async () => {
  // each cell its own BT..ET at its own place, as a table is drawn; textFromContent joins one baseline with spaces
  const cellsPdf = (cells: [string, number, number][]) => {
    const s = enc.encode(cells.map(([v, x, y]) => `BT /F1 10 Tf 1 0 0 1 ${x} ${y} Tm (${esc(v)}) Tj ET`).join('\n'));
    const head = enc.encode(`%PDF-1.4\n5 0 obj\n<< /Length ${s.length} >>\nstream\n`), tail = enc.encode('\nendstream\nendobj\n%%EOF\n');
    const out = new Uint8Array(head.length + s.length + tail.length); out.set(head); out.set(s, head.length); out.set(tail, head.length + s.length);
    return out;
  };
  const headerRow = cellsPdf([['Licence Number', 60, 700], ['Issue Date', 200, 700], ['Expiry Date', 340, 700],
    ['1145872', 60, 682], ['15/03/2025', 200, 682], ['14/03/2028', 340, 682]]);
  const byColumn = cellsPdf([['Issue Date', 60, 700], ['Expiry Date', 60, 682], ['15/03/2025', 230, 700], ['14/03/2028', 230, 682]]);
  assertEquals(await pdfText(headerRow), 'Licence Number   Issue Date   Expiry Date\n1145872   15/03/2025   14/03/2028');
  assertEquals(await pdfText(byColumn), 'Issue Date\nExpiry Date\n15/03/2025\n14/03/2028');
  for (const bytes of [headerRow, byColumn]) {
    assertEquals((await readExpiry(bytes, 'application/pdf'))?.expiry, '2028-03-14');
    assertEquals((await readLicenceFields(bytes, 'application/pdf')).expiry_date, '2028-03-14');
  }
});

Deno.test('expiryFromText: an ordinal day, a period opened by "Valid From" or "between", a Hijri month before the date', () => {
  assertEquals([parseDate('1st January 2026'), parseDate('31st of December 2026'), parseDate('January 1st, 2026'), parseDate('2nd Mar 2027')],
    ['2026-01-01', '2026-12-31', '2026-01-01', '2027-03-02']);
  const cases: [string, string | null][] = [
    ['Period of Insurance: From 1st January 2026 to 31st December 2026', '2026-12-31'],
    ['Expiry Date: 31st December 2026', '2026-12-31'],
    ['Valid until: 31st of December 2026', '2026-12-31'],
    ['Expiry Date: December 31st, 2026', '2026-12-31'],
    // a start keyword opens a period and is read to its end
    ['Valid From: 15/03/2025 To: 14/03/2028', '2028-03-14'],
    ['Valid from 01/01/2026 until 31/12/2026', '2026-12-31'],
    ['Valid From: 15/03/2025\nTo: 14/03/2028', '2028-03-14'],
    ['صالحة من 15/03/2025 إلى 14/03/2028', '2028-03-14'],
    ['سارية من: ١٥/٠٣/٢٠٢٥ حتى: ١٤/٠٣/٢٠٢٨', '2028-03-14'],
    // "between" joins its two dates with "and"; with one date there is no end, and the start was read before
    ['Period of Insurance: between 01/01/2026 and 31/12/2026', '2026-12-31'],
    ['This certificate is valid between 01/01/2026 and 31/12/2026', '2026-12-31'],
    ['Validity: between 1st January 2026 and 31st December 2026', '2026-12-31'],
    ['صلاحية: بين 01/01/2026 و 31/12/2026', '2026-12-31'],
    ['Validity: between 01/01/2026 and the date of renewal', null],
    // a month is a month's own name: "Ramadan" no longer hides the Gregorian date after it
    ['Expiry Date: 17 Ramadan 1449 / 14/02/2028', '2028-02-14'],
  ];
  for (const [text, want] of cases) assertEquals(expiryFromText(text)?.expiry ?? null, want, text);
  // GUARDS on this fix's own rules. Main reads these three the same (they cannot fail there); each fails when its
  // rule is broken: a start keyword reading its single date, a twin merged only on one line, a Hijri date counted
  // as a second column.
  assertEquals(expiryFromText('Valid From: 15/03/2025')?.expiry ?? null, null);
  assertEquals(expiryFromText('Expiry Date\nتاريخ الانتهاء\n14/03/2028')?.expiry, '2028-03-14');
  assertEquals(expiryFromText('Expiry Date\n14/03/2028   1449/07/17')?.expiry, '2028-03-14');
  // ...and, from the review of #1733, readings main already got right that a first version of this fix lost
  const kept: [string, string | null][] = [
    ['Issue Date 15/03/2025 تاريخ الإصدار   Expiry Date 14/03/2028 تاريخ الانتهاء', '2028-03-14'],
    ['تاريخ الإصدار 15/03/2025 Issue Date   تاريخ الانتهاء 14/03/2028 Expiry Date', '2028-03-14'],
    ['Expiry/Renewal Date: 31/12/2026', '2026-12-31'],
    ['Date of Expiry / Renewal Date: 31/12/2026', '2026-12-31'],
    ['Expiry Date   Next Audit\n14/03/2028   01/06/2027', '2028-03-14'],
    ['Expiry Date   Retroactive Date\n31/12/2026   01/01/2020', '2026-12-31'],
    ['Valid between 01/01/2026 and 31/12/2025', null],
  ];
  for (const [text, want] of kept) assertEquals(expiryFromText(text)?.expiry ?? null, want, text);
});

// THE PERIOD READ ADVERSARIALLY (28 Oct 2026, sales_engineer; independent review of #1708). The first fix took the
// second date of any pair, so a pair printed backwards read its EARLIER date: "Expiry Date - Issue Date: 14/03/2028 -
// 15/03/2025" read 15/03/2025, which main had read correctly, and on the licence path that is written unconfirmed.
// It also missed the commonest schedule shapes ("To:", a time after the start, From/To on two lines, وحتى, لغاية),
// and a "Validity: <start>" printed above "Expiry Date: <expiry>" still read the start. Measured row by row: every
// row above the last group fails on the reader #1708 opened with, except "Previous Policy Expiry", which guards the
// expiry-label rule this review added; the last group reads the same on main, on #1708 and here.
Deno.test('expiryFromText: a period read adversarially — later date, every connector, expiry label first', () => {
  const cases: [string, string | null][] = [
    // a pair printed backwards still reads the LATER date (an expiry is never before its issue)
    ['Expiry Date - Issue Date\n14/03/2028 - 15/03/2025', '2028-03-14'],
    ['Validity: 14/03/2028 to 15/03/2025', '2028-03-14'],
    ['صلاحية: 14/03/2028 - 15/03/2025', '2028-03-14'],
    // what a schedule prints between the two dates
    ['Period of Insurance: From: 01/01/2026 To: 31/12/2026', '2026-12-31'],
    ['Period of Insurance: From 01/01/2026 00:00 hrs To 31/12/2026 24:00 hrs', '2026-12-31'],
    ['Period of Insurance: 01/01/2026 12:00 AM to 31/12/2026 11:59 PM', '2026-12-31'],
    ['Period of Insurance\nFrom: 01/01/2026\nTo: 31/12/2026', '2026-12-31'],
    ['Validity: 01/01/2026 thru 31/12/2026', '2026-12-31'],
    ['صلاحية: من 15/03/2025 وحتى 14/03/2028', '2028-03-14'],
    ['صلاحية: من ١٥/٠٣/٢٠٢٥ لغاية ١٤/٠٣/٢٠٢٨', '2028-03-14'],
    ['صلاحية: 15/03/2025 الي 14/03/2028', '2028-03-14'],
    ['صلاحية\nمن: 15/03/2025\nإلى: 14/03/2028', '2028-03-14'],
    // an expiry label wins over a period label printed above it
    ['Validity: 15/03/2025\nExpiry Date: 14/03/2028', '2028-03-14'],
    ['Period of Insurance: From 01/01/2026\nExpiry Date: 31/12/2026', '2026-12-31'],
    ['Validity: 15/03/2025\nValid until: 14/03/2028', '2028-03-14'],
    ['Validity of quotation: 01/10/2026 - 31/10/2026\nPolicy Expiry Date: 31/12/2026', '2026-12-31'],
    // ...but not one that names an earlier document's date
    ['Period of Insurance: 01/01/2026 to 31/12/2026\nPrevious Policy Expiry: 31/12/2025', '2026-12-31'],
    ['Expiry date of previous policy: 31/12/2025\nPeriod of Insurance: 01/01/2026 to 31/12/2026', '2026-12-31'],
    ['تاريخ انتهاء الوثيقة السابقة: 31/12/2025\nصلاحية: 01/01/2026 إلى 31/12/2026', '2026-12-31'],
    ['Previous Period of Insurance: 01/01/2025 to 31/12/2025\nPeriod of Insurance: 01/01/2026 to 31/12/2026', '2026-12-31'],
    // a period whose end does not read day-first is not read at all: its start is certainly not the expiry
    ['Period of Insurance: 01/12/2026 to 12/31/2026', null],
    ['Validity: 03/15/2025 - 03/10/2028', null],
    // unchanged: a hyphen inside ONE date is not a range, and day-first stays day-first
    ['Expiry: 14-03-2028', '2028-03-14'],
    ['Expiry: 2028-03-14', '2028-03-14'],
    ['Expiry: 14-Mar-2028', '2028-03-14'],
    ['Expiry: 14-03-2028 Issue: 15-03-2025', '2028-03-14'],
    ['Expiry Date: 14/03/2028 - Issue Date: 15/03/2025', '2028-03-14'],
    ['Expiry: 14/03/2028 - Renewable annually', '2028-03-14'],
    ['Expiry: 03/04/2027', '2027-04-03'],
    ['Issue Date: 15/03/2025\nExpiry Date: 14/03/2028', '2028-03-14'],
    ['تاريخ الانتهاء: ١٤-٠٣-٢٠٢٨ تاريخ الإصدار: ١٥-٠٣-٢٠٢٥', '2028-03-14'],
  ];
  for (const [text, want] of cases) assertEquals(expiryFromText(text)?.expiry ?? null, want, text);
});

// ONE READ OF A PDF PER UPLOAD, AND A NATIVE DECODE (28 Oct 2026, sales_engineer; production size measurement: scanner-style
// licences of 14.50 and 19.33 MB ended supplier_portal and supplier_api at the edge's CPU cap, 9.66 MB passed). The three
// readers run on the same bytes in one upload; they now share one pdfText pass, and the whole-file view is decoded natively.
// A scan-like PDF: binary image streams (every byte value, 0x80-0x9F included, before the text) then the licence's text.
async function scanLike(mb: number): Promise<Uint8Array> {
  const page = new Uint8Array(1024 * 1024); for (let i = 0; i < page.length; i++) page[i] = (i * 2654435761) >>> 24;
  const text = await pdf(LICENCE, true);
  const parts: Uint8Array[] = [enc.encode('%PDF-1.4\n')];
  for (let n = 0; n < mb; n++) parts.push(enc.encode(`${10 + n} 0 obj\n<< /Type /XObject /Subtype /Image /Filter /DCTDecode /Length ${page.length} >>\nstream\n`), page, enc.encode('\nendstream\nendobj\n'));
  parts.push(text.subarray(9));   // the licence PDF without its own header line
  const out = new Uint8Array(parts.reduce((a, p) => a + p.length, 0)); let o = 0; for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}
// The reader as it was before 28 Oct, kept here as the reference: the same text must come out of the faster one.
const latin1Ref = (b: Uint8Array) => { let s = ''; for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000)); return s; };

Deno.test('pdfText: one pass per bytes object, shared by the three readers of an upload', async () => {
  const bytes = await scanLike(2);
  assertEquals(pdfText(bytes) === pdfText(bytes), true);           // the same promise: the PDF is read once
  const copy = bytes.slice();
  assertEquals(pdfText(copy) === pdfText(bytes), false);           // another upload's bytes are read on their own
  assertEquals(await pdfText(copy), await pdfText(bytes));
  assertEquals((await readExpiry(bytes, 'application/pdf'))?.expiry, '2027-03-13');
  assertEquals((await readLicenceFields(bytes, 'application/pdf')).expiry_date, '2027-03-13');
});

Deno.test('pdfText: the native decode keeps every offset, so binary streams before the text change nothing', async () => {
  for (const mb of [0, 1, 3]) {
    const bytes = await scanLike(mb);
    const text = await pdfText(bytes);
    assertEquals(text?.includes('Expiry Date           : 13/03/2027'), true, `${mb} MB of image before the text`);
    // the structural view is one character per byte, exactly like the reference decode
    assertEquals(new TextDecoder('latin1').decode(bytes).length, latin1Ref(bytes).length);
  }
});

Deno.test('pdfText: a 20 MB scan is read in well under the old cost (the old decode alone was 810 ms of 1,044)', async () => {
  const bytes = await scanLike(20);
  let t = performance.now(); latin1Ref(bytes); const oldDecode = performance.now() - t;
  t = performance.now();
  await readExpiry(bytes, 'application/pdf'); await readLicenceName(bytes, 'application/pdf'); await readLicenceFields(bytes, 'application/pdf');
  const threeReads = performance.now() - t;
  // Relative, measured in the same run on the same machine: the three readers together must cost less than the old
  // decode of ONE pass. Before 28 Oct they cost three decodes plus three scans.
  assertEquals(threeReads < oldDecode, true, `three reads ${Math.round(threeReads)} ms vs one old decode ${Math.round(oldDecode)} ms`);
});
