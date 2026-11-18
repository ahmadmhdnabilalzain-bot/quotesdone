// A LONG LICENCE FILE IS READ BY ITS FIRST PAGES (18 Nov 2026, sales_engineer; founder ruling 1728). Measured 17 Nov 2026: Shine Carpets'
// 28-page "TRADE LCS SHINE CARPETS WASHING LLC.pdf" was filed "Not a trade licence" by its page count alone (ruling 1681's rule), unread,
// though its licence was on its first pages. No paid call: every model answer below is a STAND-IN written as a model would return it; both
// long files are synthetic ZZ DEMO PDFs built here (scripts/lib/demo_pdf.mjs): 28 pages whose page 1 is a free-zone licence, and 28 pages
// whose page 1 is a company profile.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a file of more than 8 pages is refused before any model reads it, when its first pages can be given (the 28-page licence above);
//   * the reader is sent the whole long file, or more than LONG_FILE_PAGES_READ pages, or is not told which pages it holds;
//   * a licence on page 1 of a long file is not read as the licence; a profile on page 1 is not named, or its sentence loses the pages
//     read, "attach just the licence pages" or the way to a person;
//   * the reader's knowledge of licensing authorities is Dubai mainland only (a DMCC, RAKEZ, SHAMS or Ajman licence is not named);
//   * license_extract asks the model before cutting, refuses a cuttable file, or keys the refused-twice task on the cut instead of the file.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { licenceExtractRequest, licenceSecondReadRequest, licenceJudgementOf, normaliseLicence, wrongDocumentOf, SYS_LICENSE, NOT_A_LICENCE_WAY_TO_A_PERSON } from './licence_extract.ts';
import { LICENCE_MAX_PAGES, LONG_FILE_PAGES_READ, LONG_FILE_CUT_MAX_BYTES, firstPagesOfALongFile, licencePageCount, longFileNote, tooManyPagesForALicence, withLongFileWindow } from './licence_pages.ts';
import { demoPdfPages } from '../../../scripts/lib/demo_pdf.mjs';

const b64 = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000)); return btoa(s); };
const bytes = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
type Line = [string, number];
const FOOT: Line = ['(QuotesDone synthetic fixture - not a real company)', 8];
const LICENCE_PAGE: Line[] = [['ZZ DEMO DMCC Free Zone - Trade Licence', 14], ['Dubai Multi Commodities Centre Authority (DMCC)', 11],
  ['Licence No: ZZ-DMCC-777001', 11], ['Company: ZZ DEMO Saqr Carpet Washing DMCC', 11], ['Legal form: Free Zone Company', 10],
  ['Issue date: 01/07/2026   Expiry date: 30/06/2027', 10], ['Activities: Carpet and upholstery cleaning services', 10], FOOT];
const PROFILE_PAGE: Line[] = [['ZZ DEMO Saqr Carpet Washing - Company Profile', 14], ['About us: carpet and upholstery cleaning across the UAE since 2015.', 10],
  ['Our services: carpet washing, sofa cleaning, curtain cleaning.', 10], FOOT];
const filler = (i: number): Line[] => [[`ZZ DEMO Saqr Carpet Washing - page ${i} of 28: project ZZ DEMO Tower ${i}`, 11], FOOT];
const LONG_LICENCE = demoPdfPages([LICENCE_PAGE, ...Array.from({ length: 27 }, (_, i) => filler(i + 2))]) as Uint8Array;
const LONG_PROFILE = demoPdfPages([PROFILE_PAGE, ...Array.from({ length: 27 }, (_, i) => filler(i + 2))]) as Uint8Array;

async function pageTexts(pdf: Uint8Array): Promise<string[]> {
  const { getDocumentProxy, extractText } = await import('npm:unpdf@0.11.0');
  const doc = await getDocumentProxy(new Uint8Array(pdf));
  const { text } = await extractText(doc, { mergePages: false });
  return text as unknown as string[];
}
// deno-lint-ignore no-explicit-any
const fileOf = (req: any) => req.input[0].content.filter((c: any) => c.type === 'file');
// deno-lint-ignore no-explicit-any
const introOf = (req: any) => String(req.input[0].content[0].text);

