// A blank or 1px licence image yields NO fields (stage-2 run 3 S02, 12 Oct 2026, sales_engineer).
// The vision model answered a 1x1 PNG with expiry 2023-03-14 and licence number 123456 (ai_cost_log 19449);
// these replay that answer through the exact normaliser license_extract uses and assert nothing survives.
import { assertEquals } from 'jsr:@std/assert@1';
import { imageDims, imagesTooSmallToRead, licenceFromGateway, lowReadProven, normaliseLicence, placeholderLicenceNo, SYS_LICENSE, UNREADABLE_LICENCE } from './licence_extract.ts';
import { licenceNameFromModel, mergeLicenceReads } from './document_expiry.ts';

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

// THE MODEL'S OWN ANSWER, 28 Oct 2026 (supplier-journey audit, run fbe21d49, ai_gateway fn license_extract): a licence whose
// one name line is "Trade Name". Every field read, confidence 'medium', the name only in trade_name. Before the fix this
// normaliser returned UNREADABLE and the supplier was held as licence_unreadable ("upload a clearer copy").
const tradeNameOnlyAnswer = { legal_name: '', legal_name_ar: '', trade_name: 'ZZ DEMO S3 Expired Aluminium fbe21d49', legal_form: 'Limited Liability Company',
  license_number: 'ZZDEMO-FBE21D49-S3', license_authority: 'Dubai Department of Economy and Tourism', emirate: 'Dubai', city: 'Dubai',
  issue_date: '2025-09-28', expiry_date: '2026-09-27', activities: ['Aluminium and Glass Works'], trn: '', confidence: 'medium' };

Deno.test('a licence that prints its name only as a Trade Name is read: the trade name is the licensed name', () => {
  const d = normaliseLicence(tradeNameOnlyAnswer);
  assertEquals([d.unreadable, d.legal_name, d.trade_name, d.license_number, d.expiry_date, d.emirate, d.confidence],
               [false, 'ZZ DEMO S3 Expired Aluminium fbe21d49', 'ZZ DEMO S3 Expired Aluminium fbe21d49', 'ZZDEMO-FBE21D49-S3', '2026-09-27', 'Dubai', 'medium']);
  // a printed legal name still wins over the trade name
  assertEquals(normaliseLicence({ ...tradeNameOnlyAnswer, legal_name: 'ZZ DEMO Holding LLC' }).legal_name, 'ZZ DEMO Holding LLC');
  // and a 'low' trade-name read is as unreadable as a 'low' legal-name read
  assertNoFields(normaliseLicence({ ...tradeNameOnlyAnswer, confidence: 'low' }));
});

Deno.test('the prompt tells the model a lone English Trade Name is the licensed name, and never the Arabic name', () => {
  assertEquals(SYS_LICENSE.includes('when the licence prints its English name only as a Trade Name, with no separate company or legal name, that English Trade Name IS the licensed name'), true);
  assertEquals(SYS_LICENSE.includes("if the licence prints no English name, an empty string (never a translation, a transliteration or the Arabic name)"), true);
});

// REVIEW OF #1711 (28 Oct 2026). THE MODEL'S OWN RECORDED ANSWERS for the corpus's two Arabic-only licences
// (docs/reports/QuotesDone Sandbox Test 2026-10/documents/run-arabic-name-gateway/model.json): the model writes the Arabic
// name in trade_name as well as in legal_name_ar. The first version of the fallback took any trade name, so these put the
// Arabic name in legal_name: licenceNameFromModel then wrote it to leads.licence_legal_name and the review (ruling 1176)
// renamed the supplier's company in Arabic and could approve it, where the corpus expects the name held for a person.
const ajmanArabicOnly = { legal_name: '', legal_name_ar: 'زد زد ديمو الواحة', trade_name: 'زد زد ديمو الواحة', legal_form: 'مؤسسة فردية',
  license_number: '20840', license_authority: 'دائرة التنمية الاقتصادية - عجمان', emirate: 'Ajman', city: 'Ajman', issue_date: '2024-04-13',
  expiry_date: '2027-04-12', activities: ['تركيب أنظمة التكييف والتهوية', 'أعمال تنسيق الحدائق'], trn: '', confidence: 'medium' };
