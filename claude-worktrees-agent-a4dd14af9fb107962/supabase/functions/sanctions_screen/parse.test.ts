// The one thing that cannot be proved in CI is the download, so everything that turns bytes into names is
// proved here. Fixtures are SHAPES of the real sources, with invented names: a test that carried a real
// sanctioned person's name would put one in the repository for no benefit.
//   deno test supabase/functions/sanctions_screen/parse.test.ts
import { assertEquals } from 'jsr:@std/assert';
import { isWorkbook, parseUaeWorkbook, parseUnXml, uaeCandidateUrls, UAE_FALLBACK_URL } from './parse.ts';

const UN = `<?xml version="1.0" encoding="UTF-8"?>
<CONSOLIDATED_LIST dateGenerated="2026-09-18T00:00:00Z">
 <INDIVIDUALS>
  <INDIVIDUAL>
   <DATAID>1</DATAID><REFERENCE_NUMBER>QDi.900</REFERENCE_NUMBER>
   <FIRST_NAME>Zayn</FIRST_NAME><SECOND_NAME>Al</SECOND_NAME><THIRD_NAME>Fulani</THIRD_NAME><FOURTH_NAME/>
   <INDIVIDUAL_ALIAS><QUALITY>Good</QUALITY><ALIAS_NAME>Abu Testcase</ALIAS_NAME></INDIVIDUAL_ALIAS>
   <INDIVIDUAL_ALIAS><QUALITY>Low</QUALITY><ALIAS_NAME>X</ALIAS_NAME></INDIVIDUAL_ALIAS>
  </INDIVIDUAL>
 </INDIVIDUALS>
 <ENTITIES>
  <ENTITY>
   <DATAID>2</DATAID><REFERENCE_NUMBER>QDe.900</REFERENCE_NUMBER>
   <FIRST_NAME>Fulani Trading &amp; Co</FIRST_NAME>
   <ENTITY_ALIAS><ALIAS_NAME>Fulani  Co.</ALIAS_NAME></ENTITY_ALIAS>
  </ENTITY>
 </ENTITIES>
</CONSOLIDATED_LIST>`;

Deno.test('UN: primary name is the four name parts joined, aliases come through, one-character noise is dropped', () => {
  const got = parseUnXml(UN);
  assertEquals(got, [
    { entry_type: 'individual', reference: 'QDi.900', name: 'Zayn Al Fulani' },
    { entry_type: 'individual', reference: 'QDi.900', name: 'Abu Testcase' },
    { entry_type: 'entity', reference: 'QDe.900', name: 'Fulani Trading & Co' },
    { entry_type: 'entity', reference: 'QDe.900', name: 'Fulani Co.' },
  ]);
});

Deno.test('UN: a present-but-empty REFERENCE_NUMBER falls through to DATAID (?? would have kept the empty string)', () => {
  const got = parseUnXml(
    '<ENTITIES><ENTITY><DATAID>7</DATAID><REFERENCE_NUMBER></REFERENCE_NUMBER><FIRST_NAME>Empty Ref Co</FIRST_NAME></ENTITY></ENTITIES>');
  assertEquals(got, [{ entry_type: 'entity', reference: '7', name: 'Empty Ref Co' }]);
});

Deno.test('UN: a page that is not the list parses to zero, which the caller records as unparseable', () => {
  assertEquals(parseUnXml('<html><body>Service Unavailable</body></html>').length, 0);
});

// SheetJS worksheet shape: address -> { v } plus a !ref range.
// deno-lint-ignore no-explicit-any
const sheet = (rows: string[][]): any => {
  // deno-lint-ignore no-explicit-any
  const s: any = { '!ref': 'A1:F' + rows.length };
  rows.forEach((r, ri) => r.forEach((v, ci) => { if (v) s[String.fromCharCode(65 + ci) + (ri + 1)] = { v }; }));
  return s;
};

// The fixtures below are the SHAPE of the real workbook, measured 18 Sep 2026: a title row, a merged
// section-caption row, then a header row whose first cell is '#', then data keyed by that number.
const uaeSheet = (extraHeader: string[], rows: string[][]) =>
  sheet([
    ['قائمة الإرهاب المحلية', '', '', ''],
    ['أولاً- المعلومات الرئيسية', '', '', ''],
    ['#', 'التصنيف', ...extraHeader],
    ...rows,
  ]);

