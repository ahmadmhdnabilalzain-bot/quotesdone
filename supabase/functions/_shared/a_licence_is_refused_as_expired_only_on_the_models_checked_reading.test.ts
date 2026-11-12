// A LICENCE IS REFUSED AS EXPIRED ONLY ON THE MODEL'S CHECKED READING (12 Nov 2026, sales_engineer; founder rulings 1663, 1664).
//
// MEASURED. The founder's first real registration, on his iPhone: the portal refused his own valid Dubai DET licence, "This trade
// licence (...) expired on 30 Oct 2026, so we cannot register it". The licence prints Expiry Date 29/10/2027 and Issue Date
// 30/10/2026. The code reader ran first and its reading was never replaced by the model's: on the licence page the labels and their
// dates come out of the text layer in opposite orders (and an interleaved line between them), and on the Commercial Register page
// "Expiry Date ... Reg. Date" stands over "30/10/2026 29/10/2027". "Reg. Date" was not a label the reader knew, so 30/10/2026 was
// read as the expiry. The same page's "Legal Type الشكل القانون" gave its Arabic label as the legal form.
//
// EVERY FIXTURE HERE IS SYNTHETIC: the company is "ZZ DEMO ...", the numbers and dates are invented in the layout the real file has.
// No personal detail of the real licence is in this file.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { codeExpiryMayStand, expiryFromText, licenceFieldsFromText, mergeLicenceReads, modelReadingToRow } from './document_expiry.ts';
import { checkLicenceRead, datesPrintedIn, numberPrintedIn } from './licence_extract.ts';
import { licenceHasExpired } from '../../../src/components/portal/supplier/licenceExpiry.ts';

// The DET e-licence's text layer, in the order pdf.js gives it (synthetic values).
const DET_LICENCE_PAGE = [
  ' / License Details', 'License No. 9990001', 'اسم الشركةزد ديمو للتجارة ش.ذ.م.م', 'ZZ DEMO TRADING L.L.CCompany Name',
  'Issue Date تاريخ الصدارتاريخ النتهاءExpiry Date', 'Limited Liability Company - Single Owner(LLC - SO)', '29/10/2027 30/10/2026',
  'الشكل القانونشركة ذات مسؤولية محدودة - الشخص الواحد )ذ.م.مLegal Type',
].join('\n');
const DET_REGISTER_PAGE = ['Legal Type الشكل القانون', 'Expiry Date تاريخ النتهاء Reg. Date تاريخ الصدار30/10/202629/10/2027'].join('\n');
const DET_FILE = DET_LICENCE_PAGE + '\n' + DET_REGISTER_PAGE;
const MODEL_RIGHT = { legal_name: 'ZZ DEMO TRADING L.L.C', license_number: '9990001', license_authority: 'Dubai Department of Economy and Tourism',
  emirate: 'Dubai', issue_date: '2026-10-30', expiry_date: '2027-10-29', legal_form: 'Limited Liability Company - Single Owner', activities: [], confidence: 'high' };
const NOW = Date.parse('2026-11-12T08:00:00Z');

Deno.test('the DET layout: code never reads the registration or issue date as the expiry (it reads nothing, and the model reads it)', () => {
  // main read 2026-10-30 here (the register page's Reg. Date)
  assertEquals(expiryFromText(DET_FILE), null);
  assertEquals(expiryFromText(DET_REGISTER_PAGE), null);
  // the register page with its dates in the order of its labels reads the expiry
  assertEquals(expiryFromText('Expiry Date 29/10/2027 Reg. Date 30/10/2026')?.expiry, '2027-10-29');
  // inline, expiry first and issue after it; with Arabic-Indic digits; and a three-year span
  assertEquals(expiryFromText('Expiry Date 14/03/2027 Business Name ZZ DEMO Issue Date 15/03/2026')?.expiry, '2027-03-14');
  assertEquals(expiryFromText('Expiry Date ١٤/٠٣/٢٠٢٧ Issue Date ١٥/٠٣/٢٠٢٦')?.expiry, '2027-03-14');
  assertEquals(expiryFromText('Expiry Date 14/03/2029 Issue Date 15/03/2026')?.expiry, '2029-03-14');
});

Deno.test('a label is not a value: "Legal Type الشكل القانون" reads no legal form, and code reads no field wrongly on the DET layout', () => {
  const f = licenceFieldsFromText(DET_FILE);
  assertEquals(f.legal_form, null);                 // main: 'الشكل القانون', the Arabic label
  assertEquals(f.expiry_date, null);                // main: '2026-10-30'
  assertEquals(f.licence_no, '9990001');
  assertEquals(licenceFieldsFromText('Legal Type: Legal Form').legal_form, null);
  assertEquals(licenceFieldsFromText('Legal Type: Limited Liability Company').legal_form, 'Limited Liability Company');
});

Deno.test("the founder's case through the one row rule: code's wrong expiry gives way to the model's sure reading", () => {
  // what main stored: code expiry 2026-10-30 (the Reg. Date), and the model's issue date 2026-10-30
  const r = modelReadingToRow(MODEL_RIGHT, { fields: { licence_no: '9990001' }, expiry: '2026-10-30', name: null, issue: null });
  assertEquals(r.upd.license_expiry, '2027-10-29');
  assertEquals(r.issue, '2026-10-30');
  assertEquals(r.license.expiry, '2027-10-29');
  assertEquals(licenceHasExpired(String(r.upd.license_expiry), NOW), false);
  assertEquals(r.disagreements.map((d) => d.field), ['expiry_date']);
  // the merge the accuracy suite measures says the same
  assertEquals(mergeLicenceReads({ expiry_date: '2026-10-30' }, MODEL_RIGHT).merged.expiry_date, '2027-10-29');
});

