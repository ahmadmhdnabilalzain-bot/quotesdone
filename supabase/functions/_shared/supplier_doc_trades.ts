// A SUPPLIER'S OWN DOCUMENTS, READ BY CODE, TURNED INTO A TRADE PROPOSAL THE SUPPLIER CONFIRMS.
//
// Founder: "The sales engineer must actually read company profiles and catalogues" — extract the
// trades the supplier provides, then CONFIRM them with the supplier during registration.
//
// MEASURED 15 Sep 2026, before this file. Every read of a supplier's licence, profile or catalogue
// went through a model: supplier_api.process_docs sent profile images to license_extract mode
// 'profile', and supplier_catalog_ingest sent PDFs and images to ai_gateway. Every model route is on
// hold, so nothing was read. supplier_capabilities held 15,306 rows: 15,305 derived from the
// directory listing ('derived_from_directory_v1'), 2 confirmed, and source_docs = {} on every one.
// The deterministic readers in _shared/doc_read (PDF text layer, Office, zip, CAD, text) were used
// for customer RFQs and BOQs only.
//
// WHAT THIS DOES. Each uploaded document goes through readDocument (the same gate and readers the
// RFQ side uses, words only), and what its text names is stored as a PROPOSAL:
//   supplier_capabilities.proposed_trades   the codes the documents name
//   supplier_capabilities.source_docs.docs  per file: status, how each path fared (exact, meaning), and per
//                                           trade how it was named and the line it was found on (the evidence)
// It never touches supplier_capabilities.trades or confirmed_at. The supplier sees the proposal in
// "What your company can quote for", ticks or unticks it, and only the confirm writes trades.
//
// THE MODEL READS, CODE CHECKS (11 Nov 2026, customer_support; founder ruling 1627). "It's not word matching only ... when a human
// reads that, he will understand what services they will do ... So it has to be read." Until today a document's trades were
// proposed by code (an exact code, a licence activity's subject, gte-small meaning with one head word) and its services by code
// too (profile_services.servicesOfText), and the paid certification of 11 Nov showed the result (Recording studio equipment for an
// MEP contractor, from "our own team and equipment"). Now:
//   * each document is READ by code into text (readDocForTrades with textOnly: the PDF's words, a catalogue's headings and
//     statements, the vision model's transcription of a picture) and that text is kept beside the file (saveText);
//   * ALL the supplier's documents are then given to the model together (readTogether): profile, catalogues, licence and anything
//     else, each under its own header, with our catalogue of trades and their service keys. It names the trades and the services
//     the company does, each with the line it understood it from, and judges each service against the licence's activities. The
//     licence is one input: a service is never taken from the licence (a licence does not say what a supplier will do);
//   * code only CHECKS (supplier_profile_reading.checkReading, applyMapping): every key is in the catalogue, every quote is in the documents, and a
//     service's quote is in a document that is not the licence. A proposal that fails a check is dropped, never repaired;
//   * no model (an outage): nothing is proposed and nothing is guessed. The documents say they are still being read, the trade he
//     chose at sign-up stays on his checklist (supplier_services.preparedTrades), and the sweep reads them again (stuckOf).
// A scan or photo with no text is recorded 'needs_ocr', never "no trades found".
import { readDocument, type DocumentRead } from './doc_read/index.ts';
import { type Extracted, LIMITS } from './doc_read/types.ts';
import { pagesLeft } from './doc_read/pdf.ts';
import { catalogueLines, supplyOnlyOf } from './catalogue_read.ts';
import { licenceFieldsFromText } from './document_expiry.ts';
import { liveTradeDeps, type TradeHit, type TradeResolveDeps } from './trade_resolve.ts';
import type { LicenceCheck, LicenceStatus, ProposedService, ServiceHit } from './profile_services.ts';
import { PROFILE_READER, proposalOf, type ProfileReading, type Proposal, type TwoStepTimes } from './supplier_profile_reading.ts';

export type { TradeHit, TradeResolveDeps };

// deno-lint-ignore no-explicit-any
type Admin = any;
// @4: the model reads all the documents together (ruling 1627). @5 (12 Nov 2026, ruling 1647): it reads them first and maps them second
// (supplier_profile_reading.ts), every claim with its sentence and basis, and source_docs.reading holds the reading and its proposal.
export const READER = PROFILE_READER;
const MAX_DOCS = 40;

export type DocKind = 'licence' | 'profile' | 'catalogue';
// `photo_text` is the text the supplier's own browser recognised in a photo or a scanned page
// (tesseract.js, the same self-hosted OCR the customer side uses). It is untrusted words like any other
// upload, read through the same path, and the evidence says it came from a photo.
// `ocr_text` (19 Oct 2026) is a scan's or photo's words read by CODE (tesseract.js OCR, in the supplier's browser as the
// catalogue upload already does, or scripts/e2e/scan_ocr.mjs in the harness). Unlike photo_text, which the vision model
// transcribed, these are code's reading of the file, so a quote checked against them is checked against the file: its
// trades are proposed like a text layer's (N07, N09, H01 were held, every core trade "missed").
export type DocIn = { path: string; name: string; kind: DocKind; bytes?: Uint8Array; mime?: string; read?: DocumentRead; photo_text?: string; ocr_text?: string;
  /** names the company is known by (registered, licence legal name read by code or model): never read as a trade */
  names?: (string | null)[];
  /** set by supplier_docs_later.gateStored when the stored bytes failed the type / malware gate: recorded, never read */
  refused?: string;
  /** set by supplier_docs_later.readProfileByModel when it did not send the file to the model (too big, too many pages): the reason, worded for the supplier */
  unread_reason?: string;
  /** set by supplier_docs_later.readProfileByModel when it sent the model only the first pages of a scan */
  pages_read?: { read: number; of: number };
  /** A CONTINUATION (supplier_docs_later.stuckOf): read from this page on, and add to `prev`, the evidence of the pages read before */
  from_page?: number; prev?: DocEvidence;
  /** a continuation: the text read off its earlier pages (its sidecar, loadText), read before the new pages */
  prev_text?: string;
  /** how many times the sweep has read this document again because the model could not be asked (stuckOf) */
  rereads?: number };