const fujairahArabicOnly = { legal_name: '', legal_name_ar: 'زد زد ديمو الأفق', trade_name: 'زد زد ديمو الأفق', legal_form: 'شركة ذات مسؤولية محدودة',
  license_number: '44633', license_authority: 'دائرة الصناعة والاقتصاد - الفجيرة', emirate: 'Fujairah', city: 'Fujairah', issue_date: '2025-05-14',
  expiry_date: '2027-05-13', activities: ['أعمال تبليط الأرضيات والجدران', 'أعمال الزجاج'], trn: '', confidence: 'high' };

Deno.test('an Arabic trade name never becomes legal_name, the English name (the recorded Arabic-only answers)', () => {
  for (const a of [ajmanArabicOnly, fujairahArabicOnly]) {
    const d = normaliseLicence(a);
    assertEquals([d.unreadable, d.legal_name, d.legal_name_ar, d.trade_name, d.license_number, d.expiry_date],
                 [false, '', a.legal_name_ar, a.trade_name, a.license_number, a.expiry_date], a.license_number);
    assertEquals(licenceNameFromModel(d), null, 'an Arabic-only licence leaves the licence name unread, for a person to compare');
    assertEquals(mergeLicenceReads(null, d).merged.legal_name_en, null);
  }
  // an Arabic trade name carrying a Latin legal-form suffix is still not an English name
  assertEquals(normaliseLicence({ ...ajmanArabicOnly, trade_name: 'زد زد ديمو الواحة LLC' }).legal_name, '');
  assertEquals(normaliseLicence({ ...ajmanArabicOnly, legal_name_ar: '', trade_name: 'زد زد ديمو الواحة LLC' }).unreadable, true);
});

Deno.test("an Arabic-only read 'low' whose trade name is the Arabic name keeps its number and expiry (stage-2 S21)", () => {
  const d = normaliseLicence({ ...ajmanArabicOnly, confidence: 'low' });
  assertEquals([d.unreadable, d.legal_name, d.license_number, d.expiry_date, d.confidence], [false, '', '20840', '2027-04-12', 'low']);
  // an Arabic legal name printed beside an English trade name, read 'low': the same as before the fallback, no English name
  const e = normaliseLicence({ ...ajmanArabicOnly, trade_name: 'ZZ DEMO Oasis Air Conditioning', confidence: 'low' });
  assertEquals([e.unreadable, e.legal_name, e.license_number, e.expiry_date], [false, '', '20840', '2027-04-12']);
});

Deno.test("the trade name stands in only on a 'medium' or 'high' read", () => {
  for (const confidence of [undefined, '', 'unknown', 'LOW']) {
    const d = normaliseLicence({ ...tradeNameOnlyAnswer, confidence });
    assertEquals(d.unreadable, true, String(confidence));   // no English legal name and no Arabic name: no licensee read
  }
  assertEquals(normaliseLicence({ ...tradeNameOnlyAnswer, confidence: 'high' }).legal_name, tradeNameOnlyAnswer.trade_name);
});

