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
// RFQ side uses, words only), its text is matched against taxonomy_trade exactly as the estate's
// normaliser public.fn_norm_trades matches it, and what matched is stored as a PROPOSAL:
//   supplier_capabilities.proposed_trades   the codes the documents name
//   supplier_capabilities.source_docs.docs  per file: status, and per trade the matched phrases and
//                                           the line they were found on (the evidence)
// It never touches supplier_capabilities.trades or confirmed_at. The supplier sees the proposal in
// "What your company can quote for", ticks or unticks it, and only the confirm writes trades.
//
// EXACT OR NONE. A trade is proposed only when one of its aliases (or its code) occurs in the text,
// word-start anchored, the same rule fn_norm_trades applies to a customer's brief. There is no
// nearest-trade guess, no similarity floor, no model. A scan or photo with no text layer is recorded
// 'needs_ocr' — never as "no trades found", which would be a false zero.
//
// ARABIC (15 Sep 2026). taxonomy_trade.aliases were English only, so an Arabic-only document proposed
// nothing. Every active code now carries Arabic aliases and the matcher (trade_words.ts, the twin of
// fn_norm_trades) folds Arabic spelling and reads the definite article; READER is @2 from then on.
import { readDocument, type DocumentRead } from './doc_read/index.ts';
import type { Extracted } from './doc_read/types.ts';
import { tradesFromText, type TradeHit, type TradeTerm } from './trade_words.ts';
import { readCatalogue } from './catalogue_read.ts';
import type { ServiceTerm } from './service_rewrite.ts';

export { tradesFromText, type TradeHit, type TradeTerm };

// A CATALOGUE IS READ AS A CATALOGUE (21 Sep 2026, _shared/catalogue_read.ts). Its spec tables, address
// block and marketing sentences are set aside before matching, and when the service vocabulary is
// passed, every service its headings and product types name proposes that service's trade too — a
// catalogue that lists "Printers" and "UPS" names office equipment and power backup even though no
// trade alias says "printer". The words that proposed it are the evidence, as for any trade.
function catalogueTrades(text: string, vocab: TradeTerm[], services: ServiceTerm[]): { trades: TradeHit[]; supply_only: boolean } {
  const c = readCatalogue(text, services, vocab);
  const hits = new Map(tradesFromText(c.matched_text, vocab).map((h) => [h.code, h]));
  for (const it of c.rewrite.items) {
    if (it.kind !== 'service') continue;
    const h = hits.get(it.trade) || { code: it.trade, phrases: [], snippet: it.from.slice(0, 180) };
    if (h.phrases.length < 5 && !h.phrases.includes(it.label_en.toLowerCase())) h.phrases.push(it.label_en.toLowerCase());
    hits.set(it.trade, h);
  }
  return { trades: [...hits.values()].sort((a, b) => a.code.localeCompare(b.code)), supply_only: c.supply_only };
}

// deno-lint-ignore no-explicit-any
type Admin = any;
export const READER = 'supplier_doc_trades@2';
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
};
export const PHOTO_TEXT_MAX = 60_000;

/** Every word a read document holds: its text, its table cells, and its zip / email children. */
export function allText(e: Extracted, depth = 0): string {
  const cells = e.tables.flatMap((t) => t.map((row) => row.filter((c) => c != null && c !== '').join(' ')));
  const kids = depth < 3 ? e.children.map((c) => allText(c.doc, depth + 1)) : [];
  return [e.text, ...cells, ...kids].filter(Boolean).join('\n');
}

/** One document -> what it says about trades, or the honest reason it could not be read. */
export async function readDocForTrades(doc: DocIn, vocab: TradeTerm[], services?: ServiceTerm[]): Promise<DocEvidence> {
  const base = { path: doc.path, name: doc.name, kind: doc.kind, read_at: new Date().toISOString() };
  const photo = String(doc.photo_text ?? '').slice(0, PHOTO_TEXT_MAX);
  const found = (text: string, source: 'document_text' | 'photo_text', format?: string): DocEvidence => {
    if (doc.kind === 'catalogue' && services?.length) {
      const c = catalogueTrades(text, vocab, services);
      return { ...base, status: 'read', format, source, trades: c.trades, supply_only: c.supply_only };
    }
    return { ...base, status: 'read', format, source, trades: tradesFromText(text, vocab) };
  };
  const r = doc.read ?? (doc.bytes ? await readDocument(doc.bytes, doc.name, doc.mime || '', 0, { textOnly: true }) : null);
  const text = r && r.ok ? allText(r) : '';
  // The file's own text layer wins; the photo text is read only when the file has none of its own.
  if (!text.trim() && photo.trim()) return found(photo, 'photo_text', r && r.ok ? r.kind : undefined);
  if (!r) return { ...base, status: 'unreadable', reason: 'the file could not be fetched from storage', trades: [] };
  if (!r.ok) return { ...base, status: 'unreadable', reason: `${r.error}: ${r.detail}`.slice(0, 200), trades: [] };
  if (!text.trim() && r.needs === 'ocr') return { ...base, status: 'needs_ocr', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  if (!text.trim() && r.needs) return { ...base, status: 'needs_cad_conversion', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  return found(text, 'document_text', r.kind);
}

/** A licence or profile replaces the previous one of its kind; catalogues accumulate. */
export function mergeEvidence(prev: DocEvidence[], fresh: DocEvidence[]): DocEvidence[] {
  const replaced = (d: DocEvidence) => fresh.some((f) => f.path === d.path || (f.kind !== 'catalogue' && f.kind === d.kind));
  return [...fresh, ...prev.filter((d) => !replaced(d))].slice(0, MAX_DOCS);
}

export const proposedFrom = (docs: DocEvidence[]): string[] =>
  [...new Set(docs.flatMap((d) => (d.trades || []).map((t) => t.code)))].sort();

/**
 * Read the documents, merge the evidence into what this supplier already has, and store the proposal.
 * Never throws and never blocks an upload: a failure comes back as { error } for the caller to report.
 */
export async function proposeTradesFromDocs(admin: Admin, supplierId: number, docs: DocIn[]):
  Promise<{ ok: true; proposed_trades: string[]; docs: DocEvidence[] } | { ok: false; error: string }> {
  try {
    if (!docs.length) return { ok: true, proposed_trades: [], docs: [] };
    const { data: vocab, error: vErr } = await admin.from('taxonomy_trade').select('code,aliases').eq('active', true);
    if (vErr) return { ok: false, error: `vocabulary: ${vErr.message}` };
    // The service aliases too, but only when a catalogue is among the documents: they are what read it.
    const services: ServiceTerm[] = docs.some((d) => d.kind === 'catalogue')
      ? ((await admin.from('taxonomy_trade_service').select('trade_code,code,label_en,label_ar,aliases').eq('active', true)).data || [])
      : [];
    const fresh: DocEvidence[] = [];
    for (const d of docs) {
      let bytes = d.bytes;
      if (!bytes && !d.read) {
        const { data: blob } = await admin.storage.from('supplier-docs').download(d.path);
        if (blob) bytes = new Uint8Array(await blob.arrayBuffer());
      }
      fresh.push(await readDocForTrades({ ...d, bytes }, vocab || [], services));
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