export type DocEvidence = {
  path: string; name: string; kind: DocKind;
  /** 'reading': marked BEFORE the parse (markReading); if the worker is killed mid-parse it stays, and it proposes nothing.
   *  'refused': a file uploaded straight to storage failed the type / malware gate; it was removed and never read. */
  status: 'read' | 'needs_ocr' | 'needs_cad_conversion' | 'unreadable' | 'reading' | 'refused';
  /** a 'reading' mark set by the sweep's one re-read (supplier_docs_later.rereadStuck); a second stall is escalated */
  retry?: boolean;
  reason?: string; format?: string; trades: TradeHit[]; read_at: string;
  source?: 'document_text' | 'photo_text' | 'ocr_text'; supply_only?: boolean;
  /** records written by readers @3 and before (code's exact and meaning paths, deleted 11 Nov 2026) */
  exact?: string; meaning?: string;
  /** the text code read off the document (before preparedText), given to the model with the others; kept beside the file (saveText), never stored here */
  text?: string;
  /** the model could not be asked (choice 'unavailable'): how many times the sweep has read it again since */
  rereads?: number;
  /** a continuation that read nothing new: what was read stands, and the model is not asked again (never stored) */
  unchanged?: boolean;
  /** profile / catalogue: 'on' = the model chose the trades and each was proven by its quote; 'unavailable' = it could not
   *  be asked, so NOTHING was proposed (reason says why); rejected = codes the model named that code refused */
  choice?: 'on' | 'unavailable' | 'held'; rejected?: { code: string; why: string }[];
  /** LEGACY choice 'held' (reader @4, before 12 Nov 2026): the readings did not agree on any trade. Reader @5 never holds. */
  held_readings?: { code: string; quote: string }[][];
  /** LEGACY (records written before 2 Nov 2026): trades read off a PICTURE were held here for the sales engineer. Since ledger 1442 they are
   *  proposed in `trades` like any other and the supplier confirms them on the Services tab; nothing writes this field any more. */
  vision_held?: TradeHit[];
  /** A PARTIAL read (3 Nov 2026): only `read` of the file's `of` pages were read (the text read's budget, or a scan cut for the model).
   *  The proposal stands for the supplier to confirm, and this says it came from part of the document only. */
  pages?: { read: number; of: number };
  /** the read stopped at its budget or text cap and the rest is read by the next sweep run, from pages.read + 1 (stuckOf) */
  resume?: boolean;
  /** a profile or catalogue: the SERVICES it states, each with the supplier's own words (profile_services.ts, 10 Nov 2026,
   *  ledger 1573). Proposed to the supplier on the Services tab; his tick is what makes one his. */
  services?: ServiceHit[];
  /** a licence: its activities exactly as printed, the licence side of the licence-vs-profile check */
  activities?: string[];
};
export const PHOTO_TEXT_MAX = 60_000;

// WHAT THE VISION MODEL READ OFF A PICTURE IS READ FOR TRADES LIKE TEXT (ruling 1177, 12 Oct 2026). A licence or
// profile with no text layer has its activities / services read by license_extract; they become the document's
// photo_text, so they go through the same exact-code and meaning rules (Arabic exact names #1312, the licence's
// activities line only #1313). One spelling for every upload path: supplier_api, supplier_portal and the suite.
export function modelReadText(kind: DocKind, items: unknown): string | undefined {
  const a = (Array.isArray(items) ? items : []).map((x) => String(x ?? '').trim()).filter(Boolean);
  if (!a.length) return undefined;
  return kind === 'licence' ? 'Activities: ' + a.join(', ') : a.join('\n');
}

/** Every word a read document holds: its text, its table cells, and its zip / email children. */
export function allText(e: Extracted, depth = 0): string {
  const cells = e.tables.flatMap((t) => t.map((row) => row.filter((c) => c != null && c !== '').join(' ')));
  const kids = depth < 3 ? e.children.map((c) => allText(c.doc, depth + 1)) : [];
  return [e.text, ...cells, ...kids].filter(Boolean).join('\n');
}

// A CATALOGUE IS READ AS A CATALOGUE (21 Sep 2026, _shared/catalogue_read.ts). Its spec tables and address
// block are set aside first ("DVR Storage Upto 6TB" is a product property, "PREVIEW GENERAL TRADING LLC
// (Warehouse)" is an address), and a company that only trades in goods is read as supply-only, so meaning does
// not propose it installation work. What is left — headings, product types and its sentences — is what is read.
function catalogueText(text: string): { text: string; supply_only: boolean } {
  const L = catalogueLines(text);
  return { text: [...L.headings, ...L.types, ...L.statements].join('\n'), supply_only: supplyOnlyOf([...L.headings, ...L.statements].join('\n')).supply_only };
}

// A CERTIFICATE THE COMPANY HOLDS IS NOT A SERVICE IT SELLS (7 Oct 2026, accuracy suite ledger 1162). "ISO
// 9001:2015 quality management" on a contractor's profile proposed the trade iso_certification on every profile of
// the corpus (meaning: "iso 9001", head word present). A line that cites a dated standard is a credential unless it
// offers certification, auditing, consultancy or training AS a service. The section heading over such lines
// ("Certifications", "Our Certificates", "Accreditations") is the same credential: it proposed corporate_training
// ("IT & professional certification") on every profile of the corpus.
const CREDENTIAL_HEADING = /^\s*[-•*]?\s*(our\s+)?(certifications?|certificates?|accreditations?|approvals?\s+and\s+certifications?)\s*:?\s*$/i;
export function withoutCredentialLines(text: string): string {
  return String(text ?? '').split(/\r?\n/).filter((l) => !CREDENTIAL_HEADING.test(l) && !(/\bISO\s*\d{3,5}(?:-\d+)?\s*:\s*\d{4}\b/i.test(l)
    && !/\b(certification|audit(?:ing)?|consultan(?:cy|ts?)|training|implementation)\s+(services?|body|bodies)\b|\bwe\s+(certify|audit|train)\b/i.test(l))).join('\n');
}

