// A blank or 1px licence image yields NO fields (stage-2 run 3 S02, 12 Oct 2026, sales_engineer).
// The vision model answered a 1x1 PNG with expiry 2023-03-14 and licence number 123456 (ai_cost_log 19449);
// these replay that answer through the exact normaliser license_extract uses and assert nothing survives.
import { assertEquals } from 'jsr:@std/assert@1';
import { licenceFromGateway, normaliseLicence, placeholderLicenceNo } from './licence_extract.ts';

const blankImageAnswer = { legal_name: '', legal_name_ar: '', trade_name: '', legal_form: '', license_number: '123456',
  license_authority: 'Dubai Department of Economy and Tourism', emirate: 'Dubai', city: 'Dubai', issue_date: '2022-03-15',
  expiry_date: '2023-03-14', activities: ['Steel fabrication'], trn: '', confidence: 'medium' };

const assertNoFields = (d: ReturnType<typeof normaliseLicence>) => {
  assertEquals(d.unreadable, true);
  assertEquals([d.legal_name, d.license_number, d.license_authority, d.emirate, d.city, d.trn], ['', '', '', '', '', '']);
  assertEquals([d.issue_date, d.expiry_date, d.activities.length, d.confidence], [null, null, 0, 'low']);
};

Deno.test('a read that names no licensee (a blank 1px image) yields no fields at all', () => assertNoFields(normaliseLicence(blankImageAnswer)));

Deno.test("a read the model calls 'low' yields no fields, even with a name", () =>
  assertNoFields(normaliseLicence({ ...blankImageAnswer, legal_name: 'Some Trading LLC', confidence: 'low' })));

Deno.test('the gateway path answers ok with an unreadable doc for the blank-image reply', () => {
  const r = licenceFromGateway(true, { ok: true, content: JSON.stringify(blankImageAnswer) });
  assertEquals(r.ok, true);
  if (r.ok) assertNoFields(r.doc);
});

Deno.test('a named, confident read keeps its fields but never a placeholder number', () => {
  const d = normaliseLicence({ ...blankImageAnswer, legal_name: 'ZZ DEMO Steel LLC', confidence: 'high' });
  assertEquals([d.unreadable, d.legal_name, d.expiry_date, d.license_number], [false, 'ZZ DEMO Steel LLC', '2023-03-14', '']);
  assertEquals(normaliseLicence({ ...blankImageAnswer, legal_name: 'ZZ DEMO Steel LLC', license_number: '1633275' }).license_number, '1633275');
});

Deno.test('placeholder numbers are runs and repeats only', () => {
  for (const v of ['123456', '000000', '987654', '1111']) assertEquals(placeholderLicenceNo(v), true, v);
  for (const v of ['1633275', 'CN-1234567', '123', '']) assertEquals(placeholderLicenceNo(v), false, v);
});