Deno.test('an expiry not after the issue date is no reading, whoever read it: unread, never "expired"', () => {
  // code's expiry on its own issue date, the model 'low' (it only fills blanks): the expiry is unread
  const m = mergeLicenceReads({ expiry_date: '2026-10-30', issue_date: '2026-10-30' }, { confidence: 'low', legal_name_ar: 'زد' }).merged;
  assertEquals(m.expiry_date, null);
  // code's expiry before the model's issue date: dropped from the row
  const r = modelReadingToRow({ ...MODEL_RIGHT, expiry_date: '', confidence: 'high' }, { fields: {}, expiry: '2026-10-30', name: null, issue: null });
  assertEquals(r.upd.license_expiry, null);
  // the model's own pair reversed: both dates unread (license_extract asks once more first)
  const c = checkLicenceRead({ license_number: '9990001', issue_date: '2027-10-29', expiry_date: '2026-10-30' }, null);
  assertEquals([c.doc.issue_date, c.doc.expiry_date, c.check.failed], [null, null, ['expiry_not_after_issue']]);
  assertEquals(mergeLicenceReads(null, { ...MODEL_RIGHT, issue_date: '2027-10-29', expiry_date: '2026-10-30' }).merged.expiry_date, null);
});

Deno.test("while the model has not answered, code's expiry stands only where it cannot refuse", () => {
  assertEquals(codeExpiryMayStand('2026-10-30', null, '2026-11-12'), false);        // past: never written by code
  assertEquals(codeExpiryMayStand('2027-10-29', '2026-10-30', '2026-11-12'), true);
  assertEquals(codeExpiryMayStand('2027-10-29', '2027-10-29', '2026-11-12'), false); // not after its issue date
  assertEquals(codeExpiryMayStand('2026-11-12', null, '2026-11-12'), true);         // expires today: still in date today
  assertEquals(codeExpiryMayStand(null, null, '2026-11-12'), false);
});

Deno.test('a licence that really has expired is still refused, on the model reading', () => {
  const text = 'License No. ZZ-7700123\nIssue Date: 15/03/2021\nExpiry Date: 14/03/2024';
  assertEquals(expiryFromText(text)?.expiry, '2024-03-14');                   // code reads it right...
  assertEquals(codeExpiryMayStand('2024-03-14', '2021-03-15', '2026-11-12'), false);   // ...but may not refuse on it
  const r = modelReadingToRow({ legal_name: 'ZZ DEMO Old Trading LLC', license_number: 'ZZ-7700123', issue_date: '2021-03-15', expiry_date: '2024-03-14', confidence: 'high' },
    { fields: { licence_no: 'ZZ-7700123' }, expiry: null, name: null, issue: '2021-03-15' });
  assertEquals(r.upd.license_expiry, '2024-03-14');
  assertEquals(licenceHasExpired(String(r.upd.license_expiry), NOW), true);
});

Deno.test('the text-layer check only notes; it never blanks, holds or refuses a reading', () => {
  // the right answer is printed in the text (dates glued together on the register page, too)
  assert(datesPrintedIn(DET_FILE).has('2027-10-29') && datesPrintedIn(DET_FILE).has('2026-10-30'));
  assert(numberPrintedIn('9990001', DET_FILE));
  assert(!numberPrintedIn('999000', DET_FILE));                               // never part of a longer run of digits
  const ok = checkLicenceRead(MODEL_RIGHT, DET_FILE);
  assertEquals([ok.check.grounded, ok.check.failed, ok.check.notes], [true, [], []]);
  // a date the text does not print: noted for our reviewer, and the value stands
  const miss = checkLicenceRead({ ...MODEL_RIGHT, expiry_date: '2028-10-29' }, DET_FILE);
  assertEquals(miss.doc.expiry_date, '2028-10-29');
  assertEquals(miss.check.notes, ['expiry_date_not_in_text_layer']);
  // a text layer that is not this licence's (a scan with a footer): nothing is compared
  assertEquals(checkLicenceRead(MODEL_RIGHT, 'Page 1 of 1').check, { failed: [], notes: [], grounded: false });
});

Deno.test('the original PDF goes beside its page pictures only when switched on', async () => {
  const { documentContent } = await import('./licence_extract.ts');
  const page = { mime: 'image/jpeg', data: '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U' };
  const body = { file_b64: 'JVBERi0xLjQKJcfsj6IKNSAwIG9iago=', mime: 'application/pdf', filename: 'ZZ_DEMO_licence.pdf' };
  assertEquals(documentContent('read', [page], body).map((p: { type: string }) => p.type), ['text', 'image_url']);
  assertEquals(documentContent('read', [page], body, { withFile: true }).map((p: { type: string }) => p.type), ['text', 'image_url', 'file']);
  assertEquals(documentContent('read', [page], { ...body, mime: 'image/png' }, { withFile: true }).map((p: { type: string }) => p.type), ['text', 'image_url']);
});