// WHAT A REAL PROFILE SAYS IT DOES (13 Oct 2026, it_engineer; ACCURACY_real_profiles.md). The synthetic profiles of the
// suite were a page each; a real UAE company profile is 10-180 pages of which a few lines say what the company does,
// and the rest is the CEO's message, policies, the organisation chart, staff and machinery lists, certificates,
// client and project lists. Measured on 29 real profiles and catalogues, reading every line: 131 trades proposed that
// the company does not do (meaning: "Management 1" on an org chart -> accounting, "SECTION 13: INSURANCE DETAILS" ->
// insurance brokerage, "Full range of equipment" -> commercial kitchens), and meaning's 40-clause budget was spent on
// whichever lines came first. So a long profile is read where it states its offer, by the document's STRUCTURE, never
// by which trade a word names:
//   * the lines under an offer heading ("Our Services", "Specialised in", "Scope of Work", "Products", "Activities" ...)
//     up to OFFER_WINDOW lines on;
//   * a sentence that states the offer ("specialises in", "services include", "we offer / provide / undertake / supply /
//     install / manufacture", "principal activity", "engaged in", "is a ... contractor") from that phrase on, and the
//     OFFER_TAIL lines that continue it (a PDF breaks a sentence across lines).
// Which trade those lines name is still decided only by exact code and meaning (trade_resolve.tradesOfText).
// A document of SHORT_DOC_LINES lines or fewer, or one that states no offer in these forms, is read whole, as before.
// ARABIC TOO (review of #1404): the same headings and offer sentences in Arabic (خدماتنا، نطاق العمل، منتجاتنا، متخصصة في،
// نقدم ...). Measured on the BCG Arabic brochure (69 pages) in ACCURACY_real_profiles.md.
export const SHORT_DOC_LINES = 60, OFFER_WINDOW = 25, OFFER_TAIL = 3;
const OFFER_HEAD = /^\s*(?:\d{1,2}[.)]?\s*)?(?:our\s+|core\s+|main\s+|key\s+|list\s+of\s+)*(?:services?|products?(?:\s+range)?|product\s+range|scope(?:\s+of\s+(?:work|works|services|supply))?|activities|speciali[sz](?:ed\s+in|ations?)|expertise|what\s+we\s+do|capabilities|disciplines|divisions)\s*:?\s*$/i;
const OFFER_FRAME = /\b(?:speciali[sz](?:e|es|ed|ing)\s+in|services?\s+(?:include|including|such\s+as|offered)|we\s+(?:offer|provide|undertake|supply|install|manufacture|take\s+up|carry\s+out|deal\s+in)|scope\s+of\s+works?\s*(?:includes?|:)|activities\s*:|principal\s+activit(?:y|ies)|engaged\s+in|deal(?:s|ing)?\s+(?:with|in)|(?:is|are)\s+(?:a|an|the)\s+(?:[\w&/-]+\s+){0,6}?(?:company|contractors?|manufacturers?|suppliers?|providers?|specialists?|firm))\b/i;
const OFFER_HEAD_AR = /^\s*(?:\d{1,2}[.)]?\s*)?(?:خدماتنا|الخدمات|خدمات الشركة|نطاق العمل|نطاق الأعمال|نطاق أعمالنا|منتجاتنا|المنتجات|الأنشطة|أنشطة الشركة|أنشطتنا|مجالات العمل|مجالات عملنا|تخصصاتنا|قدراتنا|خبراتنا|أقسام الشركة)\s*[:：]?\s*$/u;
const OFFER_FRAME_AR = /(?:متخصص(?:ة|ون|ين)?\s+في|تتخصص\s+في|نتخصص\s+في|نقدم|نوفر|تقدم\s+الشركة|توفر\s+الشركة|تشمل\s+خدمات|خدماتنا\s+تشمل|نشاط\s+الشركة|تعمل\s+(?:الشركة\s+)?في\s+مجال)/u;
export function offerText(text: string): string | null {
  const lines = String(text ?? '').split(/\r?\n/);
  if (lines.filter((l) => l.trim()).length <= SHORT_DOC_LINES) return null;
  const keep = new Set<number>();
  lines.forEach((l, i) => {
    if (OFFER_HEAD.test(l) || OFFER_HEAD_AR.test(l)) for (let k = i + 1; k <= i + OFFER_WINDOW && k < lines.length; k++) keep.add(k);
    const m = OFFER_FRAME.exec(l) ?? OFFER_FRAME_AR.exec(l);
    if (m) { lines[i] = l.slice(m.index); for (let k = i; k <= i + OFFER_TAIL && k < lines.length; k++) keep.add(k); }
  });
  const out = [...keep].sort((a, b) => a - b).map((i) => lines[i]).filter((l) => l.trim());
  return out.length ? out.join('\n') : null;
}

/** What code read off one document, as the model is given it: a licence by its activities only (the line that says what it
 *  permits; its name lines are never a trade), a catalogue by its headings, product types and sentences (catalogue_read), a
 *  profile with its certificates set aside and the lines where it states its offer brought first (offerText). */
export function preparedText(kind: DocKind, text: string): { text: string; supply_only?: boolean } {
  if (kind === 'licence') {
    const acts = licenceFieldsFromText(text).activities ?? [];
    return { text: acts.length ? 'Activities: ' + acts.join('; ') : '' };
  }
  if (kind === 'catalogue') return catalogueText(withoutCredentialLines(text));
  const whole = withoutCredentialLines(text), offer = offerText(whole);
  return { text: offer ? `${offer}\n\n--- the rest of the document ---\n${whole}` : whole };
}

// THE SIDECAR (11 Nov 2026). The model reads every document of the supplier together, so when he uploads his profile a week
// after his licence, the licence's text is needed again. Parsing a 300-page PDF twice costs the worker's CPU budget, so the
// text code read is kept beside the file, as supplier_catalog_ingest keeps <path>.ocr.txt: <path>.read.txt in supplier-docs.
// The demo fixtures' teardown sweeps both (scripts/lib/demo_factory.mjs, the supplier-docs rule).
export const textPathOf = (path: string) => `${path}.read.txt`;
export async function saveText(admin: Admin, d: DocEvidence): Promise<void> {
  if (!d.text?.trim()) return;
  try {
    const { error } = await admin.storage.from('supplier-docs').upload(textPathOf(d.path), new TextEncoder().encode(d.text), { contentType: 'text/plain', upsert: true });
    if (error) console.error(JSON.stringify({ at: 'supplier_doc_trades.saveText', path: d.path, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: 'supplier_doc_trades.saveText', path: d.path, error: String((e as Error)?.message || e).slice(0, 200) })); }
}
export async function loadText(admin: Admin, d: DocEvidence): Promise<string | null> {
  try {
    const { data } = await admin.storage.from('supplier-docs').download(textPathOf(d.path));
    return data ? await data.text() : null;
  } catch { return null; }
}

