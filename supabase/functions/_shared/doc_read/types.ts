// doc_read — the ONE place a document's content is read, deterministically, with no model.
//
// WHY (14 Sep 2026). Founder: "the sales agent need to be extremely capable of reading all types of
// document", with OpenConstructionERP's README named as the minimum bar. Before this, customer and
// supplier uploads were read only as PDF text layers and spreadsheets; every other format was
// refused or stored unread. Every model route is on hold, so every reader here is plain code.
//
// THE CONTRACT. Each format module exports `read<Format>(bytes, ctx)` returning a ReadResult. Readers
// do NOT scrub identity and do NOT drop prices: they report what the file says. The caller that
// turns a result into a customer BOQ (drawing_boq, via boqFromExtracted) scrubs contacts with
// scrubIdentity and never reads a price column. A supplier-quote caller may keep prices.
// Readers never evaluate formulas, run macros, expand external entities, or follow links.

export type Cell = string | number | boolean | null | undefined;

/** A quantity the format itself states or measures (CAD, BIM, GAEB, a scaled PDF). */
export type Qty = {
  section: string;
  description: string;
  qty: number | null;
  unit: string;
  /** Where it came from, precise enough for a human to check: "layer WALLS, 12 closed polylines". */
  basis: string;
  confidence: 'low' | 'medium';
};

export type Extracted = {
  /** Short format name: 'pdf' | 'docx' | 'doc' | 'pptx' | 'odt' | 'ods' | 'xlsx' | 'csv' | 'rtf' | 'txt' | 'dxf' | 'ifc' | 'gaeb' | 'eml' | 'msg' | 'zip' | 'image' | ... */
  kind: string;
  /** Text in reading order, lines separated by '\n'. NOT scrubbed. Capped at LIMITS.maxTextChars. */
  text: string;
  /** Tables found in the document, each as rows of cells (cached values only, never formulas). */
  tables: Cell[][][];
  /** Quantities stated or measured by the format itself. */
  quantities: Qty[];
  /** Zip entries and email attachments, each read by the same dispatcher. */
  children: { name: string; doc: Extracted }[];
  /** Set when the content cannot be read without something outside this function. */
  needs: null | 'ocr' | 'cad_conversion' | 'bim_conversion';
  /** Honest limits in plain English; they become the BOQ's missing_info. */
  notes: string[];
};

export type Refusal = { ok: false; error: string; detail: string };
export type ReadResult = ({ ok: true } & Extracted) | Refusal;

export type ReadContext = {
  filename: string;
  /** Zip / attachment nesting depth; a reader handing bytes back to the dispatcher passes depth + 1. */
  depth: number;
  /** The dispatcher, for containers (zip, eml, msg) whose children are documents in their own right. */
  readChild?: (bytes: Uint8Array, filename: string, depth: number) => Promise<ReadResult>;
};

export const empty = (kind: string, notes: string[] = [], needs: Extracted['needs'] = null): Extracted =>
  ({ kind, text: '', tables: [], quantities: [], children: [], needs, notes });

export const ok = (e: Extracted): ReadResult => ({ ok: true, ...e });
export const refuse = (error: string, detail: string): Refusal => ({ ok: false, error, detail });

/**
 * Hard ceilings for every reader. A document is a customer's file, not a denial-of-service vector:
 * the zip numbers match supplier_catalog_ingest's ZIP_CAPS (measured reasoning there), the text cap is
 * roughly 100 dense pages, the depth cap stops a zip in a zip in an email from nesting further.
 */
export const LIMITS = {
  maxBytes: 20 * 1024 * 1024,
  maxTextChars: 400_000,
  maxZipEntries: 512,
  maxZipTotalBytes: 64 * 1024 * 1024,
  maxZipRatio: 120,
  maxEntryBytes: 32 * 1024 * 1024,
  maxDepth: 2,
  maxTableRows: 2000,
  maxQuantities: 500,
} as const;

/** Append text without passing the cap; returns false once the cap is reached. */
export function capText(parts: string[], add: string, used: { n: number }): boolean {
  if (used.n >= LIMITS.maxTextChars) return false;
  const room = LIMITS.maxTextChars - used.n;
  const piece = add.length > room ? add.slice(0, room) : add;
  parts.push(piece); used.n += piece.length;
  return piece.length === add.length;
}
