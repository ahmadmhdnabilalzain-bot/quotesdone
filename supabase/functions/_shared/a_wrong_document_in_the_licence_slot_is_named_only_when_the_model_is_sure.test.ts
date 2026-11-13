// A WRONG DOCUMENT IN THE LICENCE SLOT IS NAMED ONLY WHEN THE MODEL IS SURE (12 Nov 2026, sales_engineer; founder ruling 1668: "if
// someone attaches that by mistake, the verifier should be able to understand ... But of course, it has to be accurate when it says
// that. I don't want it to be misjudging actual documents").
//
// MEASURED. The founder attached his company profile as his trade licence on purpose; license_extract read it (24,093 prompt tokens,
// 16.3 s) and the form said only "being read". The model now says what the file is in the same call (SYS_LICENSE document_kind), and
// licence_extract.ts wrongDocumentOf is the one rule for saying "wrong document". Every model answer below is a STAND-IN written as a
// model would plausibly return it (no paid call); the corpus answers are the model's own, RECORDED by the accuracy suite's gateway runs
// (docs/reports/QuotesDone Sandbox Test 2026-10/documents/run-*/model.json), all synthetic ZZ DEMO licences.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { normaliseLicence, SYS_LICENSE, wrongDocumentOf, wrongDocumentSentence } from './licence_extract.ts';

const PROFILE = { legal_name: '', license_number: '', license_authority: '', issue_date: '', expiry_date: '', activities: [], confidence: 'low',
  document_kind: 'company_profile', document_kind_confidence: 'high',
  document_kind_why: 'a company profile: it describes MEP services and projects and carries no licence number, issuing authority or expiry date' };

Deno.test('a file the model is sure is not a licence, with no licence field read, is named by its kind', () => {
  for (const kind of ['company_profile', 'catalogue', 'quotation_or_invoice', 'identity_document', 'certificate', 'other']) {
    const w = wrongDocumentOf({ ...PROFILE, document_kind: kind });
    assert(w, kind);
    assertEquals(w!.kind, kind);
    assert(/not a trade licence|rather than your trade licence|does not look like a trade licence/.test(w!.message), w!.message);
  }
  assertEquals(wrongDocumentSentence('company_profile'),
    'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below. If this is your trade licence, reply to our e-mail or write to management@quotesdone.com and we will check it.');
  // nothing of the file is a licence reading, even a company name the model copied against the instruction
  const d = normaliseLicence({ ...PROFILE, legal_name: 'ZZ DEMO MEP Contracting LLC', confidence: 'high' });
  assertEquals([d.unreadable, d.legal_name, d.license_number, d.expiry_date, d.wrong_document?.kind], [true, '', '', null, 'company_profile']);
});

Deno.test('anything less than sure, or a never-a-licence kind with a licence page read, is never called the wrong document', () => {
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind_confidence: 'medium' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind_confidence: 'low' }), null);
  // ruling 1681 (13 Nov 2026): at 'high' the reader has decided, so a certificate or other is named whatever it read; the one case
  // left for "one of our team will check" (the second read) is a never-a-licence kind with BOTH an authority and an expiry read.
  for (const kind of ['certificate', 'other']) {
    assertEquals(wrongDocumentOf({ ...PROFILE, document_kind: kind, license_authority: 'Dubai Department of Economy and Tourism' })?.kind, kind, kind);
    assertEquals(wrongDocumentOf({ ...PROFILE, document_kind: kind, expiry_date: '2027-10-29' })?.kind, kind, kind);
  }
  assertEquals(wrongDocumentOf({ ...PROFILE, license_authority: 'Dubai Department of Economy and Tourism', expiry_date: '2027-10-29' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind: 'trade_licence' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind: 'unreadable' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind: 'licence' }), null);           // a kind not on the list is not a finding
  const { document_kind: _k, document_kind_confidence: _c, document_kind_why: _w, ...older } = PROFILE;
  assertEquals(wrongDocumentOf(older), null);                                                // an older or fallback model: no field
  assertEquals(wrongDocumentOf(null), null);
  // a company profile with the licence scanned inside it: the model calls it the licence and reads it
  const mixed = normaliseLicence({ legal_name: 'ZZ DEMO MEP Contracting LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism',
    expiry_date: '2027-06-30', issue_date: '2026-07-01', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high',
    document_kind_why: 'a company profile whose page 4 is the trade licence' });
  assertEquals([mixed.unreadable, mixed.license_number, mixed.expiry_date, mixed.wrong_document], [false, 'ZZ-555001', '2027-06-30', null]);
});