/** The model's reading of all the supplier's documents, checked by code and laid out per document. */
/** `profile` (reader @5): the two-step reading and what code proposes from it, stored as source_docs.reading. */
export type StoredReading = { reader: string; read_at: string; times: TwoStepTimes } & ProfileReading & Proposal;
export type Reading =
  | { ok: true; trades: (TradeHit & { doc: string })[]; services: (ProposedService & { path: string })[]; rejected: { code: string; why: string }[]; profile?: StoredReading }
  | { ok: false; why: 'no_documents' | 'unavailable'; error: string };
const KIND_ORDER: Record<DocKind, number> = { profile: 0, catalogue: 1, licence: 2 };

/**
 * ALL THE SUPPLIER'S DOCUMENTS, READ TOGETHER BY THE MODEL (ruling 1627). Each document read by code is given under its own
 * header, profile and catalogues first and the licence last. The model names the trades and the services the company does,
 * each with a line it quoted; code then CHECKS only (supplier_profile_reading.checkReading: the key is ours, the quote is in the
 * documents) and here finds which document each quote is in. A trade or service quoted only from the licence is dropped: a
 * licence says what the company is permitted to do, not what it does ("General Trading" over an MEP contractor's profile).
 * A licence alone is not given to the model at all.
 */
export async function readTogether(docs: DocEvidence[], deps: TradeResolveDeps, company: string | null): Promise<Reading> {
  // what the model is given and what a quote is looked for in: each document's text as preparedText lays it out
  const usable = docs.filter((d) => d.status === 'read' && d.text?.trim()).map((d) => ({ ...d, text: preparedText(d.kind, d.text!).text }))
    .filter((d) => d.text.trim()).sort((a, b) => KIND_ORDER[a.kind] - KIND_ORDER[b.kind]);
  if (!usable.some((d) => d.kind !== 'licence')) return { ok: false, why: 'no_documents', error: 'a licence says what the company may do, not what it does: the trades and services are read from its profile or catalogue' };
  if (!deps.readProfile) return { ok: false, why: 'unavailable', error: 'no reader model' };
  return await readInTwoSteps(usable, deps, company);
}

/**
 * READ FIRST, MAPPED SECOND (reader @5, 12 Nov 2026, ruling 1647; supplier_profile_reading.ts). The reading's checked claims become the
 * proposal by code (proposalOf): the stated, verified, mapped services are the services he is shown to tick (never ticked for him), a
 * partner service is shown with its sentence and marked 'partner', a phrase with no key is kept in his words, and the questions are
 * drafted. A reading that names nothing is never 'held': it is the question "what does your company do".
 */
async function readInTwoSteps(usable: DocEvidence[], deps: TradeResolveDeps, company: string | null): Promise<Reading> {
  const docs = usable.map((d) => ({ path: d.path, name: d.name, kind: d.kind, text: d.text! }));
  const r = await deps.readProfile!(docs, company);
  if (!r.ok) {
    console.error(JSON.stringify({ at: 'supplier_doc_trades.readTogether', reader: READER, docs: usable.map((d) => d.path), error: r.error }));
    return { ok: false, why: 'unavailable', error: r.error };
  }
  const licence = usable.find((d) => d.kind === 'licence');
  const p = proposalOf(r.reading, r.taxonomy, r.implications, { licenceActivities: licence?.activities ?? [] });
  const nameOf = new Map(usable.map((d) => [d.path, d.name]));
  // the licence's fit is the reading's, for the whole profile (the per-service judgement of @4 is not asked any more)
  const lic: LicenceStatus = !licence ? 'unclear' : r.reading.licence.covers_profile === 'yes' ? 'supported' : r.reading.licence.covers_profile === 'no' ? 'not_covered' : 'unclear';
  const services: (ProposedService & { path: string })[] = [
    ...p.tick.map((x) => ({ key: x.key, trade: x.trade, label_en: x.label_en, via: 'model' as const, phrase: x.quote, snippet: x.quote, doc: nameOf.get(x.doc) ?? x.doc, path: x.doc, licence: lic, delivery: 'own' as const })),
    ...p.partner.map((x) => ({ key: x.key, trade: x.trade, label_en: x.label_en, via: 'model' as const, phrase: x.quote, snippet: x.quote, doc: nameOf.get(x.doc) ?? x.doc, path: x.doc, licence: lic, delivery: 'partner' as const, partner_name: x.partner_name })),
  ];
  const trades = p.trades.map((t) => ({ code: t.code, via: 'model_choice' as const, phrases: [t.words], snippet: t.quote, doc: t.doc }));
  return { ok: true, trades, services: services.sort((a, b) => a.key.localeCompare(b.key)), rejected: r.reading.rejected.map((x) => ({ code: x.what, why: x.why })),
    profile: { reader: READER, read_at: new Date().toISOString(), times: r.times, ...r.reading, ...p } };
}

/** The reading laid onto each document's evidence: its trades and services are the ones quoted from it. */
export function withReading(docs: DocEvidence[], r: Reading): DocEvidence[] {
  const reads = (d: DocEvidence) => d.status === 'read' && d.kind !== 'licence' && !!d.text?.trim();
  const first = docs.find(reads);
  return docs.map((d) => {
    if (d.status !== 'read') return d;
    if (d.kind === 'licence') return { ...d, trades: [], ...(r.ok ? {} : r.why === 'no_documents' ? { reason: r.error } : {}) };
    if (!reads(d)) return d;
    if (r.ok) {
      const { choice: _c, held_readings: _h, ...rest } = d;
      return { ...rest, choice: 'on', reason: undefined, trades: r.trades.filter((t) => t.doc === d.path).map(({ doc: _doc, ...t }) => t),
        services: r.services.filter((s) => s.path === d.path).map(({ doc: _doc, licence: _l, path: _p, ...s }) => s),
        ...(d === first ? { rejected: r.rejected } : {}) };
    }
    return { ...d, trades: [], choice: 'unavailable', reason: `still being read: ${r.error}` };
  });
}

/** The services the model understood from the documents, each with the line it came from, and the licence's activities. */
export function servicesAndLicence(r: Reading, docs: DocEvidence[]): { proposed: ProposedService[]; licence_check: LicenceCheck } {
  const lic = docs.find((d) => d.kind === 'licence' && d.status === 'read');
  const proposed: ProposedService[] = r.ok ? r.services.map(({ path: _p, ...s }) => s) : [];
  return { proposed, licence_check: { read: !!lic?.activities?.length, activities: lic?.activities ?? [], licence_trades: [],
    not_covered: proposed.filter((p) => p.licence === 'not_covered').map((p) => p.key), checked_at: new Date().toISOString() } };
}