Deno.test('a 28-page PDF is cut to its first 3 pages for the reader; up to 8 pages, or uncounted, it is read whole', async () => {
  assertEquals([LICENCE_MAX_PAGES, LONG_FILE_PAGES_READ], [8, 3]);
  const payload = { file_b64: b64(LONG_LICENCE), mime: 'application/pdf', filename: 'TRADE LCS ZZ DEMO.pdf' };
  const pages = await licencePageCount(payload);
  assertEquals(pages, 28);
  const first = await firstPagesOfALongFile(payload, pages);
  assert(first, 'a cuttable 28-page PDF was not given to the reader');
  assertEquals(first.window, { read: 3, of: 28 });
  assertEquals(first.payload.mime, 'application/pdf');
  assertEquals(first.payload.filename, 'TRADE LCS ZZ DEMO.pdf');
  assertEquals(await licencePageCount(first.payload), 3);
  const texts = await pageTexts(bytes(first.payload.file_b64!));
  assertStringIncludes(texts[0], 'ZZ-DMCC-777001');
  assert(!texts.join(' ').includes('page 28 of 28'), 'a page after the first three reached the reader');
  for (const n of [null, 1, 4, 8]) assertEquals(await firstPagesOfALongFile(payload, n), null, String(n));
});

Deno.test('page pictures are kept by count; a long PDF that cannot be cut goes as its pictures, or is answered by its count', async () => {
  const pics = Array.from({ length: 20 }, (_, i) => ({ mime: 'image/jpeg', data: `/9j/${'A'.repeat(40)}${i}` }));
  const damaged = b64(new TextEncoder().encode('%PDF-1.4 damaged beyond reading'));
  const withPics = await firstPagesOfALongFile({ images: pics, file_b64: damaged, mime: 'application/pdf' }, 20);
  assert(withPics);
  assertEquals(withPics.payload.images!.length, 3);
  assertEquals(withPics.payload.file_b64, undefined, 'an uncut PDF went beside the first pictures');
  assertEquals(withPics.window, { read: 3, of: 20 });
  // portal shape: pictures and the PDF itself; both cut
  const both = await firstPagesOfALongFile({ images: pics.slice(0, 12), file_b64: b64(LONG_PROFILE), mime: 'application/pdf' }, 12);
  assertEquals([both!.payload.images!.length, await licencePageCount({ file_b64: both!.payload.file_b64, mime: 'application/pdf' })], [3, 3]);
  // no pictures and no cut: never sent whole; the count answers it, as under ruling 1681
  assertEquals(await firstPagesOfALongFile({ file_b64: damaged, mime: 'application/pdf' }, 28), null);
  assertEquals(tooManyPagesForALicence(28)!.kind, 'long_file');
  assertStringIncludes(tooManyPagesForALicence(28)!.message, 'we could not open it to read its first pages');
  assert(LONG_FILE_CUT_MAX_BYTES >= 10 * 1024 * 1024, 'the cut refuses a file the portal accepts (10 MB)');
});

Deno.test('the reader is told it holds the first 3 of 28 pages, on the first read and the second, and gets one 3-page file', async () => {
  const first = (await firstPagesOfALongFile({ file_b64: b64(LONG_LICENCE), mime: 'application/pdf' }, 28))!;
  const note = longFileNote(first.window);
  assertStringIncludes(note, 'This file has 28 pages; you are given only its first 3.');
  assertStringIncludes(note, 'any UAE licensing authority');
  for (const req of [licenceExtractRequest(first.payload, 'zz-subject', note), licenceSecondReadRequest(first.payload, 'zz-subject', 'anthropic/zz-demo', note)]) {
    assertStringIncludes(introOf(req), 'you are given only its first 3');
    const files = fileOf(req);
    assertEquals(files.length, 1);
    assertEquals(await licencePageCount({ file_b64: String(files[0].file.file_data).replace(/^data:[^;]+;base64,/, ''), mime: 'application/pdf' }), 3);
  }
  // a short file's request is unchanged
  assert(!introOf(licenceExtractRequest({ file_b64: b64(LONG_LICENCE), mime: 'application/pdf' }, null)).includes('you are given only'));
});