Deno.test('the prompt asks for the kind in the same call, calls every form of a UAE licence a licence, and keeps a wrong file empty', () => {
  assert(SYS_LICENSE.includes('"document_kind":"trade_licence"|"company_profile"'));
  for (const form of ['free zone', 'e-trader', 'Commercial Register certificate page', 'Arabic-only licence', 'photo of a framed licence', 'renewal receipt', 'inside a larger file'])
    assert(SYS_LICENSE.includes(form), form);
  // review of #1985 (D1): the model never empties a printed field because of its own doubt, so condition 3 stays independent evidence
  assert(SYS_LICENSE.includes('Always fill the licence fields with exactly what the file prints, whatever document_kind is: never leave a printed licence number, issuing authority or expiry date out because you think the file is not a licence.'));
  assert(!SYS_LICENSE.includes('leave every licence field empty'));
  assert(SYS_LICENSE.includes('free-zone Certificate of Incorporation'), 'a free-zone certificate of incorporation is part of the licence papers');
});

// Every RECORDED gateway answer the accuracy suite keeps for the licence corpus (synthetic licences, every authority and format).
const runs = [...Deno.readDirSync(new URL('../../../docs/reports/QuotesDone Sandbox Test 2026-10/documents/', import.meta.url))]
  .filter((e) => e.isDirectory && e.name.startsWith('run-'))
  .map((e) => new URL(`../../../docs/reports/QuotesDone Sandbox Test 2026-10/documents/${e.name}/model.json`, import.meta.url))
  .filter((u) => { try { Deno.statSync(u); return true; } catch { return false; } });
const recorded = runs.flatMap((u) => (JSON.parse(Deno.readTextFileSync(u)).docs as { id: string; asked?: boolean; doc?: Record<string, unknown> }[])
  .filter((d) => d.asked && d.doc).map((d) => ({ id: d.id, doc: d.doc! })));

Deno.test('no recorded licence is ever named the wrong document: without the field it reads as today, with it as a licence', () => {
  assert(recorded.length >= 100, `recorded answers: ${recorded.length}`);
  const strip = (x: Record<string, unknown>) => { const { wrong_document: _w, ...rest } = x; return rest; };
  let guarded = 0;
  for (const { id, doc } of recorded) {
    const today = normaliseLicence(doc);
    assertEquals(today.wrong_document, null, id);
    // the same answer from a model that now also says what the document is
    const withKind = normaliseLicence({ ...doc, document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'a UAE trade licence' });
    assertEquals(strip(withKind), strip(today), id);
    // even a model that wrongly called a licence a company profile, sure: every recorded licence answer that read an authority
    // or an expiry is still not named the wrong document (rule 3: both read for a never-a-licence kind; review of #1992)
    const confused = wrongDocumentOf({ ...doc, document_kind: 'company_profile', document_kind_confidence: 'high' });
    if (String(doc.license_authority ?? '').trim() || String(doc.expiry_date ?? '').trim()) { assertEquals(confused, null, id); guarded++; }
  }
  console.log(`recorded licence answers replayed: ${recorded.length} from ${runs.length} runs; ${guarded} would be safe even from a confused kind`);
});