/** One document -> what it says about trades, or the honest reason it could not be read. */
export async function readDocForTrades(doc: DocIn, deps: TradeResolveDeps, opts: { textOnly?: boolean } = {}): Promise<DocEvidence> {
  const base = { path: doc.path, name: doc.name, kind: doc.kind, read_at: new Date().toISOString() };
  const photo = String(doc.photo_text ?? '').slice(0, PHOTO_TEXT_MAX);
  const ocr = String(doc.ocr_text ?? '').slice(0, PHOTO_TEXT_MAX);
  // A PARTIAL READ SAYS SO (3 Nov 2026, scripts/e2e/document_reading_qualification.ts). A 300-page profile read to page 250 was
  // recorded 'read' with nothing to show that 50 pages were never read: the note pdf.js wrote was dropped here.
  // ponytail: the unread pages are recorded, not read later; upgrade: the re-read sweep resumes from pages.read + 1.
  let partial: { read: number; of: number } | undefined, resumable = false;
  const found = async (text: string, source: 'document_text' | 'photo_text' | 'ocr_text', format?: string): Promise<DocEvidence> => {
    // a continuation is read with the text of its earlier pages before it (proposeTradesFromDocs gives it as `prev_text`)
    const e = await foundIn(doc.prev_text ? `${doc.prev_text}\n${text}` : text, source, format);
    if (!partial) return e;
    const said = `read ${partial.read} of ${partial.of} pages; ${resumable ? 'the rest is being read' : 'the rest of the document was not read'}`;
    return { ...e, pages: partial, reason: e.reason ? `${e.reason} (${said})` : said, ...(resumable ? { resume: true } : {}) };
  };
  // The document's text, read by code; then (unless textOnly) the model reads it, as readTogether reads all of a supplier's documents.
  const foundIn = async (text: string, source: 'document_text' | 'photo_text' | 'ocr_text', format?: string): Promise<DocEvidence> => {
    const prep = preparedText(doc.kind, text);
    const e: DocEvidence = { ...base, status: 'read', format, source, trades: [], text, ...(doc.rereads ? { rereads: doc.rereads } : {}),
      ...(doc.kind === 'licence' ? { activities: licenceFieldsFromText(text).activities ?? [] } : {}), ...(prep.supply_only !== undefined ? { supply_only: prep.supply_only } : {}) };
    if (opts.textOnly) return e;
    return withReading([e], await readTogether([e], deps, (doc.names ?? []).find((n) => !!n) ?? null))[0];
  };
  if (doc.refused) return { ...base, status: 'refused', reason: doc.refused.slice(0, 200), trades: [] };
  const r = doc.read ?? (doc.bytes ? await readDocument(doc.bytes, doc.name, doc.mime || '', 0, { textOnly: true, maxBytes: LIMITS.maxPaperBytes, fromPage: doc.from_page }) : null);
  const text = r && r.ok ? allText(r) : '';
  const p = (r && r.ok && r.pages && r.pages.read < r.pages.of) ? r.pages : doc.pages_read;
  // resumable only while pages remain under the reader's page cap; past it the unread pages are filed (docPartiallyRead), not re-read
  if (p && p.read < p.of) { partial = p; resumable = p === (r && r.ok ? r.pages : undefined) && pagesLeft(p); }
  // A CONTINUATION THAT READ NOTHING NEW keeps the evidence it had and never asks the model about an empty text (review of #1833)
  if (doc.prev && r && r.ok && !r.needs && !text.trim()) {
    const { resume: _resume, pages: _pages, ...kept } = doc.prev;
    const said = partial ? `read ${partial.read} of ${partial.of} pages; the rest of the document was not read` : '';
    const was = (doc.prev.reason ?? '').replace(/ ?\(read \d+ of \d+ pages;[^)]*\)$/, '');
    return { ...kept, read_at: base.read_at, trades: doc.prev.trades || [], unchanged: true, ...(partial ? { pages: partial, reason: was ? `${was} (${said})` : said } : {}) };
  }
  // The file's own text layer wins; then code's OCR of the scan; the vision model's transcription only when neither exists.
  // A SCAN WITH A STRAY TEXT LAYER (M12, 19 Oct 2026): the group profile is an image-only scan whose PDF still carries a stray text
  // layer: the reader reads 71 characters, 13 of them letters or digits ("58", "GLOBAL REACH"; measured 19 Oct 2026). That non-empty layer won over code's 15,179-character OCR, so the model was given
  // the stray words and named nothing (measured: 3 readings of {"trades":[]}; the same file with the OCR text read all 5 core
  // trades). Code's OCR now wins whenever the text layer holds fewer than 200 letters or digits and the OCR holds more.
  const layerChars = text.replace(/[^\p{L}\p{N}]/gu, '').length, ocrChars = ocr.replace(/[^\p{L}\p{N}]/gu, '').length;
  if (ocrChars >= 200 && layerChars < 200 && ocrChars > layerChars) return await found(ocr, 'ocr_text', r && r.ok ? r.kind : undefined);
  if (!text.trim() && photo.trim()) return await found(photo, 'photo_text', r && r.ok ? r.kind : undefined);
  if (!r) return { ...base, status: 'unreadable', reason: 'the file could not be fetched from storage', trades: [] };
  if (!r.ok) return { ...base, status: 'unreadable', reason: `${r.error}: ${r.detail}`.slice(0, 200), trades: [] };
  if (!text.trim() && r.needs === 'ocr') return { ...base, status: 'needs_ocr', format: r.kind, reason: (doc.unread_reason || r.notes.join(' ')).slice(0, 200), trades: [] };
  if (!text.trim() && r.needs) return { ...base, status: 'needs_cad_conversion', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  return await found(text, 'document_text', r.kind);
}

// Evidence a reader before @3 wrote: its trades came from the document's alias words. It is kept as a record
// of the file, but it proposes nothing any more (measured 29 Sep 2026: 1 supplier_capabilities row carries such
// evidence, source_docs.reader 'supplier_doc_trades@2'). The next upload of that file reads it by code and meaning.
export const WORD_READ = 'read by alias words before 29 Sep 2026 (ruling 890); upload the file again to read it by exact code and meaning';
// a record of reader @2: no exact / meaning fields AND no model choice (readers @3 and @4 record `choice` on every document the model read)
const wordRead = (d: DocEvidence) => d.status === 'read' && d.exact === undefined && d.meaning === undefined && d.choice === undefined && (d.trades || []).length > 0;

