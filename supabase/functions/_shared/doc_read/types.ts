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
  /** Short format name: 'pdf' | 'docx' | 'doc' | 'pptx' | 'odt' | 'ods' | 'xlsx' | 'csv' | 'rtf' | 'txt' | 'dxf' | 'dwg' | 'gaeb' | 'eml' | 'msg' | 'zip' | 'image' | ... */
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
  /**
   * CAD readers only (22 Sep 2026): the ASCII DXF the take-off was measured from - the file itself, a
   * binary DXF converted, or a DWG's entities written out by dwg.ts. The caller hands it to
   * _shared/cad_identity.ts cadSupplierBoq so nothing the file says about its own job (title block,
   * $PROJECTNAME, xref paths, party attributes) reaches a BOQ line. Never serialised to a client.
   */
  dxf_text?: string;
};

export type Refusal = { ok: false; error: string; detail: string };
export type ReadResult = ({ ok: true } & Extracted) | Refusal;

export type ReadContext = {
  filename: string;
  /** Zip / attachment nesting depth; a reader handing bytes back to the dispatcher passes depth + 1. */
  depth: number;
  /** The dispatcher, for containers (zip, eml, msg) whose children are documents in their own right. */
  readChild?: (bytes: Uint8Array, filename: string, depth: number) => Promise<ReadResult>;
  /** Words only: skip the drawing measurement. A supplier's profile or catalogue is read for what it
   *  says, and measuring 40 pages of vector art spends CPU an edge function does not have. */
  textOnly?: boolean;
  /** The byte ceiling for this read: LIMITS.maxBytes unless the caller passed LIMITS.maxPaperBytes. */
  maxBytes?: number;
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
  // The same 25 MB the upload accepts (attachment.sanitizeUpload's default): until 13 Oct 2026 this was 20 MB, so a
  // 21-25 MB company profile was stored and then never read (2 of 29 real UAE profiles, ACCURACY_real_profiles.md).
  maxBytes: 25 * 1024 * 1024,
  // A SUPPLIER'S PROFILE OR CATALOGUE, UPLOADED STRAIGHT TO STORAGE, IS READ UP TO 100 MB (19 Oct 2026, sales_engineer).
  // Only the words-only supplier path asks for it (readDocument opts.maxBytes, _shared/supplier_docs_later.ts); every
  // other read keeps maxBytes. Above maxBytes pdf.js is handed the buffer itself, not a copy (doc_read/pdf.ts), which is
  // what keeps it inside the edge's 256 MB. Measured locally with deno, 19 Oct 2026, peak RSS of the whole background read
  // - streamed from a local server in the same process (supplier_docs_later.fetchStored), type gate, sha256
  // (malware.sha256Hex), readDocument - with the modules loaded at 57-58 MB; every page read, text in characters:
  //   A08 EMT prequalification  30.2 MB, 183 pages -> 129 MB, 68,674 characters
  //   B05 Al Shirawi brochure   84.9 MB,  22 pages -> 203 MB, 36,958 characters
  //   C05 BCG Arabic brochure   38.0 MB,  69 pages -> 132 MB, 57,302 characters
  // What the two changes saved on B05: with crypto.subtle.digest (which copies its input) the pipeline peaked at 255 MB;
  // pdf.js alone, handed a copy instead of the buffer, peaked at 265 MB. The in-process server's buffers are counted, so
  // these are upper bounds.
  maxPaperBytes: 100 * 1024 * 1024,
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
