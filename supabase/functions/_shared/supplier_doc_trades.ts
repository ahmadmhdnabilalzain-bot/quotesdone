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

export { tradesFromText, type TradeHit, type TradeTerm };

// deno-lint-ignore no-explicit-any
type Admin = any;
export const READER = 'supplier_doc_trades@2';
const MAX_DOCS = 40;

export type DocKind = 'licence' | 'profile' | 'catalogue';
export type DocIn = { path: string; name: string; kind: DocKind; bytes?: Uint8Array; mime?: string; read?: DocumentRead };
export type DocEvidence = {
  path: string; name: string; kind: DocKind;
  status: 'read' | 'needs_ocr' | 'needs_cad_conversion' | 'unreadable';
  reason?: string; format?: string; trades: TradeHit[]; read_at: string;
};

/** Every word a read document holds: its text, its table cells, and its zip / email children. */
export function allText(e: Extracted, depth = 0): string {
  const cells = e.tables.flatMap((t) => t.map((row) => row.filter((c) => c != null && c !== '').join(' ')));
  const kids = depth < 3 ? e.children.map((c) => allText(c.doc, depth + 1)) : [];
  return [e.text, ...cells, ...kids].filter(Boolean).join('\n');
}

/** One document -> what it says about trades, or the honest reason it could not be read. */
export async function readDocForTrades(doc: DocIn, vocab: TradeTerm[]): Promise<DocEvidence> {
  const base = { path: doc.path, name: doc.name, kind: doc.kind, read_at: new Date().toISOString() };
  const r = doc.read ?? (doc.bytes ? await readDocument(doc.bytes, doc.name, doc.mime || '', 0, { textOnly: true }) : null);
  if (!r) return { ...base, status: 'unreadable', reason: 'the file could not be fetched from storage', trades: [] };
  if (!r.ok) return { ...base, status: 'unreadable', reason: `${r.error}: ${r.detail}`.slice(0, 200), trades: [] };
  const text = allText(r);
  if (!text.trim() && r.needs === 'ocr') return { ...base, status: 'needs_ocr', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  if (!text.trim() && r.needs) return { ...base, status: 'needs_cad_conversion', format: r.kind, reason: r.notes.join(' ').slice(0, 200), trades: [] };
  return { ...base, status: 'read', format: r.kind, trades: tradesFromText(text, vocab) };
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
    const fresh: DocEvidence[] = [];
    for (const d of docs) {
      let bytes = d.bytes;
      if (!bytes && !d.read) {
        const { data: blob } = await admin.storage.from('supplier-docs').download(d.path);
        if (blob) bytes = new Uint8Array(await blob.arrayBuffer());
      }
      fresh.push(await readDocForTrades({ ...d, bytes }, vocab || []));
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