/** A licence or profile replaces the previous one of its kind; catalogues accumulate. */
export function mergeEvidence(prev: DocEvidence[], fresh: DocEvidence[]): DocEvidence[] {
  const replaced = (d: DocEvidence) => fresh.some((f) => f.path === d.path || (f.kind !== 'catalogue' && f.kind === d.kind));
  const kept = prev.filter((d) => !replaced(d)).map((d) => (wordRead(d) ? { ...d, trades: [], reason: WORD_READ } : d));
  return [...fresh, ...kept].slice(0, MAX_DOCS);
}

/** A document read only in part (DocEvidence.pages): one pending agent_actions item (kind doc_partially_read) per supplier and document,
 *  for the sales engineer, naming the pages that were NOT read, so they are read by a person rather than silently dropped. */
export async function docPartiallyRead(admin: Admin, supplierId: number, d: DocEvidence): Promise<void> {
  const target = `${supplierId}:${d.path}`;
  try {
    const { data: open } = await admin.from('agent_actions').select('id').eq('kind', 'doc_partially_read').eq('status', 'pending').eq('target_id', target).limit(1);
    if (open?.length) return;
    const { error } = await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'doc_partially_read', status: 'pending', risk: 'low',
      title: (`Read pages ${d.pages!.read + 1}-${d.pages!.of} of a supplier document the reader stopped short of: ` + d.name).slice(0, 200),
      detail: { supplier_id: supplierId, path: d.path, kind: d.kind, pages_read: d.pages!.read, pages_total: d.pages!.of, proposed: (d.trades || []).map((t) => t.code),
                waiting_for: 'sales_engineer to read the unread pages and add any trade they state to the proposal the supplier confirms' },
      target_table: 'supplier_capabilities', target_id: target });
    if (error) console.error(JSON.stringify({ at: 'supplier_doc_trades.docPartiallyRead', supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: 'supplier_doc_trades.docPartiallyRead', supplier: supplierId, error: String((e as Error)?.message || e) })); }
}

/** A profile states services the trade licence's activities do not cover: one pending agent_actions item (kind
 *  licence_scope_check) per supplier for the sales engineer, refreshed with the latest reading. NEVER a rejection (founder
 *  ledger 1573: "checks the licence activities against the profile"): the supplier still sees and may confirm each service,
 *  told it is not on his licence; the sales engineer decides with the activities and the profile lines side by side. */
export async function licenceScopeCheck(admin: Admin, supplierId: number,
  check: { activities: string[]; licence_trades: string[]; not_covered: string[] }, proposed: { key: string; phrase: string; snippet: string; licence: string }[]): Promise<void> {
  const target = String(supplierId);
  const detail = { supplier_id: supplierId, licence_activities: check.activities, licence_trades: check.licence_trades,
    not_covered: proposed.filter((p) => p.licence === 'not_covered').map((p) => ({ key: p.key, phrase: p.phrase, line: p.snippet })),
    waiting_for: 'sales_engineer to compare the licence activities with the profile and confirm or question the services the licence does not list' };
  try {
    const { data: open } = await admin.from('agent_actions').select('id').eq('kind', 'licence_scope_check').eq('status', 'pending').eq('target_id', target).limit(1);
    if (open?.length) { await admin.from('agent_actions').update({ detail }).eq('id', open[0].id); return; }
    const { error } = await admin.from('agent_actions').insert({ agent: 'sales_engineer', kind: 'licence_scope_check', status: 'pending', risk: 'low',
      title: `Profile services not on the trade licence: ${check.not_covered.slice(0, 4).join(', ')}`.slice(0, 200),
      detail, target_table: 'supplier_capabilities', target_id: target });
    if (error) console.error(JSON.stringify({ at: 'supplier_doc_trades.licenceScopeCheck', supplier: supplierId, error: error.message }));
  } catch (e) { console.error(JSON.stringify({ at: 'supplier_doc_trades.licenceScopeCheck', supplier: supplierId, error: String((e as Error)?.message || e) })); }
}

export const proposedFrom = (docs: DocEvidence[]): string[] =>
  [...new Set(docs.flatMap((d) => (d.trades || []).map((t) => t.code)))].sort();

/**
 * Read the documents, merge the evidence into what this supplier already has, and store the proposal.
 * Never throws and never blocks an upload: a failure comes back as { error } for the caller to report.
 * `deps` is for tests; an edge function passes nothing and gets the live routine, vectors and model.
 */
/**
 * HELD BEFORE IT IS READ (review of #1404). The edge worker is killed at its CPU cap with no catch running, so a parse
 * that dies must already have left its mark: each document is stored as 'reading' first. A finished read replaces the
 * mark; a killed one leaves the document held ('reading', no trades), visible as not read rather than silently absent.
 * Never throws; a failed write is returned for the caller to report.
 */
export async function markReading(admin: Admin, supplierId: number, docs: { path: string; name: string; kind: DocKind }[], retry = false): Promise<string | null> {
  try {
    if (!docs.length) return null;
    const at = new Date().toISOString();
    // a continuation keeps the trades its earlier pages proposed while the rest is read
    const marks: DocEvidence[] = docs.map((d) => ({ path: d.path, name: d.name, kind: d.kind, status: 'reading', reason: 'being read; if this stays, the read did not finish', trades: (d as DocIn).prev?.trades ?? [], read_at: at, ...(retry ? { retry } : {}) }));
    // laid onto the row as it is at the write (fn_supplier_source_docs_store): a mark never puts back an older copy of another document
    for (let i = 0; i < STORE_TRIES; i++) {
      const prevSrc = await readSourceDocs(admin, supplierId);
      const merged = mergeEvidence(docsOf(prevSrc), marks);
      const r = await storeSourceDocs(admin, supplierId, prevSrc, { ...prevSrc, reader: READER, docs: merged });
      if (r === 'stored') return null;
      if (r !== 'moved') return `mark: ${r}`;
    }
    return `mark: the row was written by another read ${STORE_TRIES} times in a row`;
  } catch (e) { return String((e as Error)?.message || e).slice(0, 200); }
}

