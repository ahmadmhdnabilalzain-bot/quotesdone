// THE READER DECIDES WHAT IS A TRADE LICENCE (13 Nov 2026, sales_engineer; founder ruling 1681: "the reader has to confirm ... A trade
// license can never be more than 5 pages, let's say ... a company profile that also prints a license validity date gets the [softer
// sentence]. One of our team will check."). No paid call: every model answer below is a STAND-IN written as a model would return it;
// every PDF is a synthetic ZZ DEMO file built here or in scripts/e2e/fixtures/registration.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the page rule: a PDF of more than LICENCE_MAX_PAGES (8) pages reaches a model whole, or a licence of 1 to 8 pages is refused by code
//     (since ruling 1728, 18 Nov 2026, a longer file is read by its first pages: a_long_licence_file_is_read_by_its_first_pages.test.ts);
//   * an uncountable PDF (damaged) is refused instead of read; the sentence loses its count, its "what to do" or its way to a person;
//   * license_extract counts pages after asking the model;
//   * a file the first reader called a licence, or named at 'high', is read a second time;
//   * the second reader's sure answer does not decide (a licence it reads is not the reading; a non-licence it is sure of is held);
//   * a held file reaches a person while the second reader was sure, or the first prompt (SYS_LICENSE) is changed by the second read;
//   * the e-mail door writes a refused or held file to the supplier's licence.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { normaliseLicence, SYS_LICENSE, SYS_LICENSE_SECOND_READ, licenceSecondReadRequest, secondReadOutcome, licenceJudgementOf, wrongDocumentSentence,
  NOT_A_LICENCE_WAY_TO_A_PERSON, HELD_FOR_PERSON_SENTENCE, type HeldForPerson } from './licence_extract.ts';
import { LICENCE_MAX_PAGES, licencePageCount, longFileSentence, tooManyPagesForALicence } from './licence_pages.ts';
import { decideWithSecondRead, licenceFileSha } from './licence_second_read.ts';
import { demoPdfPages } from '../../../scripts/lib/demo_pdf.mjs';

const b64 = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000)); return btoa(s); };
const pdfOf = (pages: number) => b64(demoPdfPages(Array.from({ length: pages }, (_, i) => [[`ZZ DEMO page ${i + 1}`, 12], ['(QuotesDone synthetic fixture)', 8]])) as Uint8Array);

Deno.test('the page rule: more than 8 pages that cannot be cut is answered by code with the count and what to do; 1 to 8, an image and an uncountable file are read', async () => {
  assertEquals(LICENCE_MAX_PAGES, 8);
  for (const n of [1, 4, 8, 9, 12]) assertEquals(await licencePageCount({ file_b64: pdfOf(n), mime: 'application/pdf' }), n, String(n));
  const fixture = await Deno.readFile(new URL('../../../scripts/e2e/fixtures/registration/N1_long_profile_12_pages.pdf', import.meta.url));
  assertEquals(await licencePageCount({ file_b64: b64(fixture), mime: 'application/pdf' }), 12);
  assertEquals(await licencePageCount({ file_b64: b64(new Uint8Array([0xff, 0xd8, 0xff])), mime: 'image/jpeg' }), 1);
  assertEquals(await licencePageCount({ images: [{ b64: 'AA==' }, { b64: 'AA==' }] }), 2);
  assertEquals(await licencePageCount({ file_b64: b64(new TextEncoder().encode('%PDF-1.4 damaged')), mime: 'application/pdf' }), null);
  assertEquals(await licencePageCount({}), null);
  for (const n of [null, 1, 4, 8]) assertEquals(tooManyPagesForALicence(n), null, String(n));
  const long = tooManyPagesForALicence(23)!;
  assertEquals(long.kind, 'long_file');
  assertEquals(long.message, 'This file has 23 pages, and we could not open it to read its first pages. A trade licence is a short document, usually 1 to 4 pages. Please attach your trade licence here on its own. If this is your company profile, it goes in the Company profile box below. If your licence is inside this file, please attach just the licence pages. If this is your trade licence, reply to our e-mail or write to management@quotesdone.com and we will check it.');
  assertEquals(longFileSentence(9).startsWith('This file has 9 pages,'), true);
  // the finding carries no licence field: the doors treat it exactly as a wrong document (put back, Submit blocked when nothing restored)
  const doc = { ...normaliseLicence({}), wrong_document: long };
  assertEquals([doc.unreadable, doc.license_number, doc.expiry_date, doc.held_for_person], [true, '', null, null]);
});

