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