// ONE WRITER OF source_docs AT A TIME (12 Nov 2026, customer_support; final audit R1, regcert_diagnosis F1; ledger 1642). Every
// writer here read source_docs, waited on the model (4-60 s; 30 calls, mean 17.4 s, in the paid round of 11 Nov) and wrote the
// WHOLE value back, so the slower of two reads of one supplier put back its old copy of the other's document: on 11 Nov the
// profile's read set the licence, read 42 s earlier, to 'reading' again with no activities, and the gate held the supplier
// pending until the 30-minute sweep. Now each write goes through fn_supplier_source_docs_store
// (scripts/sql/two_reads_of_one_suppliers_documents_never_overwrite_each_other.sql), which writes only when the row still has
// the fingerprint the writer read, under the row's lock. 'moved' means another read wrote first: the caller reads the row again.
export const STORE_TRIES = 5;
const docsOf = (src: Record<string, unknown>): DocEvidence[] => Array.isArray(src.docs) ? src.docs as DocEvidence[] : [];
/** The row's source_docs ({} when the supplier has no row yet). */
export async function readSourceDocs(admin: Admin, supplierId: number): Promise<Record<string, unknown>> {
  const { data: cur, error } = await admin.from('supplier_capabilities').select('source_docs').eq('supplier_id', supplierId).maybeSingle();
  if (error) throw new Error(`read: ${error.message}`);
  return (cur?.source_docs && typeof cur.source_docs === 'object') ? cur.source_docs as Record<string, unknown> : {};
}
/** What fn_supplier_source_docs_store compares: the version and each document's path, status and read_at, in stored order.
 *  Strings only, so it compares exactly after the JSON round trip. two_reads_of_one_supplier_never_overwrite_each_other.test.ts and the SQL probe hold the
 *  two to one literal. */