Deno.test('license_extract counts pages before any model is asked, and asks the other family only for a held reading', async () => {
  const src = await Deno.readTextFile(new URL('../license_extract/index.ts', import.meta.url));
  const pages = src.indexOf('tooManyPagesForALicence(pages)'), model = src.indexOf('await fetch(GW');
  assert(pages > 0 && pages < model, 'the page count comes after the model call');
  assert(src.includes("guard: 'too_many_pages'"));
  assert(/decideWithSecondRead\(s, first\.model,/.test(src), 'the second read is not wired');
});

const HELD: HeldForPerson = { kind: 'company_profile', why: 'a company profile pack', message: HELD_FOR_PERSON_SENTENCE,
  read: { license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism', expiry_date: '2027-06-30', issue_date: '', legal_name: 'ZZ DEMO MEP Contracting LLC' } };
const LICENCE_READ = { legal_name: 'ZZ DEMO MEP Contracting LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism', expiry_date: '2027-06-30',
  issue_date: '2026-07-01', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'page 6 is a DET trade licence' };

Deno.test('the second reader decides: sure licence -> the reading; sure non-licence -> named; unsure or no answer -> a person', () => {
  const rows: [string, Record<string, unknown> | null, string][] = [
    ['trade_licence high', LICENCE_READ, 'licence'],
    ['company_profile high', { document_kind: 'company_profile', document_kind_confidence: 'high', document_kind_why: 'a profile; it quotes the licence' }, 'wrong_document'],
    ['certificate high', { document_kind: 'certificate', document_kind_confidence: 'high', document_kind_why: 'a chamber of commerce certificate' }, 'wrong_document'],
    ['trade_licence medium', { ...LICENCE_READ, document_kind_confidence: 'medium' }, 'held_for_person'],
    ['certificate medium', { document_kind: 'certificate', document_kind_confidence: 'medium' }, 'held_for_person'],
    ['unreadable', { document_kind: 'unreadable', document_kind_confidence: 'high' }, 'held_for_person'],
    ['no answer', null, 'held_for_person'],
  ];
  for (const [name, second, want] of rows) assertEquals(secondReadOutcome(HELD, second, 'anthropic/zz-demo').outcome, want, name);
  const named = secondReadOutcome(HELD, rows[2][1]);
  assertEquals(named.outcome === 'wrong_document' && named.wrong.message, wrongDocumentSentence('certificate'));
  const held = secondReadOutcome(HELD, null, 'anthropic/zz-demo');
  assertEquals(held.outcome === 'held_for_person' && held.held.second_read, { model: 'anthropic/zz-demo', kind: 'no_answer', confidence: '', why: '' });
});

// THE OUTCOMES TABLE for 1 to 8 pages: the first reader's answer x the second reader's answer -> what he sees, what is stored, who is asked.
Deno.test('the outcomes table: first reader x second reader -> named / read / held, and the second read only where the first was unsure', async () => {
  const settle = async (raw: Record<string, unknown>) => ({ doc: normaliseLicence(raw) });
  const PROFILE_PAGE = { ...LICENCE_READ, document_kind: 'company_profile', document_kind_why: 'a company profile that prints its licence and its validity date' };
  const rows: [string, Record<string, unknown>, Record<string, unknown> | null | 'not asked', string, string | null][] = [
    // name, first answer, second answer, outcome, stored licence number
    ['licence, sure', LICENCE_READ, 'not asked', 'licence', 'ZZ-555001'],
    ['licence, first reader low on its kind', { ...LICENCE_READ, document_kind: 'certificate', document_kind_confidence: 'low' }, 'not asked', 'licence', 'ZZ-555001'],
    ['profile, sure, number + authority', { ...PROFILE_PAGE, expiry_date: '' }, 'not asked', 'wrong_document', null],
    ['chamber certificate, sure, validity only', { ...LICENCE_READ, license_authority: '', document_kind: 'certificate' }, 'not asked', 'wrong_document', null],
    ['chamber certificate, sure, authority+expiry, second: certificate', { ...LICENCE_READ, license_authority: 'Dubai Chamber of Commerce and Industry', document_kind: 'certificate' }, { document_kind: 'certificate', document_kind_confidence: 'high' }, 'wrong_document', null],
    ['professional licence called other, sure, authority+expiry, second: licence', { ...LICENCE_READ, document_kind: 'other' }, LICENCE_READ, 'licence', 'ZZ-555001'],
    ['other, sure, nothing read', { document_kind: 'other', document_kind_confidence: 'high' }, 'not asked', 'wrong_document', null],
    ['profile printing authority + validity, second: licence', PROFILE_PAGE, LICENCE_READ, 'licence', 'ZZ-555001'],
    ['profile printing authority + validity, second: profile', PROFILE_PAGE, { document_kind: 'company_profile', document_kind_confidence: 'high' }, 'wrong_document', null],
    ['profile printing authority + validity, second: unsure', PROFILE_PAGE, { document_kind: 'company_profile', document_kind_confidence: 'medium' }, 'held_for_person', null],
    ['certificate at medium, second: certificate sure', { ...LICENCE_READ, document_kind: 'certificate', document_kind_confidence: 'medium' }, { document_kind: 'certificate', document_kind_confidence: 'high' }, 'wrong_document', null],
    ['licence called other at medium, second: licence', { ...LICENCE_READ, document_kind: 'other', document_kind_confidence: 'medium' }, LICENCE_READ, 'licence', 'ZZ-555001'],
    ['held, second reader gives no answer', PROFILE_PAGE, null, 'held_for_person', null],
    ['unreadable', { document_kind: 'unreadable', document_kind_confidence: 'high', confidence: 'low' }, 'not asked', 'licence', ''],
  ];
  for (const [name, firstRaw, secondRaw, want, number] of rows) {
    let calls = 0;
    const { s, second } = await decideWithSecondRead({ doc: normaliseLicence(firstRaw) }, 'openai/zz-demo-first', async (m) => {
      calls++; assertEquals(m, 'openai/zz-demo-first', 'the second read names the first answer\'s model as the counterpart');
      return secondRaw === 'not asked' || secondRaw === null ? null : { ai: secondRaw, model: 'anthropic/zz-demo-second' };
    }, settle);
    const got = s.doc.wrong_document ? 'wrong_document' : s.doc.held_for_person ? 'held_for_person' : 'licence';
    assertEquals(got, want, name);
    assertEquals(calls, secondRaw === 'not asked' ? 0 : 1, `${name}: second reads`);
    assertEquals(second.asked, secondRaw !== 'not asked', name);
    if (number !== null) assertEquals(s.doc.license_number, number, name);
    else assertEquals([s.doc.license_number, s.doc.license_authority, s.doc.expiry_date], ['', '', null], `${name}: nothing stored`);
    if (s.doc.wrong_document) assert(s.doc.wrong_document.message.endsWith(NOT_A_LICENCE_WAY_TO_A_PERSON), name);
  }
  // without the first answer's model the other family cannot be named: no second read, a person (as before)
  const noModel = await decideWithSecondRead({ doc: normaliseLicence(PROFILE_PAGE) }, null, () => { throw new Error('asked'); }, settle);
  assertEquals([noModel.second.asked, !!noModel.s.doc.held_for_person], [false, true]);
});

Deno.test('the second read asks the other family one direct question before the unchanged first prompt', () => {
  assert(SYS_LICENSE_SECOND_READ.endsWith(SYS_LICENSE), 'the first prompt is changed inside the second');
  assert(SYS_LICENSE_SECOND_READ.startsWith('SECOND READ.'));
  const req = licenceSecondReadRequest({ file_b64: pdfOf(1), mime: 'application/pdf', filename: 'zz.pdf' }, null, 'openai/zz-demo-first');
  assertEquals([req.fn, req.counterpart_model, req.sys === SYS_LICENSE_SECOND_READ], ['license_extract', 'openai/zz-demo-first', true]);
  assertEquals(req.input[0].content.some((c: { type: string }) => c.type === 'file'), true);
  // a first answer the reader called a licence never needs it
  assertEquals(licenceJudgementOf(LICENCE_READ).outcome, 'licence');
});

Deno.test('the same file gives the same SHA-256 (the twice-refused task), a different file another', async () => {
  const a = await licenceFileSha({ file_b64: pdfOf(2) }), b = await licenceFileSha({ file_b64: pdfOf(2) }), c = await licenceFileSha({ file_b64: pdfOf(3) });
  assertEquals([a?.length, a === b, a === c], [64, true, false]);
  assertEquals(await licenceFileSha({}), null);
});

Deno.test('the e-mail door never writes a refused or held file to the licence; WhatsApp tells him the reader\'s sentence', async () => {
  const src = await Deno.readTextFile(new URL('../resend_inbound/steps/supplier_docs.ts', import.meta.url));
  const wrong = src.indexOf('if (ex?.doc?.wrong_document)'), held = src.indexOf('} else if (ex?.doc?.held_for_person)'), write = src.indexOf('license_doc_path: path, license_doc_name: fname');
  assert(wrong > 0 && held > wrong && write > held, 'the licence write is reachable for a refused or held file');
  assert(src.includes("recordWrongDocument(admin, lead.id, 'resend_inbound.supplier_docs', path, ex.doc.wrong_document, lead.license_doc_path ?? null)"));
  const wa = await Deno.readTextFile(new URL('../wa_inbound/media.ts', import.meta.url));
  assert(wa.includes("'kept, not filed as the licence: ' + named"));
});