Deno.test('judged like a human: a licence on page 1 is the reading; a profile on page 1 is named with the pages read and a way to a person', () => {
  const w = { read: 3, of: 28 };
  // stand-in answer for the 28-page licence: the reader sees a DMCC free-zone licence on page 1
  const licence = { legal_name: 'ZZ DEMO Saqr Carpet Washing DMCC', license_number: 'ZZ-DMCC-777001', license_authority: 'Dubai Multi Commodities Centre Authority (DMCC)',
    emirate: 'Dubai', issue_date: '2026-07-01', expiry_date: '2027-06-30', activities: ['Carpet and upholstery cleaning services'], confidence: 'high',
    document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'page 1 is a DMCC trade licence; the later pages are a company profile' };
  assertEquals(licenceJudgementOf(licence).outcome, 'licence');
  const read = normaliseLicence(licence);
  assertEquals([read.license_number, read.license_authority, read.expiry_date, read.wrong_document ?? null], ['ZZ-DMCC-777001', 'Dubai Multi Commodities Centre Authority (DMCC)', '2027-06-30', null]);
  // stand-in answer for the 28-page profile: the first three pages describe services, no licence on them
  const profile = { legal_name: 'ZZ DEMO Saqr Carpet Washing', license_number: '', license_authority: '', expiry_date: '', confidence: 'low',
    document_kind: 'company_profile', document_kind_confidence: 'high', document_kind_why: 'a company profile: services and projects, no licence number, authority or expiry' };
  const wrong = wrongDocumentOf(profile)!;
  assertEquals(wrong.kind, 'company_profile');
  const named = withLongFileWindow(wrong, w);
  assertEquals(named.message, `This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below. We read the first 3 of its 28 pages. If your licence is inside this file, please attach just the licence pages. ${NOT_A_LICENCE_WAY_TO_A_PERSON}`);
  assertStringIncludes(named.why, 'pages 1-3 of 28 read');
});

Deno.test('the reader knows every UAE licensing authority, not Dubai mainland only', () => {
  for (const a of ['DET', 'ADDED', 'SEDD', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'DMCC', 'JAFZA', 'DAFZA', 'IFZA', 'Meydan', 'DIFC', 'ADGM',
    'RAKEZ', 'SAIF Zone', 'SHAMS', 'Hamriyah', 'Ajman Free Zone', 'KEZAD', 'UAQ FTZ', 'never only Dubai']) assertStringIncludes(SYS_LICENSE, a);
});

Deno.test('license_extract cuts before any model is asked, refuses only an uncut long file, and keeps the whole file\'s SHA', async () => {
  const src = await Deno.readTextFile(new URL('../license_extract/index.ts', import.meta.url));
  const cut = src.indexOf('firstPagesOfALongFile('), model = src.indexOf('await fetch(GW');
  assert(cut > 0 && cut < model, 'the cut comes after the model call');
  assert(/const long = first \? null : tooManyPagesForALicence\(pages\);/.test(src), 'a cuttable long file is refused by its count');
  assert(/buildContent\(mode, images, body, withFile, note\)/.test(src), 'the first read is not told which pages it holds');
  assert(/licenceSecondReadRequest\([^;]+firstModel, note\)/.test(src), 'the second read is not told which pages it holds');
  assert(/withLongFileWindow\(s\.doc\.wrong_document, pagesWindow\)/.test(src), 'a named long file does not say which pages were read');
  assertEquals((src.match(/licenceFileSha\(original\)/g) || []).length, 2, 'the refused-twice task is keyed on the cut, not the file');
});