export function sourceDocsFingerprint(src: Record<string, unknown>): { v: number; docs: (string | null)[][] } {
  const s = (x: unknown) => (x == null ? null : String(x));
  return { v: Number(src.v ?? 0), docs: docsOf(src).map((d) => { const r = d as unknown as Record<string, unknown>; return [s(r.path), s(r.status), s(r.read_at)]; }) };
}
/** Writes `next` if the row still holds `read` (what this writer read): 'stored', 'moved' (another read wrote first), or the error. */
export async function storeSourceDocs(admin: Admin, supplierId: number, read: Record<string, unknown>, next: Record<string, unknown>,
  opts: { proposed_trades?: string[]; extracted?: boolean } = {}): Promise<'stored' | 'moved' | string> {
  const { data, error } = await admin.rpc('fn_supplier_source_docs_store', { p_supplier_id: supplierId, p_expect: sourceDocsFingerprint(read),
    p_source_docs: next, p_proposed_trades: opts.proposed_trades ?? null, p_extracted: !!opts.extracted });
  if (error) return `store: ${error.message}`;
  return data === true ? 'stored' : data === false ? 'moved' : `store: unexpected answer ${JSON.stringify(data)}`;
}
/** The licence and profile files the supplier's row (leads) names now; null when it names none or could not be read. */
export async function filesOnRow(admin: Admin, supplierId: number): Promise<{ licence: string | null; profile: string | null }> {
  try {
    const { data } = await admin.from('leads').select('license_doc_path,company_profile_doc_path').eq('id', supplierId).maybeSingle();
    const p = (x: unknown) => (typeof x === 'string' && x.trim() ? x.trim().replace(/^supplier-docs\//, '') : null);
    return { licence: p(data?.license_doc_path), profile: p(data?.company_profile_doc_path) };
  } catch { return { licence: null, profile: null }; }
}
/** A licence or profile the supplier's row no longer names: a newer upload replaced it, and its read is not written (the newer
 *  file's own read writes). Decided from leads, never from source_docs, so a failed mark cannot make a new file look replaced
 *  (review of the fix, 12 Nov 2026). A row that names no file decides nothing; a catalogue is never replaced by another. */
export const replacedOnRow = (row: { licence: string | null; profile: string | null }, d: { path: string; kind: DocKind }): boolean => {
  const named = d.kind === 'licence' ? row.licence : d.kind === 'profile' ? row.profile : null;
  return !!named && named !== d.path.replace(/^supplier-docs\//, '');
};
/** The documents the model is given (readTogether's `usable`), by path and read time: a reading stands for this set only. */
const givenOf = (docs: DocEvidence[]) => docs.filter((d) => d.status === 'read' && d.text?.trim()).map((d) => `${d.path}|${d.read_at}`).sort().join('\n');
// A reading laid on documents another read has changed is read together again, at most this many times (one model call each);
// after that the documents this read holds are laid onto the row and the supplier-wide fields are left as the other read wrote them.
export const READ_AGAIN_MAX = 2;

export type ProposeResult = { ok: true; proposed_trades: string[]; docs: DocEvidence[] } | { ok: false; error: string };

/** The names the supplier is known by, read once: the registered name and the licence's legal name. */
export async function knownNames(admin: Admin, supplierId: number): Promise<(string | null)[]> {
  const { data: who } = await admin.from('leads').select('company_name,licence_legal_name').eq('id', supplierId).maybeSingle();
  return [who?.company_name ?? null, who?.licence_legal_name ?? null];
}

/** Step 1: CODE READS each new document into text, kept beside the file (saveText). The bytes are let go after each. */
export async function readTexts(admin: Admin, docs: DocIn[], known: (string | null)[]): Promise<DocEvidence[]> {
  const fresh: DocEvidence[] = [];
  for (const d of docs) {
    let bytes = d.bytes;
    if (!bytes && !d.read && !d.refused) {
      const { data: blob } = await admin.storage.from('supplier-docs').download(d.path);
      if (blob) bytes = new Uint8Array(await blob.arrayBuffer());
    }
    const prev_text = d.prev ? (await loadText(admin, d.prev)) ?? undefined : undefined;
    const e = await readDocForTrades({ ...d, bytes, prev_text, names: [...known, ...(d.names ?? [])] }, {}, { textOnly: true });
    await saveText(admin, e);
    fresh.push(e);
  }
  return fresh;
}

/**
 * Step 2: every document of the supplier, the new ones with those read before, READ TOGETHER BY THE MODEL (readTogether), and
 * the proposal stored. A document read before has its text from its sidecar; one read before the sidecar existed (reader @3
 * and earlier) is read again from storage, once, and its sidecar written. Never throws.
 */
export async function proposeFromRead(admin: Admin, supplierId: number, fresh: DocEvidence[], deps: TradeResolveDeps, known: (string | null)[]): Promise<ProposeResult> {
  try {
    const texts = new Map<string, string | null>();   // path|read_at -> kept text: a second attempt does not parse again
    let live = fresh, reading: Reading | null = null, given = '', asked = 0;
    for (let attempt = 0; attempt < STORE_TRIES + READ_AGAIN_MAX; attempt++) {
      const prevSrc = await readSourceDocs(admin, supplierId);
      const prevDocs = docsOf(prevSrc);
      // a licence or profile the supplier's row no longer names is not written back over the newer file (final audit R3)
      const onRow = await filesOnRow(admin, supplierId);
      const gone = live.filter((d) => replacedOnRow(onRow, d));
      if (gone.length) console.error(JSON.stringify({ at: 'supplier_doc_trades.proposeFromRead', supplier: supplierId, superseded: gone.map((d) => d.path) }));
      live = live.filter((d) => !gone.includes(d));
      if (fresh.length && !live.length) return { ok: true, proposed_trades: proposedFrom(prevDocs), docs: [] };
      const all = mergeEvidence(prevDocs, live);
      const isFresh = (d: DocEvidence) => live.some((f) => f.path === d.path);
      const withText: DocEvidence[] = [];
      for (const d of all) {
        if (d.text !== undefined || d.status !== 'read') { withText.push(d); continue; }
        const key = `${d.path}|${d.read_at}`;
        if (!texts.has(key)) {
          let text = await loadText(admin, d);
          if (text == null && d.source !== 'photo_text') {
            const [re] = await readTexts(admin, [{ path: d.path, name: d.name, kind: d.kind }], known);
            text = re?.status === 'read' ? re.text ?? null : null;
          }
          texts.set(key, text);
        }
        const text = texts.get(key);
        withText.push(text == null ? d : { ...d, text });
      }
      // a continuation that read nothing new changes nothing the model read: it is not asked again (review of #1833)
      if (live.length && live.every((d) => d.unchanged)) {
        const merged = withText.map(({ text: _t, unchanged: _u, ...d }) => d as DocEvidence);
        const r = await storeSourceDocs(admin, supplierId, prevSrc, { ...prevSrc, reader: READER, docs: merged }, { proposed_trades: proposedFrom(merged), extracted: true });
        if (r === 'moved') continue;
        if (r !== 'stored') return { ok: false, error: r };
        for (const d of live) if (d.pages && d.pages.read < d.pages.of && !d.resume) await docPartiallyRead(admin, supplierId, d);
        return { ok: true, proposed_trades: proposedFrom(merged), docs: merged.filter(isFresh) };
      }
      // The model reads the documents as they are on the row now. A reading of the same documents is laid again without asking
      // (only a mark or another document's status moved); a reading of a different set is asked again, at most READ_AGAIN_MAX times.
      const now = givenOf(withText);
      const last = reading !== null && now !== given && asked > READ_AGAIN_MAX;
      if (reading === null || (now !== given && !last)) { reading = await readTogether(withText, deps, known.find((n) => !!n) ?? null); given = now; asked++; }
      // AN OUTAGE CHANGES NOTHING THAT WAS READ: the new documents say they are still being read (the sweep reads them again,
      // supplier_docs_later.stuckOf), and what an earlier reading proposed stands until a reading succeeds.
      const outage = !reading.ok && reading.why === 'unavailable';
      // read together too often while the row kept changing: only this read's own documents are laid, and the services and the
      // licence check another read wrote stand (logged; the next read of this supplier lays them all again)
      const ownOnly = outage || last;
      if (last) console.error(JSON.stringify({ at: 'supplier_doc_trades.proposeFromRead', supplier: supplierId, error: `the documents changed ${asked} times while they were read; this read's own documents are stored` }));
      const laid = ownOnly ? withText.map((d) => isFresh(d) ? withReading([d], reading!)[0] : d) : withReading(withText, reading);
      const merged = laid.map(({ text: _t, unchanged: _u, ...d }) => d as DocEvidence);
      const proposed = proposedFrom(merged);
      // THE SERVICES THE MODEL UNDERSTOOD AND THE LICENCE CHECK: stored beside the documents, shown on the Services tab for the
      // supplier to tick (never ticked for him), and a service the licence does not cover goes to the sales engineer.
      const { proposed: proposedServices, licence_check } = ownOnly
        ? { proposed: (prevSrc.proposed_services ?? []) as ProposedService[], licence_check: (prevSrc.licence_check ?? servicesAndLicence(reading, merged).licence_check) as LicenceCheck }
        : servicesAndLicence(reading, merged);
      // reader @5: the reading itself, its tick list, his own words and the drafted questions (report 3.1), through the same compare-and-set
      const stored = !ownOnly && reading.ok && reading.profile ? { reading: reading.profile } : {};
      const r = await storeSourceDocs(admin, supplierId, prevSrc, { ...prevSrc, reader: READER, docs: merged, proposed_services: proposedServices, licence_check, ...stored },
        { proposed_trades: proposed, extracted: true });
      if (r === 'moved') continue;
      if (r !== 'stored') return { ok: false, error: r };
      // a read the next sweep run continues (resume) is not filed; a scan cut for the model is, since nothing will read the rest
      for (const d of live) if (d.pages && d.pages.read < d.pages.of && !d.resume) await docPartiallyRead(admin, supplierId, d);
      if (!ownOnly && licence_check.not_covered.length) await licenceScopeCheck(admin, supplierId, licence_check, proposedServices);
      return { ok: true, proposed_trades: proposed, docs: merged.filter(isFresh) };
    }
    return { ok: false, error: `store: the row was written by another read ${STORE_TRIES + READ_AGAIN_MAX} times in a row` };
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) };
  }
}

/** Read the documents (step 1), then all of the supplier's documents together (step 2). Never throws. `deps` is for tests. */
export async function proposeTradesFromDocs(admin: Admin, supplierId: number, docs: DocIn[], deps?: TradeResolveDeps, retry = false): Promise<ProposeResult> {
  try {
    if (!docs.length) return { ok: true, proposed_trades: [], docs: [] };
    const d0 = deps ?? await liveTradeDeps(admin);
    const known = await knownNames(admin, supplierId);
    const markErr = await markReading(admin, supplierId, docs.filter((d) => !d.refused), retry);
    if (markErr) console.error(JSON.stringify({ at: 'supplier_doc_trades.markReading', supplier: supplierId, error: markErr }));
    return await proposeFromRead(admin, supplierId, await readTexts(admin, docs, known), d0, known);
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) };
  }
}
