// The one thing that cannot be proved in CI is the download, so everything that turns bytes into names is
// proved here. Fixtures are SHAPES of the real sources, with invented names: a test that carried a real
// sanctioned person's name would put one in the repository for no benefit.
//   deno test supabase/functions/sanctions_screen/parse.test.ts
import { assertEquals } from 'jsr:@std/assert';
import { parseUaeWorkbook, parseUnXml, uaeExcelUrl } from './parse.ts';

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
  const s: any = { '!ref': 'A1:C' + rows.length };
  rows.forEach((r, ri) => r.forEach((v, ci) => { if (v) s[String.fromCharCode(65 + ci) + (ri + 1)] = { v }; }));
  return s;
};

Deno.test('UAE: individuals and organisations are read, de-listing sheets and header rows are not', () => {
  const wb = {
    SheetNames: ['الأفراد', 'التنظيمات', 'رفع الأسماء'],
    Sheets: {
      'الأفراد': sheet([['م', 'الاسم', ''], ['1', 'Zayn Al Fulani', '']]),
      'التنظيمات': sheet([['2', 'Fulani Trading and Company', '']]),
      'رفع الأسماء': sheet([['3', 'Someone Removed From The List', '']]),
    },
  };
  assertEquals(parseUaeWorkbook(wb), [
    { entry_type: 'individual', reference: '1', name: 'Zayn Al Fulani' },
    { entry_type: 'entity', reference: '2', name: 'Fulani Trading and Company' },
  ]);
});

Deno.test('UAE: the Excel link is read off the page, absolute or relative, and null when the page has none', () => {
  assertEquals(uaeExcelUrl('<a href="/DownloadFile?FileID=0433bfdb-8a3d-44db-9015-90cbbf48f6f6">Download Excel File</a>'),
    'https://www.uaeiec.gov.ae/DownloadFile?FileID=0433bfdb-8a3d-44db-9015-90cbbf48f6f6');
  assertEquals(uaeExcelUrl('<a href="https://x.example/LS.xls">Download Excel File</a>'), 'https://x.example/LS.xls');
  assertEquals(uaeExcelUrl('<a href="/en-us/home">Home</a>'), null);
});