// What the review compares. Every upload path writes leads.licence_legal_name from licenceNameFromModel(doc); the review
// (fn_sales_engineer_verifies_supplier) compares it with the registered company name. The trade name must arrive there
// verbatim, so a different registered name is a difference the review sees (ruling 1176: the company takes the licence's
// name; a name another claimed supplier holds is held as licence_name_mismatch), and a 'low' read must leave it unread,
// which the review holds as licence_unreadable and never approves automatically.
Deno.test('a trade-name-only read reaches the licence name verbatim, and a low one leaves it unread', () => {
  assertEquals(licenceNameFromModel(normaliseLicence(tradeNameOnlyAnswer)), 'ZZ DEMO S3 Expired Aluminium fbe21d49');
  assertEquals(mergeLicenceReads(null, normaliseLicence(tradeNameOnlyAnswer)).merged.legal_name_en, 'ZZ DEMO S3 Expired Aluminium fbe21d49');
  assertEquals(licenceNameFromModel(normaliseLicence({ ...tradeNameOnlyAnswer, trade_name: 'ZZ DEMO Another Company' })), 'ZZ DEMO Another Company');
  assertEquals(licenceNameFromModel(normaliseLicence({ ...tradeNameOnlyAnswer, confidence: 'low' })), null);
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

// REVIEW OF #1707 (28 Oct 2026, sales_engineer). The data URL names the page's own type, and a page that is not
// base64 never reaches the provider: the request falls back to the file, or license_extract refuses it by name.
import { hasReadablePage, pageMime } from './licence_extract.ts';
const JPEG_B64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDA==';

Deno.test("the data URL carries the page's mime, image/jpeg or image/png, never a fixed one", () => {
  const png = pngHeader(1240, 1754);
  assertEquals(urlsOf(documentContent('read', [{ mime: 'image/jpeg', data: JPEG_B64 }], {}))[0].startsWith('data:image/jpeg;base64,/9j/'), true);
  assertEquals(urlsOf(documentContent('read', [{ mime: 'image/png', data: png }], {}))[0].startsWith('data:image/png;base64,iVBOR'), true);
  // no mime named (a bare string, or an empty/non-image mime): the bytes decide, and a data URL's own prefix wins
  assertEquals([pageMime(png), pageMime(JPEG_B64), pageMime({ data: png, mime: '' }), pageMime({ b64: png, mime: 'application/pdf' })],
    ['image/png', 'image/jpeg', 'image/png', 'image/png']);
  assertEquals(pageMime('data:image/png;base64,' + png), 'image/png');
  assertEquals(urlsOf(documentContent('read', ['data:image/png;base64,' + png], {}))[0], 'data:image/png;base64,' + png);
});

Deno.test('an empty or invalid page is never sent: the file is read instead, or nothing is readable', () => {
  const bad = [{ mime: 'image/png', data: '' }, { mime: 'image/png', data: '[object Object]' }, { mime: 'image/png', data: { x: 1 } }, { mime: 'image/png' }, 'https://x/y.png'];
  for (const im of bad) assertEquals(pageB64(im), '', JSON.stringify(im));
  // the portal sends the PDF beside its pages: no usable page -> the file goes, as a file
  const c = documentContent('read', bad, { file_b64: 'JVBERi0xLjQKJcfsj6IKNSAwIG9iago=', mime: 'application/pdf', filename: 'l.pdf' });
  assertEquals([c.length, c[1].type, urlsOf(c).length], [2, 'file', 0]);
  assertEquals(hasReadablePage(bad, {}), false);                      // license_extract answers 400 no_readable_page
  assertEquals(hasReadablePage(bad, { file_b64: 'JVBERi0xLjQKJcfsj6IKNSAwIG9iago=' }), true);
  assertEquals(hasReadablePage([{ mime: 'image/jpeg', data: JPEG_B64 }], {}), true);
  assertEquals(documentContent('read', bad, {}).length, 1);           // nothing but the instruction: never garbage
  // a valid page among invalid ones is the only one sent
  assertEquals(urlsOf(documentContent('read', [...bad, { mime: 'image/jpeg', data: JPEG_B64 }], {})).length, 1);
});

Deno.test('license_extract refuses a request with no readable page before any model is asked', async () => {
  const src = await Deno.readTextFile(new URL('../license_extract/index.ts', import.meta.url));
  const guard = src.indexOf('!hasReadablePage(images, body)'), model = src.indexOf('await fetch(GW');
  assertEquals(guard > 0 && guard < model, true);
});

Deno.test('quote_extract reads the portal page shape through the same reader (its uploads send { mime, data } too)', async () => {
  const src = await Deno.readTextFile(new URL('../quote_extract/index.ts', import.meta.url));
  assertEquals(/import \{ pageB64, pageMime \} from '\.\.\/_shared\/licence_extract\.ts'/.test(src), true);
  assertEquals(/const b = im\?\.b64 \|\| im;/.test(src), false);
});
