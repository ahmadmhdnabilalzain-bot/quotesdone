// A blank or 1px licence image yields NO fields (stage-2 run 3 S02, 12 Oct 2026, sales_engineer).
// The vision model answered a 1x1 PNG with expiry 2023-03-14 and licence number 123456 (ai_cost_log 19449);
// these replay that answer through the exact normaliser license_extract uses and assert nothing survives.
import { assertEquals } from 'jsr:@std/assert@1';
import { imageDims, imagesTooSmallToRead, licenceFromGateway, lowReadProven, normaliseLicence, placeholderLicenceNo, UNREADABLE_LICENCE } from './licence_extract.ts';

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

// Stage-2 run 4 S21, lic_ajman_ded_ar_png: an Arabic-only licence, which the prompt makes the model call 'low'.
const arabicOnlyAnswer = { legal_name: '', legal_name_ar: 'زد زد ديمو الواحة', trade_name: '', legal_form: 'مؤسسة فردية',
  license_number: '20840', license_authority: 'Ajman Department of Economic Development', emirate: 'Ajman', city: 'Ajman',
  issue_date: '2026-04-13', expiry_date: '2027-04-12', activities: ['تكييف الهواء'], trn: '', confidence: 'low' };

Deno.test("an Arabic-only licence read 'low' keeps its fields (number, expiry, Arabic name)", () => {
  const d = normaliseLicence(arabicOnlyAnswer);
  assertEquals([d.unreadable, d.license_number, d.expiry_date, d.legal_name_ar, d.legal_name, d.emirate, d.confidence],
               [false, '20840', '2027-04-12', 'زد زد ديمو الواحة', '', 'Ajman', 'low']);
});

Deno.test("a 'low' read with only an English name, or with no name, is still unreadable", () => {
  assertNoFields(normaliseLicence({ ...arabicOnlyAnswer, legal_name: 'Invented Trading LLC', legal_name_ar: '' }));
  assertNoFields(normaliseLicence({ ...arabicOnlyAnswer, legal_name_ar: '' }));
});

// The run-3 fixture image: a 1x1 PNG. The guard decides on it BEFORE any model answer exists, so an invented
// Arabic name, number and expiry from the model can never reach normaliseLicence for it.
const PNG_1PX = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const pngHeader = (w: number, h: number) => { const u = new Uint8Array(24); u.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  new DataView(u.buffer).setUint32(16, w); new DataView(u.buffer).setUint32(20, h); return btoa(String.fromCharCode(...u)); };

Deno.test('the blank-image guard runs before the model: a 1x1 PNG is unreadable whatever a model would say', () => {
  assertEquals(imageDims(PNG_1PX), { w: 1, h: 1 });
  assertEquals(imagesTooSmallToRead([{ b64: PNG_1PX, mime: 'image/png' }], {}), true);
  assertEquals(imagesTooSmallToRead([], { file_b64: PNG_1PX, mime: 'image/png' }), true);
  assertNoFields(UNREADABLE_LICENCE());
});

Deno.test('the guard never blocks a page-sized image, a PDF, or an image whose size code cannot read', () => {
  assertEquals(imagesTooSmallToRead([{ b64: pngHeader(1240, 1754) }], {}), false);
  assertEquals(imagesTooSmallToRead([{ b64: PNG_1PX }, { b64: pngHeader(1240, 1754) }], {}), false);
  assertEquals(imagesTooSmallToRead([], { file_b64: btoa('%PDF-1.7'), mime: 'application/pdf' }), false);
  assertEquals(imagesTooSmallToRead([{ b64: btoa('GIF89a....') }], {}), false);
});

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

Deno.test("a 'low' read is kept only with ink measured or its number in the text layer", () => {
  const low = { confidence: 'low', unreadable: false, license_number: '20840' };
  assertEquals(lowReadProven(low, true, null), true);                          // printed image page measured
  assertEquals(lowReadProven(low, false, 'Licence No. 20840 Expiry 12/04/2027'), true);
  assertEquals(lowReadProven({ ...low, license_number: 'CN-1234567' }, false, 'رقم الرخصة CN-1234567 الانتهاء'), true);
  assertEquals(lowReadProven(low, false, 'Licence No. 208401'), false);        // not the same number
  assertEquals(lowReadProven(low, false, null), false);                        // a scan PDF: nothing proven -> held
  assertEquals(lowReadProven({ ...low, confidence: 'medium' }, false, null), true);
});

// THE PORTAL'S PAGE SHAPE (28 Oct 2026, sales_engineer). The registration form sends each licence page as
// { mime, data } (SupplierPortal.tsx fileToImages, me/pdfRaster.ts). documentContent read only `b64`, so the page
// went to the model as "[object Object]" and the provider refused every call: ai_cost_log 27-28 Oct, 38 of 38
// license_extract calls "Invalid image data URL ... payload is not base64-encoded data". Replays that exact input.
import { documentContent, licencePages, pageB64 } from './licence_extract.ts';
const B64 = /^[A-Za-z0-9+/]+={0,2}$/;
const urlsOf = (c: { type: string; image_url?: { url: string } }[]) => c.filter((x) => x.type === 'image_url').map((x) => x.image_url!.url);

Deno.test('a page the portal sends as { mime, data } reaches the model as real base64', () => {
  const page = pngHeader(1240, 1754);
  for (const im of [{ mime: 'image/png', data: page }, { b64: page, mime: 'image/png' }, page]) {
    const urls = urlsOf(documentContent('read', [im], {}));
    assertEquals(urls.length, 1);
    assertEquals(urls[0].startsWith('data:image/png;base64,') || urls[0].startsWith('data:image/jpeg;base64,'), true);
    assertEquals(B64.test(urls[0].replace(/^data:[^;]+;base64,/, '')), true, urls[0].slice(0, 60));
  }
});

Deno.test('the size and ink guards judge a { mime, data } page, not the text of an object', () => {
  assertEquals(imagesTooSmallToRead([{ mime: 'image/png', data: PNG_1PX }], {}), true);
  assertEquals(imagesTooSmallToRead([{ mime: 'image/png', data: pngHeader(1240, 1754) }], {}), false);
  assertEquals(licencePages([{ mime: 'image/png', data: PNG_1PX }], {}), [PNG_1PX]);
  assertEquals([pageB64({}), pageB64(null), pageB64({ data: 5 })], ['', '', '']);
});

Deno.test('the portal still sends pages as { mime, data } (the shape the tests above replay)', async () => {
  const src = await Deno.readTextFile(new URL('../../../src/components/portal/SupplierPortal.tsx', import.meta.url));
  assertEquals(/images:\s*\[\{\s*mime:\s*file\.type,\s*data:\s*b64\s*\}\]/.test(src), true);
  const raster = await Deno.readTextFile(new URL('../../../src/components/me/pdfRaster.ts', import.meta.url));
  assertEquals(/Promise<\{\s*mime:\s*string;\s*data:\s*string\s*\}\[\]>/.test(raster), true);
});