// Review of #1985 (D1): the cases the reviewer asked for.
Deno.test('a file called other or certificate, sure, is named with a way to a person; a profile footer with a number is named; a free-zone certificate is a licence paper', () => {
  // a file the model calls "other", sure, with a number and authority read: since ruling 1681 the reader has decided and it is named
  // (nothing stored), and the sentence tells him how to reach a person if it IS his licence (the second identical refusal opens a task).
  const doubted = normaliseLicence({ legal_name: 'ZZ DEMO Oryx Trading FZE', license_number: 'ZZ-88001', license_authority: 'ZZ Free Zone Authority', expiry_date: '2027-05-01',
    issue_date: '2026-05-02', confidence: 'medium', document_kind: 'other', document_kind_confidence: 'high', document_kind_why: 'an unusual layout' });
  assertEquals([doubted.wrong_document?.kind, doubted.held_for_person, doubted.license_number], ['other', null, '']);
  assert(doubted.wrong_document!.message.endsWith('write to management@quotesdone.com and we will check it.'));
  // a company profile whose footer prints the licence number, sure, no authority, no expiry: named, and nothing of it is kept
  const footer = normaliseLicence({ ...PROFILE, license_number: 'ZZ-88001', legal_name: 'ZZ DEMO Oryx Trading FZE' });
  assertEquals([footer.wrong_document?.kind, footer.license_number, footer.legal_name], ['company_profile', '', '']);
  // a free-zone Certificate of Incorporation alone: the prompt calls it trade_licence (SYS_LICENSE), so it is read; a model that called it
  // a certificate at 'medium' sends it to the second read, never to a refusal
  const coi = { legal_name: 'ZZ DEMO Oryx Trading FZE', license_number: 'ZZ-COI-501', license_authority: 'ZZ Free Zone Authority', expiry_date: '', confidence: 'medium' };
  assertEquals(wrongDocumentOf({ ...coi, document_kind: 'trade_licence', document_kind_confidence: 'high' }), null);
  assertEquals(wrongDocumentOf({ ...coi, document_kind: 'certificate', document_kind_confidence: 'medium' }), null);
  assertEquals(wrongDocumentSentence('certificate'), 'This looks like a certificate (such as a chamber of commerce membership, ISO, insurance or VAT registration certificate) rather than your trade licence. Please attach your trade licence here. If this is your trade licence, reply to our e-mail or write to management@quotesdone.com and we will check it.');
});

// Second review of #1985, W1: a file the model calls something else but reads licence-like fields from is held for a person.
// Since ruling 1681 (13 Nov 2026) the chamber certificate the model is SURE of is named; at 'medium' it is held for the second read.
Deno.test('a chamber certificate with licence-like fields is never stored: named when the reader is sure, held for the second read when not', async () => {
  const { licenceJudgementOf, HELD_FOR_PERSON_SENTENCE } = await import('./licence_extract.ts');
  const CHAMBER = { legal_name: 'ZZ DEMO Chamber Member Trading LLC', license_number: 'ZZ-777001', license_authority: 'Dubai Chamber of Commerce and Industry',
    expiry_date: '2027-12-31', issue_date: '2026-01-01', confidence: 'high', document_kind: 'certificate', document_kind_confidence: 'high',
    document_kind_why: 'a chamber of commerce membership certificate' };
  const sure = normaliseLicence(CHAMBER);
  assertEquals([sure.unreadable, sure.license_number, sure.license_authority, sure.expiry_date, sure.legal_name, sure.wrong_document?.kind, sure.held_for_person], [true, '', '', null, '', 'certificate', null]);
  {
    const conf = 'medium';
    const j = licenceJudgementOf({ ...CHAMBER, document_kind_confidence: conf });
    assertEquals(j.outcome, 'held_for_person', conf);
    const d = normaliseLicence({ ...CHAMBER, document_kind_confidence: conf });
    assertEquals([d.unreadable, d.license_number, d.license_authority, d.expiry_date, d.legal_name, d.wrong_document], [true, '', '', null, '', null], conf);
    assertEquals(d.held_for_person?.message, HELD_FOR_PERSON_SENTENCE);
    assertEquals(d.held_for_person?.read.license_authority, 'Dubai Chamber of Commerce and Industry');   // kept for the person, not the row
  }
  // a real licence the model calls a certificate at 'medium', fields read: the same path (a person's look; never refused, never approved by code)
  assertEquals(licenceJudgementOf({ ...CHAMBER, license_authority: 'Dubai Department of Economy and Tourism', document_kind_confidence: 'medium' }).outcome, 'held_for_person');
  // a real licence called trade_licence: read; an older model with no kind, or a 'low' doubt: today's flow
  assertEquals(licenceJudgementOf({ ...CHAMBER, document_kind: 'trade_licence' }).outcome, 'licence');
  const { document_kind: _k, document_kind_confidence: _c, document_kind_why: _w, ...older } = CHAMBER;
  assertEquals(licenceJudgementOf(older).outcome, 'licence');
  assertEquals(normaliseLicence(older).license_number, 'ZZ-777001');
  assertEquals(licenceJudgementOf({ ...CHAMBER, document_kind_confidence: 'low' }).outcome, 'licence');
  // a sure non-licence with no authority and no expiry is still the wrong-document sentence (ii)
  assertEquals(licenceJudgementOf({ ...CHAMBER, license_authority: '', expiry_date: '' }).outcome, 'wrong_document');
});

