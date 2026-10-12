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
// A TRADE IS NAMED BY AN EXACT CODE OR BY MEANING, NEVER BY THE DOCUMENT'S WORDS (29 Sep 2026, founder ledger
// 1054, ruling 890). Until today a trade was proposed wherever one of its aliases occurred in the text
// (trade_words.ts, the TS twin of the word matcher #893 removed from fn_norm_trades on 23 Sep), and a
// catalogue's service-alias hits proposed their trades too. Now (trade_resolve.ts):
//   exact code  a line or list item that IS a live code or intake slug, decided by public.fn_norm_trades;
//   meaning     the lines' gte-small vectors against every service's stored vector, accepted only with the
//               service's head word in the line (service_meaning.proposeByMeaning) — the service names its trade.
// A scan or photo with no text layer is recorded 'needs_ocr' — never as "no trades found", which would be a
// false zero — and a document whose meaning could not be read records why (meaning: embedding_unavailable,
// budget_spent), so an empty proposal is never mistaken for a document that names nothing.
import { readDocument, type DocumentRead } from './doc_read/index.ts';
import type { Extracted } from './doc_read/types.ts';
import { catalogueLines, supplyOnlyOf } from './catalogue_read.ts';
import { licenceFieldsFromText } from './document_expiry.ts';
import { liveTradeDeps, tradesOfText, type ExactState, type MeaningState, type TradeHit, type TradeResolveDeps } from './trade_resolve.ts';

export type { TradeHit, TradeResolveDeps };

// deno-lint-ignore no-explicit-any
type Admin = any;
export const READER = 'supplier_doc_trades@3';
const MAX_DOCS = 40;

export type DocKind = 'licence' | 'profile' | 'catalogue';
// `photo_text` is the text the supplier's own browser recognised in a photo or a scanned page
// (tesseract.js, the same self-hosted OCR the customer side uses). It is untrusted words like any other
// upload, read through the same path, and the evidence says it came from a photo.
export type DocIn = { path: string; name: string; kind: DocKind; bytes?: Uint8Array; mime?: string; read?: DocumentRead; photo_text?: string };
export type DocEvidence = {
  path: string; name: string; kind: DocKind;
  status: 'read' | 'needs_ocr' | 'needs_cad_conversion' | 'unreadable';
  reason?: string; format?: string; trades: TradeHit[]; read_at: string;
  source?: 'document_text' | 'photo_text'; supply_only?: boolean;
  /** how each path fared on this document (reader @3 on) */
  exact?: ExactState; meaning?: MeaningState;
};
export const PHOTO_TEXT_MAX = 60_000;

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

