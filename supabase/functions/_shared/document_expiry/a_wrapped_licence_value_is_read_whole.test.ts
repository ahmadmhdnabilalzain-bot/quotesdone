// A LICENCE VALUE THAT WRAPS IS READ WHOLE (10 Nov 2026, customer_support; supplier registration certification, founder
// ruling 1620: he invites his network only once the registration "reads their trade licence").
//
// Measured on the certification's fixtures (scripts/e2e/fixtures/registration, clean system-printed PDFs): a value too long
// for its table cell continues on the next text line, and the code reader took only the first line.
//   L1 Dubai DET, English + Arabic: legal name read "ZZ DEMO Saker Electromechanical" for "... Contracting LLC". That name
//      differs from the registered one, so fn_sales_engineer_verifies_supplier (ruling 1176) RENAMES the company to the cut
//      name and e-mails the supplier that his licence prints it. The authority was read with the row's Arabic label glued on
//      ("Dubai Department of Economy and Tourism" + the Arabic for "issuing authority"), and 1 of 3 activities, itself cut.
//   L3 JAFZA: "Sanitary" for the activity "Sanitary Ware Trading". L2 and L6 lost their third activity the same way.
// The text below is what _shared/document_expiry/pdf_text.ts extracts from L1 and L3, verbatim.
import { assertEquals } from 'jsr:@std/assert@1';
import { licenceFieldsFromText, licenceNameFromText } from './licence_fields.ts';

const L1 = `GOVERNMENT OF DUBAI
DEPARTMENT OF ECONOMY AND TOURISM
TRADE LICENCE
ﺔﻳرﺎﺠﺗ ﺔﺼﺧر
Licence Number ZZ-1290417 ﺔﺼﺧﺮﻟا ﻢﻗر
Legal Name ZZ DEMO Saker Electromechanical
Contracting LLC
ذ.م.م ﺔﻴﻜﻴﻧﺎﻜﻴﻣوﺮﻬﻜﻟت اﻻوﺎﻘﻤﻠﻟ ﺮﻘﺼﻟا ﻮﻤﻳزد زد د
ﻲﻧﻮﻧﺎﻘﻟا ﻢﺳﻻا
Trade Name ZZ DEMO Saker Electromechanical ريﺎﺠﺘﻟا ﻢﺳﻻا
Legal Form Limited Liability Company ﻲﻧﻮﻧﺎﻘﻟا ﻞﻜﺸﻟا
Emirate Dubai رةﺎﻣﻹا
Issuing Authority Dubai Department of Economy and Tourism ارﺪﺻﻹا ﺔﻬﺟ
Issue Date 16 Feb 2025 ارﺪﺻﻹا ﺦﻳرﺎﺗ
Expiry Date 15 Feb 2027 ءﺎﻬﺘﻧﻻا ﺦﻳرﺎﺗ
Business Activities Electromechanical Equipment Installation
and Maintenance, Plumbing and Sanitary
Installation, Air Conditioning and Ventilation
Systems Installation
ﺔﻄﺸﻧﻷا
Electronically issued document - verify on the issuer's portal
(QuotesDone synthetic fixture - not a real company or licence)`;

const L3 = `JEBEL ALI FREE ZONE AUTHORITY
JAFZA
TRADING LICENCE
Licence No ZZ-719044
Name of Company ZZ DEMO Dune Building Materials Trading FZE
Trade Name ZZ DEMO Dune Building Materials
Legal Status Free Zone Establishment
Issued By Jebel Ali Free Zone Authority
Date of Issue 21/09/2025
Valid Until 20/09/2027
Licensed Activities Building Materials Trading, Tiles and Ceramics Trading, Sanitary
Ware Trading
Electronically issued document - verify on the issuer's portal
(QuotesDone synthetic fixture - not a real company or licence)`;

Deno.test('a legal name that wraps onto the next line is read whole, so the company is never renamed to half its name', () => {
  assertEquals(licenceNameFromText(L1), 'ZZ DEMO Saker Electromechanical Contracting LLC');
  assertEquals(licenceFieldsFromText(L1).legal_name_en, 'ZZ DEMO Saker Electromechanical Contracting LLC');
});

Deno.test('a bilingual row: the Arabic label printed after the English value is not part of the value', () => {
  const f = licenceFieldsFromText(L1);
  assertEquals(f.authority, 'Dubai Department of Economy and Tourism');
  assertEquals(f.legal_form, 'Limited Liability Company');
  assertEquals(f.trade_name, 'ZZ DEMO Saker Electromechanical');
  assertEquals(f.licence_no, 'ZZ-1290417');
  assertEquals(f.emirate, 'Dubai');
  assertEquals(f.issue_date, '2025-02-16');
  assertEquals(f.expiry_date, '2027-02-15');
});

Deno.test('activities that wrap are read whole, every one of them, and the footer after them is not an activity', () => {
  assertEquals(licenceFieldsFromText(L1).activities,
    ['Electromechanical Equipment Installation and Maintenance', 'Plumbing and Sanitary Installation', 'Air Conditioning and Ventilation Systems Installation']);
  assertEquals(licenceFieldsFromText(L3).activities, ['Building Materials Trading', 'Tiles and Ceramics Trading', 'Sanitary Ware Trading']);
});

Deno.test('a name that already ends in its legal form takes nothing from the line after it', () => {
  assertEquals(licenceNameFromText(L3), 'ZZ DEMO Dune Building Materials Trading FZE');
  const t = 'Company Name: ZZ DEMO Reem Projects LLC\nCompany Details\nLicence No: 12345';
  assertEquals(licenceNameFromText(t), 'ZZ DEMO Reem Projects LLC');
});

Deno.test('one value per line, as before, when nothing wraps (the colon layout of most licences)', () => {
  const t = 'Licence No: 704512\nCompany Name: ZZ DEMO Falcon Aluminium LLC\nTrade Name: ZZ DEMO Falcon Aluminium\nIssuing Authority: Sharjah Economic Development Department\nIssue Date: 01/02/2025\nExpiry Date: 31/01/2027\nActivities: Aluminium Works Contracting, Glass and Glazing Works\n(QuotesDone synthetic fixture - not a real company or licence)';
  const f = licenceFieldsFromText(t);
  assertEquals(f.legal_name_en, 'ZZ DEMO Falcon Aluminium LLC');
  assertEquals(f.authority, 'Sharjah Economic Development Department');
  assertEquals(f.activities, ['Aluminium Works Contracting', 'Glass and Glazing Works']);
});

Deno.test('an Arabic-only value is kept: only an Arabic run AFTER English is a label', () => {
  const f = licenceFieldsFromText('اسم الشركة: زد زد ديمو النجم للمقاولات\nرقم الرخصة: 123456');
  assertEquals(f.legal_name_ar, 'زد زد ديمو النجم للمقاولات');
});