// Third review of #1985, F3: the kind and the doubt are read in their normal form; anything still unknown keeps the safe default.
Deno.test('the kind and the doubt are read whatever their case or spelling; a malformed answer is never a refusal', async () => {
  const { licenceJudgementOf } = await import('./licence_extract.ts');
  const CH = { legal_name: 'ZZ DEMO X LLC', license_number: 'ZZ-1', license_authority: 'Dubai Chamber of Commerce and Industry', expiry_date: '2027-12-31', confidence: 'high' };
  const rows: [Record<string, unknown>, string][] = [
    [{ ...CH, document_kind: 'certificate', document_kind_confidence: 'High' }, 'wrong_document'],
    [{ ...CH, document_kind: ' Certificate ', document_kind_confidence: 'high' }, 'wrong_document'],
    [{ ...CH, document_kind: 'CERTIFICATE', document_kind_confidence: ' MEDIUM ' }, 'held_for_person'],
    [{ ...PROFILE, document_kind: 'Company Profile', document_kind_confidence: 'HIGH' }, 'wrong_document'],
    [{ ...PROFILE, document_kind: 'company-profile', document_kind_confidence: 'high' }, 'wrong_document'],
    [{ ...CH, document_kind: 'Trade Licence', document_kind_confidence: 'high' }, 'licence'],
    [{ ...CH, document_kind: 'trade_license', document_kind_confidence: 'high' }, 'licence'],
    [{ ...CH, document_kind: 'Commercial License', document_kind_confidence: 'high' }, 'licence'],
    [{ ...CH }, 'licence'],                                                            // no field: an older model
    [{ ...CH, document_kind: null, document_kind_confidence: null }, 'licence'],
    [{ ...CH, document_kind: 'certificate', document_kind_confidence: null }, 'licence'],
    [{ ...CH, document_kind: 'membership_card', document_kind_confidence: 'high' }, 'licence'],   // an unknown word
    [{ ...CH, document_kind: ['certificate'], document_kind_confidence: 'high' }, 'wrong_document'],   // an array reads as its text, as before
  ];
  for (const [ai, want] of rows) assertEquals(licenceJudgementOf(ai).outcome, want, JSON.stringify([ai.document_kind, ai.document_kind_confidence]));
});