Deno.test('UAE: every name column is an entry, and the title and caption rows are not', () => {
  const wb = {
    SheetNames: ['الأفراد', 'التنظيمات', 'رفع الإدراج - أفراد'],
    Sheets: {
      // Two name columns (Arabic and Latin) plus a non-name column that must NOT become an entry.
      'الأفراد': uaeSheet(['الاسم الكامل (بالحروف العربية)', 'الاسم الكامل (بالحروف اللاتينية)', 'الجنسية'],
        [['1', 'شخص إرهابي', 'زين الفولاني', 'ZAYN AL FULANI', 'قطر'],
          ['2', 'شخص إرهابي', '-', 'SECOND PERSON', 'الأردن']]),
      // On the real organisations sheet the LONGEST cell is the listing resolution, which the previous
      // parser took as the name. This asserts it does not come through.
      'التنظيمات': uaeSheet(['الاسم الكامل (بالحروف اللاتينية)', 'الاسم', 'معلومات أخرى'],
        [['1', 'تنظيم إرهابي', 'FULANI TRADING AND COMPANY', 'شركة الفولاني',
          'مدرج بموجب قرار مجلس الوزراء رقم (41) لسنة 2014']]),
      'رفع الإدراج - أفراد': uaeSheet(['الاسم الكامل (بالحروف اللاتينية)'],
        [['1', 'شخص', 'SOMEONE DELISTED']]),
    },
  };
  assertEquals(parseUaeWorkbook(wb), [
    { entry_type: 'individual', reference: '1', name: 'زين الفولاني' },
    { entry_type: 'individual', reference: '1', name: 'ZAYN AL FULANI' },
    { entry_type: 'individual', reference: '2', name: 'SECOND PERSON' },
    { entry_type: 'entity', reference: '1', name: 'FULANI TRADING AND COMPANY' },
    { entry_type: 'entity', reference: '1', name: 'شركة الفولاني' },
  ]);
});

Deno.test('UAE: a sheet with no # header row yields nothing rather than a guess', () => {
  const wb = { SheetNames: ['الأفراد'], Sheets: { 'الأفراد': sheet([['Zayn Al Fulani', 'something']]) } };
  assertEquals(parseUaeWorkbook(wb), []);
});

Deno.test('UAE: the known workbook FileID is tried first, then every download the page offers', () => {
  // The real page's FIRST matching href is a Federal Decree PDF — which is exactly what the first
  // production run downloaded (screening_run 74, "parsed 0 of 575454 bytes"). Order matters.
  const html = '<a href="../API/Upload/DownloadFile?FileID=49dafd48-f1df-456c-8610-51cff0e7bcd1">Federal Decree No. 26 of 2021</a>'
    + '<a href="../API/Upload/DownloadFile?FileID=0433bfdb-8a3d-44db-9015-90cbbf48f6f6">&nbsp;</a>';
  const got = uaeCandidateUrls(html);
  assertEquals(got[0], UAE_FALLBACK_URL);
  assertEquals(got.includes('https://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=49dafd48-f1df-456c-8610-51cff0e7bcd1'), true);
  assertEquals(uaeCandidateUrls('<a href="/en-us/home">Home</a>'), [UAE_FALLBACK_URL]);
});

Deno.test('SSRF: an href on somebody else\'s page can never send us to somebody else\'s host', () => {
  const hostile = '<a href="https://attacker.example/evil.xls">Download Excel File</a>'
    + '<a href="http://169.254.169.254/latest/meta-data/">x</a>'
    + '<a href="http://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=49dafd48-f1df-456c-8610-51cff0e7bcd1">plaintext</a>'
    + '<a href="https://uaeiec.gov.ae.attacker.example/LS.xls">lookalike</a>'
    + '<a href="not a url at all">broken</a>';
  // Only the known-good FileID on the real host survives; nothing on the page adds a destination.
  assertEquals(uaeCandidateUrls(hostile), [UAE_FALLBACK_URL]);
  // ...and a genuine same-host link still does come through.
  assertEquals(
    uaeCandidateUrls('<a href="https://www.uaeiec.gov.ae/API/Upload/DownloadFile?FileID=49dafd48-f1df-456c-8610-51cff0e7bcd1">ok</a>').length,
    2,
  );
});

Deno.test('the bytes decide what a workbook is: OLE2 and ZIP yes, PDF and HTML no', () => {
  assertEquals(isWorkbook(new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0])), true); // .xls
  assertEquals(isWorkbook(new Uint8Array([0x50, 0x4b, 3, 4, 0, 0, 0, 0, 0, 0])), true); // .xlsx
  assertEquals(isWorkbook(new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, 0, 0])), false); // %PDF-1.7
  assertEquals(isWorkbook(new TextEncoder().encode('<!DOCTYPE html><html>')), false);
  assertEquals(isWorkbook(new Uint8Array([1, 2])), false);
});

