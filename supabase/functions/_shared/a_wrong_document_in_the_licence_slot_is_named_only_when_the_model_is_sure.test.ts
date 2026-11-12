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
    assert(/not a trade licence|does not look like a trade licence/.test(w!.message), w!.message);
  }
  assertEquals(wrongDocumentSentence('company_profile'),
    'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below.');
  // nothing of the file is a licence reading, even a company name the model copied against the instruction
  const d = normaliseLicence({ ...PROFILE, legal_name: 'ZZ DEMO MEP Contracting LLC', confidence: 'high' });
  assertEquals([d.unreadable, d.legal_name, d.license_number, d.expiry_date, d.wrong_document?.kind], [true, '', '', null, 'company_profile']);
});

Deno.test('anything less than sure, or any licence field read, is the existing flow: never called the wrong document', () => {
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind_confidence: 'medium' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, document_kind_confidence: 'low' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, license_number: 'ZZ-1234567' }), null);       // a licence number read: there is a licence
  assertEquals(wrongDocumentOf({ ...PROFILE, license_authority: 'Dubai Department of Economy and Tourism' }), null);
  assertEquals(wrongDocumentOf({ ...PROFILE, expiry_date: '2027-10-29' }), null);
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
  assert(SYS_LICENSE.includes('When document_kind is not trade_licence, leave every licence field empty'));
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
    // even a model that wrongly called a licence a company profile, sure: every recorded licence answer that read a number, an authority
    // or an expiry is still not named the wrong document (rule 3)
    const confused = wrongDocumentOf({ ...doc, document_kind: 'company_profile', document_kind_confidence: 'high' });
    if (String(doc.license_number ?? '').trim() || String(doc.license_authority ?? '').trim() || String(doc.expiry_date ?? '').trim()) { assertEquals(confused, null, id); guarded++; }
  }
  console.log(`recorded licence answers replayed: ${recorded.length} from ${runs.length} runs; ${guarded} would be safe even from a confused kind`);
});