// 13 Nov 2026, the first paid J11 on the live site (founder ruling 1668: "definitely a company profile is not a trade license ... he
// should be able to judge, oh, listen, this is the wrong document ... But of course, it has to be accurate when it says that"). The
// ZZ DEMO MEP company profile (scripts/e2e/fixtures/registration/P1_mep_contractor.pdf) came back from the model, in one tagged paid call:
// company_profile, 'high', "A company profile describing MEP services and projects; it mentions a licence number but contains no licence
// page or expiry date", with license_number, license_authority and legal_name filled. The old rule held it for a person.
Deno.test('a sure company profile, catalogue, quotation or ID is named unless it reads both an authority and an expiry; a sure certificate or other is named', async () => {
  const { licenceJudgementOf, NEVER_A_LICENCE_KINDS } = await import('./licence_extract.ts');
  assertEquals([...NEVER_A_LICENCE_KINDS], ['company_profile', 'catalogue', 'quotation_or_invoice', 'identity_document']);
  const QUOTES = { legal_name: 'ZZ DEMO MEP Contracting LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism',
    expiry_date: '2027-06-30', issue_date: '2026-07-01', confidence: 'high', document_kind_why: 'a company profile that quotes its licence details' };
  const rows: [string, Record<string, unknown>, string][] = [
    ['real licence', { ...QUOTES, document_kind: 'trade_licence', document_kind_confidence: 'high' }, 'licence'],
    ['P1 as measured', { ...QUOTES, expiry_date: '', issue_date: '', document_kind: 'company_profile', document_kind_confidence: 'high' }, 'wrong_document'],
    ['profile, number+authority, no expiry (measured)', { ...QUOTES, expiry_date: '', document_kind: 'company_profile', document_kind_confidence: 'high' }, 'wrong_document'],
    ['profile, number+authority+expiry', { ...QUOTES, document_kind: 'company_profile', document_kind_confidence: 'high' }, 'held_for_person'],
    ['catalogue, all read', { ...QUOTES, document_kind: 'catalogue', document_kind_confidence: 'high' }, 'held_for_person'],
    ['quotation, all read', { ...QUOTES, document_kind: 'quotation_or_invoice', document_kind_confidence: 'high' }, 'held_for_person'],
    ['identity document, expiry read, no authority', { ...QUOTES, license_authority: '', document_kind: 'identity_document', document_kind_confidence: 'high' }, 'wrong_document'],
    ['identity document in front of a licence page, authority+expiry read', { ...QUOTES, document_kind: 'identity_document', document_kind_confidence: 'high' }, 'held_for_person'],
    ['certificate, authority read (ruling 1681: named)', { ...QUOTES, expiry_date: '', document_kind: 'certificate', document_kind_confidence: 'high' }, 'wrong_document'],
    ['other, expiry read (ruling 1681: named)', { ...QUOTES, license_authority: '', document_kind: 'other', document_kind_confidence: 'high' }, 'wrong_document'],
    ['profile at medium', { ...QUOTES, document_kind: 'company_profile', document_kind_confidence: 'medium' }, 'held_for_person'],
    ['catalogue at medium, nothing read', { ...PROFILE, document_kind: 'catalogue', document_kind_confidence: 'medium' }, 'held_for_person'],
    ['other, nothing read', { ...PROFILE, document_kind: 'other', document_kind_confidence: 'high' }, 'wrong_document'],
    ['profile at low', { ...QUOTES, document_kind: 'company_profile', document_kind_confidence: 'low' }, 'licence'],
  ];
  for (const [name, ai, want] of rows) assertEquals(licenceJudgementOf(ai).outcome, want, name);
  // nothing of a named profile is a licence reading: no number, authority or name reaches the row
  const d = normaliseLicence({ ...QUOTES, expiry_date: '', document_kind: 'company_profile', document_kind_confidence: 'high' });
  assertEquals([d.unreadable, d.license_number, d.license_authority, d.expiry_date, d.legal_name, d.held_for_person, d.wrong_document?.kind],
    [true, '', '', null, '', null, 'company_profile']);
  assertEquals(d.wrong_document?.message, wrongDocumentSentence('company_profile'));
  // with an authority and an expiry both read it may be a licence page: held, and still nothing of it reaches the row
  const h = normaliseLicence({ ...QUOTES, document_kind: 'company_profile', document_kind_confidence: 'high' });
  assertEquals([h.unreadable, h.license_number, h.license_authority, h.expiry_date, h.wrong_document, h.held_for_person?.kind], [true, '', '', null, null, 'company_profile']);
});

// The model's own answer for P1 in the paid confirmation run of 13 Nov 2026 (run d29f5749; the fixture is synthetic ZZ DEMO), recorded
// as returned: company_profile, 'high', number + authority + name read, no expiry. The narrowed rule (review of #1992) still names it.
Deno.test('the recorded answer for the P1 company profile is named the wrong document by the rule as it stands', async () => {
  const { licenceJudgementOf } = await import('./licence_extract.ts');
  const P1 = { legal_name: 'ZZ DEMO Saker Electromechanical Contracting LLC', license_number: 'ZZ-1290417', license_authority: 'Dubai Department of Economy and Tourism',
    expiry_date: '', issue_date: '', confidence: 'low', emirate: 'Dubai', trn: '', document_kind: 'company_profile', document_kind_confidence: 'high',
    document_kind_why: 'This is a company profile describing services and projects; it mentions a licence but contains no licence document or expiry date.' };
  const j = licenceJudgementOf(P1);
  assertEquals(j.outcome, 'wrong_document');
  assertEquals(j.outcome === 'wrong_document' ? j.wrong.message : '', wrongDocumentSentence('company_profile'));
});