/** One document -> what it says about trades, or the honest reason it could not be read. */
export async function readDocForTrades(doc: DocIn, deps: TradeResolveDeps): Promise<DocEvidence> {
  const base = { path: doc.path, name: doc.name, kind: doc.kind, read_at: new Date().toISOString() };
  const photo = String(doc.photo_text ?? '').slice(0, PHOTO_TEXT_MAX);
  const found = async (text: string, source: 'document_text' | 'photo_text', format?: string): Promise<DocEvidence> => {
    // A LICENCE NAMES ITS TRADES IN ITS ACTIVITIES, NOWHERE ELSE (7 Oct 2026, accuracy suite ledger 1162). The whole
    // licence was read, so the company's NAME line proposed trades: "Company Name: ZZ DEMO Horizon Floor LLC" ->
    // floor cleaners and mezzanine floors, on 4 of 22 text licences of scripts/e2e/document_intake_corpus.mjs. Only
    // the labelled activities line is read now; a licence whose activities could not be read proposes nothing.
    if (doc.kind === 'licence') {
      const acts = licenceFieldsFromText(text).activities;
      if (!acts?.length) return { ...base, status: 'read', format, source, reason: 'no activities line could be read on the licence', trades: [] };
      text = acts.join('\n');
    } else text = withoutCredentialLines(text);
    const c = doc.kind === 'catalogue' ? catalogueText(text) : null;
    const r = await tradesOfText(c ? c.text : text, deps, { supplyOnly: c?.supply_only });
    return { ...base, status: 'read', format, source, trades: r.trades, exact: r.exact, meaning: r.meaning, ...(c ? { supply_only: c.supply_only } : {}) };
  };
  const r = doc.read ?? (doc.bytes ? await readDocument(doc.bytes, doc.name, doc.mime || '', 0, { textOnly: true }) : null);
  const text = r && r.ok ? allText(r) : '';
  // The file's own text layer wins; the photo text is read only when the file has none of its own.
  if (!text.trim() && photo.trim()) return await found(photo, 'photo_text', r && r.ok ? r.kind : undefined);
  if (!r) return { ...base, status: 'unreadable', reason: 'the file could not be fetched from storage', trades: [] };
  if (!r.ok) return { ...base, status: 'unreadable', reason: `${r.error}: ${r.detail}`.slice(0, 200), trades: [] };
  if (!text.trim() && r.needs === 'ocr') return { ...base, status: 'needs_ocr', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  if (!text.trim() && r.needs) return { ...base, status: 'needs_cad_conversion', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  return await found(text, 'document_text', r.kind);
}

// Evidence a reader before @3 wrote: its trades came from the document's alias words. It is kept as a record
// of the file, but it proposes nothing any more (measured 29 Sep 2026: 1 supplier_capabilities row carries such
// evidence, source_docs.reader 'supplier_doc_trades@2'). The next upload of that file reads it by code and meaning.
export const WORD_READ = 'read by alias words before 29 Sep 2026 (ruling 890); upload the file again to read it by exact code and meaning';
const wordRead = (d: DocEvidence) => d.status === 'read' && d.exact === undefined && d.meaning === undefined && (d.trades || []).length > 0;

/** A licence or profile replaces the previous one of its kind; catalogues accumulate. */
export function mergeEvidence(prev: DocEvidence[], fresh: DocEvidence[]): DocEvidence[] {
  const replaced = (d: DocEvidence) => fresh.some((f) => f.path === d.path || (f.kind !== 'catalogue' && f.kind === d.kind));
  const kept = prev.filter((d) => !replaced(d)).map((d) => (wordRead(d) ? { ...d, trades: [], reason: WORD_READ } : d));
  return [...fresh, ...kept].slice(0, MAX_DOCS);
}

export const proposedFrom = (docs: DocEvidence[]): string[] =>
  [...new Set(docs.flatMap((d) => (d.trades || []).map((t) => t.code)))].sort();

/**
 * Read the documents, merge the evidence into what this supplier already has, and store the proposal.
 * Never throws and never blocks an upload: a failure comes back as { error } for the caller to report.
 * `deps` is for tests; an edge function passes nothing and gets the live routine, vectors and model.
 */
export async function proposeTradesFromDocs(admin: Admin, supplierId: number, docs: DocIn[], deps?: TradeResolveDeps):
  Promise<{ ok: true; proposed_trades: string[]; docs: DocEvidence[] } | { ok: false; error: string }> {
  try {
    if (!docs.length) return { ok: true, proposed_trades: [], docs: [] };
    // One set of deps for every document of this call: the vectors are read once, and meaning's line budget is shared.
    const d0 = deps ?? await liveTradeDeps(admin);
    const fresh: DocEvidence[] = [];
    for (const d of docs) {
      let bytes = d.bytes;
      if (!bytes && !d.read) {
        const { data: blob } = await admin.storage.from('supplier-docs').download(d.path);
        if (blob) bytes = new Uint8Array(await blob.arrayBuffer());
      }
      fresh.push(await readDocForTrades({ ...d, bytes }, d0));
    }
    const { data: cur } = await admin.from('supplier_capabilities').select('source_docs').eq('supplier_id', supplierId).maybeSingle();
    const prevSrc = (cur?.source_docs && typeof cur.source_docs === 'object') ? cur.source_docs as Record<string, unknown> : {};
    const merged = mergeEvidence(Array.isArray(prevSrc.docs) ? prevSrc.docs as DocEvidence[] : [], fresh);
    const proposed = proposedFrom(merged);
    const { error } = await admin.from('supplier_capabilities').upsert({
      supplier_id: supplierId, proposed_trades: proposed,
      source_docs: { ...prevSrc, reader: READER, docs: merged }, extracted_at: new Date().toISOString(),
    }, { onConflict: 'supplier_id' });
    if (error) return { ok: false, error: `store: ${error.message}` };
    return { ok: true, proposed_trades: proposed, docs: fresh };
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) };
  }
}
