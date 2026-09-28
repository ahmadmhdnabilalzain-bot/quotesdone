// pdf_vector_redact — a VECTOR PDF drawing, anonymised as a PDF: the identifying text is cut out of the file,
// the geometry is not touched, and the result is re-read to prove both (28 Sep 2026, sales_engineer; founder
// ledger items 30, 31, 32, 580, 703: "removes every contact detail and every project-identifying detail
// WITHOUT damaging the drawing content", and suppliers receive the anonymised drawing plus the BOQ).
//
// MEASURED BEFORE THIS FILE: every PDF drawing reached a supplier only as drawing_redact's JPEG — black boxes
// painted on a 2600 px raster of the page. The vector sheet (zoomable linework, scale, measurable lengths) was
// never sent, and nothing proved that the picture still carried the counts the BOQ states.
//
// WHAT IT DOES — deterministic, no model:
//  1. WHICH TEXT. The same decision drawing_redact paints: anonymise.titleBlockBoxes (the title strip) through
//     supplier_copy.supplierBoxes (held unless confident), plus drawing_identity_text.textLayerBoxes (e-mails,
//     phones, firms and "Client:"-style labels with their values, anywhere on the sheet). A run fully inside a
//     box is identity; so is any run anonymise.residualScan still finds a party in (customer seeds + the
//     file's own label values, drawing_identity_gate.drawingIdentityTerms).
//  2. CUT, NOT COVER. Each identity run's show operator (Tj, TJ, ', ") is removed from the content stream it
//     was drawn from — the page's, or a Form XObject's — by the operator's own offsets (pdf_text_positions
//     reports them as `at`). A black box over live text leaves the text selectable; a cut leaves nothing.
//     A raster image lying wholly inside a title-block box (a logo) has its `Do` cut and the image dropped.
//  3. THE FILE ITSELF. /Info, XMP /Metadata (document, page and object), annotations, the document outline,
//     /Names (embedded files, JavaScript), /OpenAction, /AA, /AcroForm, /PieceInfo and thumbnails are removed;
//     optional-content (CAD layer) names go through redactText. Every object no longer reachable from the
//     catalogue is deleted, so the old content streams do not ride along unreferenced.
//  4. VERIFY (verifyPdfRedaction): the output OPENS (pdf-lib and our own reader, same page count); the
//     GEOMETRY is unchanged (every path operator with its operands, page by page and form by form, equal
//     before and after; the reader's measured lines, CAD-layer segments and closed marks equal); the COUNTS are
//     unchanged (drawing_set's take-off, line by line and quantity by quantity, equal before and after); and NO
//     IDENTIFIER is left anywhere in the file — every decoded stream and every dictionary string is re-read.
//     Any failure is a HOLD: the caller must not send the file.
//
// WHAT IT DOES NOT DO: a scanned sheet (no text layer) is held here — scan_redact.ts paints its pixels; text
// drawn as vector strokes (SHX) has no text layer and is not seen (cad_render.ts owns stroke text for CAD); an
// encrypted PDF is held. A vector logo (paths, not an image) is geometry and is kept — ponytail: telling a logo
// from linework needs the title strip's paths classified; add it when a real sheet shows a vector logo.
// deno-lint-ignore-file no-explicit-any
import { PDFArray, PDFDict, PDFDocument, PDFName, PDFRawStream, PDFRef, PDFString, PDFHexString, decodePDFRawStream } from 'https://esm.sh/pdf-lib@1.17.1';
import { linesFromRuns, pdfPages, pdfRedactionView, tokens, type PdfPage, type TextRun } from './pdf_text_positions.ts';
import { redactText, residualScan, seedTerms, titleBlockBoxes, type Box } from './anonymise.ts';
import { supplierBoxes } from './supplier_copy.ts';
import { textLayerBoxes } from './drawing_identity_text.ts';
import { drawingIdentityTerms } from './drawing_identity_gate.ts';
import { boqFromDrawingSet } from '../drawing_boq/drawing_set.ts';

const LATIN1 = new TextDecoder('latin1');
const latin1 = (s: string) => { const u = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i) & 0xff; return u; };
const SHOW = new Set(['Tj', 'TJ', "'", '"']);
/** Path construction and painting, clipping and the CTM: what "the geometry" is in a content stream. */
const PATH = new Set(['m', 'l', 'c', 'v', 'y', 're', 'h', 'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'n', 'W', 'W*', 'cm', 'q', 'Q', 'w']);
const EPS = 1e-6;
const inside = (b: Box, r: { x: number; y: number; w: number; h: number }) => r.x >= b.x - EPS && r.y >= b.y - EPS && r.x + r.w <= b.x + b.w + EPS && r.y + r.h <= b.y + b.h + EPS;

export type PdfRedactResult =
  | { ok: true; bytes: Uint8Array; removed_runs: number; removed_images: number; kept_runs: number; terms: string[] }
  | { ok: false; held: string; detail?: string };

/** The identity terms: the customer's seeds plus what the sheet's own labels name. */
function termsOf(pages: PdfPage[], seeds: string[]): string[] {
  return [...new Set([...seeds, ...seedTerms({ extra: drawingIdentityTerms(linesFromRuns(pages)) })])];
}

/** Cut the operators at `drop` (operator indexes) out of a content stream, operands included. */
export function cutOperators(src: string, drop: Set<number>): { src: string; names: Set<string> } {
  let out = '', last = 0, opn = 0, start = -1;
  const left = new Set<string>();                    // names still used by a kept Do
  let pendingName: string | undefined;
  for (const tk of tokens(src)) {
    if (tk.t !== 'op') { if (start < 0) start = tk.p; if (tk.t === 'name') pendingName = tk.v; continue; }
    opn++;
    const from = start >= 0 ? start : tk.p;
    if (drop.has(opn)) {
      // ' and " also move to the next line: keep the move, lose the text.
      out += src.slice(last, from) + (tk.v === "'" || tk.v === '"' ? 'T*' : '');
      last = tk.e;
    } else if (tk.v === 'Do' && pendingName !== undefined) left.add(pendingName);
    start = -1; pendingName = undefined;
  }
  return { src: out + src.slice(last), names: left };
}

function rawText(doc: PDFDocument, ref: PDFRef): string | null {
  const o = doc.context.lookup(ref);
  if (!(o instanceof PDFRawStream)) return null;
  try { return LATIN1.decode(decodePDFRawStream(o).decode()); } catch { return null; }
}
function contentRefs(page: PDFDict): PDFRef[] {
  const c = page.get(PDFName.of('Contents'));
  if (c instanceof PDFRef) return [c];
  if (c instanceof PDFArray) return c.asArray().filter((x): x is PDFRef => x instanceof PDFRef);
  return [];
}
/** Replace a stream object's bytes, keeping its dictionary (a Form's /BBox, /Resources, /Matrix). */
function replaceStream(doc: PDFDocument, ref: PDFRef, src: string) {
  const old = doc.context.lookup(ref) as PDFRawStream;
  const s = doc.context.flateStream(latin1(src));
  for (const [k, v] of old.dict.entries()) if (!['/Filter', '/DecodeParms', '/Length', '/DL'].includes(k.asString())) s.dict.set(k, v);
  doc.context.assign(ref, s);
}

const DROP_DOC = ['Metadata', 'OpenAction', 'AA', 'Names', 'AcroForm', 'PieceInfo', 'Outlines', 'Threads', 'SpiderInfo', 'URI', 'Perms', 'Legal'];
const DROP_PAGE = ['Annots', 'Metadata', 'PieceInfo', 'Thumb', 'AA', 'B'];

function strOf(v: unknown): string | null {
  if (v instanceof PDFString || v instanceof PDFHexString) return v.decodeText();
  return null;
}

/** Remove what the FILE says about itself and everything unreachable from the catalogue. */
function scrubFile(doc: PDFDocument, terms: string[]) {
  const ctx = doc.context;
  ctx.trailerInfo.Info = undefined;
  ctx.trailerInfo.ID = undefined;
  const cat = doc.catalog;
  for (const k of DROP_DOC) cat.delete(PDFName.of(k));
  for (const p of doc.getPages()) for (const k of DROP_PAGE) p.node.delete(PDFName.of(k));
  // Optional content (CAD layer) names: a layer can be named after the consultant or the project.
  for (const [, obj] of ctx.enumerateIndirectObjects()) {
    const d = obj instanceof PDFDict ? obj : obj instanceof PDFRawStream ? obj.dict : null;
    if (!d) continue;
    d.delete(PDFName.of('Metadata'));
    if (d.get(PDFName.of('Type')) === PDFName.of('OCG')) {
      const nm = strOf(d.get(PDFName.of('Name')));
      if (nm !== null) d.set(PDFName.of('Name'), PDFHexString.fromText(redactText(nm, terms).text.replace(/█+/g, '').replace(/\s{2,}/g, ' ').trim() || 'LAYER'));
    }
  }
  // Reachability from the catalogue: an old content stream, the /Info dictionary or a dropped logo is no
  // longer referenced, and pdf-lib would otherwise write it out anyway.
  const seen = new Set<string>();
  const walk = (v: unknown) => {
    if (v instanceof PDFRef) {
      const k = v.toString(); if (seen.has(k)) return; seen.add(k);
      walk(ctx.lookup(v)); return;
    }
    if (v instanceof PDFRawStream) { walk(v.dict); return; }
    if (v instanceof PDFDict) { for (const [, x] of v.entries()) walk(x); return; }
    if (v instanceof PDFArray) { for (const x of v.asArray()) walk(x); }
  };
  walk(ctx.trailerInfo.Root);
  for (const [ref] of ctx.enumerateIndirectObjects()) if (!seen.has(ref.toString())) ctx.delete(ref);
}

/** Drop an XObject name from a resources dictionary (direct or indirect). */
function dropXObject(doc: PDFDocument, res: unknown, name: string) {
  const r = res instanceof PDFRef ? doc.context.lookup(res) : res;
  if (!(r instanceof PDFDict)) return;
  const x0 = r.get(PDFName.of('XObject'));
  const x = x0 instanceof PDFRef ? doc.context.lookup(x0) : x0;
  if (x instanceof PDFDict) x.delete(PDFName.of(name));
}

/**
 * A vector PDF drawing with every identifying run cut out and the file's own metadata removed. Fails closed:
 * `ok:false` whenever the sheet cannot be judged (no text layer, title block not confident, a content stream
 * our reader and pdf-lib do not decode identically, an operator ceiling hit, encryption).
 */
export async function redactPdfVector(bytes: Uint8Array, seeds: string[]): Promise<PdfRedactResult> {
  const view = await pdfRedactionView(bytes);
  if (!view || !view.pages.length) return { ok: false, held: 'pdf_unreadable' };
  if (/\/Encrypt\b/.test(LATIN1.decode(bytes.subarray(Math.max(0, bytes.length - 4096)))) || /\/Encrypt\b/.test(LATIN1.decode(bytes.subarray(0, 4096)))) return { ok: false, held: 'pdf_encrypted' };
  const pages = view.pages.map((p) => p.page);
  if (pages.some((p) => p.truncated)) return { ok: false, held: 'pdf_too_many_operators' };
  if (pages.some((p) => !p.runs.length)) return { ok: false, held: 'no_text_layer', detail: 'a page has no text layer (scanned): scan_redact paints it' };
  const terms = termsOf(pages, seeds);
  const tb = titleBlockBoxes(await pdfPages(bytes, undefined, { layers: false }), terms);
  const boxes = supplierBoxes(tb, null, pages.length);
  if (!boxes) return { ok: false, held: 'title_block_not_confident', detail: `confidence ${tb.confidence}; residual ${tb.residual.join('; ')}`.slice(0, 200) };

  const drop = new Map<string, Set<number>>();       // stream key -> operator indexes to cut
  const dropImg = new Map<string, Set<string>>();    // stream key -> image names cut there
  const mark = (key: string, op: number) => { (drop.get(key) ?? drop.set(key, new Set()).get(key)!).add(op); };
  let removedRuns = 0, keptRuns = 0, removedImages = 0;
  view.pages.forEach((vp, i) => {
    const all = [...boxes[i], ...textLayerBoxes(pages, i).boxes];
    const keyOf = (at: string) => { const [s, op] = at.split(':'); return { key: s === 'p' ? 'p' + vp.num : s, op: Number(op) }; };
    for (const r of vp.page.runs as TextRun[]) {
      const identity = all.some((b) => inside(b, r)) || residualScan(r.text, terms).length > 0;
      if (!identity) { keptRuns++; continue; }
      if (!r.at) return;
      const k = keyOf(r.at); mark(k.key, k.op); removedRuns++;
    }
    for (const im of vp.page.images ?? []) {
      if (!im.at || !im.name || !boxes[i].some((b) => inside(b, im))) continue;
      const k = keyOf(im.at); mark(k.key, k.op); removedImages++;
      (dropImg.get(k.key) ?? dropImg.set(k.key, new Set()).get(k.key)!).add(im.name);
    }
  });

  const doc = await PDFDocument.load(bytes, { updateMetadata: false });
  const pl = doc.getPages();
  if (pl.length !== view.pages.length) return { ok: false, held: 'page_tree_mismatch' };
  for (let i = 0; i < pl.length; i++) {
    const vp = view.pages[i];
    if (pl[i].ref.objectNumber !== vp.num) return { ok: false, held: 'page_tree_mismatch' };
    const refs = contentRefs(pl[i].node);
    const texts = refs.map((r) => rawText(doc, r));
    if (texts.some((t) => t === null)) return { ok: false, held: 'content_stream_unreadable' };
    // Whitespace aside (pdf-lib keeps the EOL before `endstream`, the reader honours /Length), both must have
    // decoded the same operators, or a stream the reader skipped would be dropped by the rewrite.
    const ws = (s: string) => s.replace(/\s+/g, ' ').trim();
    if (ws(texts.join('\n')) !== ws(vp.content)) return { ok: false, held: 'content_stream_unreadable', detail: 'pdf-lib and the reader decode the page differently' };
    const src = vp.content;
    const d = drop.get('p' + vp.num);
    if (!d) continue;
    const cut = cutOperators(src, d);
    const s = doc.context.flateStream(latin1(cut.src));
    pl[i].node.set(PDFName.of('Contents'), doc.context.register(s));
    for (const n of dropImg.get('p' + vp.num) ?? []) if (!cut.names.has(n)) dropXObject(doc, pl[i].node.Resources(), n);
  }
  for (const [key, d] of drop) {
    if (!key.startsWith('f')) continue;
    const num = Number(key.slice(1));
    const src = view.forms.get(num);
    if (src === undefined) return { ok: false, held: 'form_unreadable' };
    const ref = PDFRef.of(num);
    const cut = cutOperators(src, d);
    const res = (doc.context.lookup(ref) as PDFRawStream).dict.get(PDFName.of('Resources'));
    replaceStream(doc, ref, cut.src);
    for (const n of dropImg.get(key) ?? []) if (!cut.names.has(n)) dropXObject(doc, res, n);
  }
  scrubFile(doc, terms);
  const out = await doc.save({ useObjectStreams: false, updateFieldAppearances: false });
  return { ok: true, bytes: out, removed_runs: removedRuns, removed_images: removedImages, kept_runs: keptRuns, terms };
}

// ── verification ────────────────────────────────────────────────────────────────────────────────────

/** Every path operator with its operands, in drawing order, per page and per form (by object number). */
export function geometrySignature(view: NonNullable<Awaited<ReturnType<typeof pdfRedactionView>>>): string[] {
  const sig = (src: string) => {
    const out: string[] = []; let nums: string[] = [];
    for (const tk of tokens(src)) {
      if (tk.t === 'num') { nums.push(tk.v); continue; }
      if (tk.t !== 'op') { nums = []; continue; }
      if (PATH.has(tk.v)) out.push(nums.join(' ') + ' ' + tk.v);
      nums = [];
    }
    return out.join('\n');
  };
  const forms = [...view.forms.entries()].sort((a, b) => a[0] - b[0]).map(([, s]) => sig(s));
  return [...view.pages.map((p) => sig(p.content)), ...forms];
}

/** Every string the file carries, decoded: streams (inflated), dictionary strings, names. */
export async function fileStrings(bytes: Uint8Array): Promise<string> {
  const doc = await PDFDocument.load(bytes, { updateMetadata: false });
  const parts: string[] = [];
  const dictText = (d: PDFDict) => { for (const [k, v] of d.entries()) { parts.push(k.asString()); const s = strOf(v); if (s !== null) parts.push(s); if (v instanceof PDFName) parts.push(v.asString()); if (v instanceof PDFArray) for (const x of v.asArray()) { const t = strOf(x); if (t !== null) parts.push(t); } } };
  for (const [, o] of doc.context.enumerateIndirectObjects()) {
    if (o instanceof PDFRawStream) {
      dictText(o.dict);
      if (/Image/.test(String(o.dict.get(PDFName.of('Subtype'))))) continue;   // pixels are not text
      try { parts.push(LATIN1.decode(decodePDFRawStream(o).decode())); } catch { parts.push('<undecodable stream>'); }
    } else if (o instanceof PDFDict) dictText(o);
    else { const s = strOf(o); if (s !== null) parts.push(s); }
  }
  for (const [k, v] of Object.entries(doc.context.trailerInfo)) if (v) parts.push(k + ' ' + String(v));
  return parts.join('\n');
}

const qtyMap = (set: any) => {
  const m = new Map<string, number>();
  for (const l of (set?.boq ?? [])) m.set(String(l.description), Number(l.qty));
  return m;
};

export type PdfVerify = {
  ok: boolean; problems: string[];
  pages: [number, number]; geometry_ops: [number, number]; counts: { before: Record<string, number>; after: Record<string, number> };
  identity_left: string[];
};

/** Prove a redacted PDF: it opens, its geometry and its take-off counts are the original's, and no identity is left. */
export async function verifyPdfRedaction(before: Uint8Array, after: Uint8Array, seeds: string[], identity: string[] = []): Promise<PdfVerify> {
  const problems: string[] = [];
  const vb = await pdfRedactionView(before), va = await pdfRedactionView(after);
  try { await PDFDocument.load(after); } catch (e) { problems.push('does not open in pdf-lib: ' + String((e as Error)?.message || e).slice(0, 120)); }
  if (!va) problems.push('does not open in the reader');
  const pb = vb?.pages.length ?? 0, pa = va?.pages.length ?? 0;
  if (pb !== pa) problems.push(`page count ${pb} -> ${pa}`);
  const gb = vb ? geometrySignature(vb) : [], ga = va ? geometrySignature(va) : [];
  const nOps = (g: string[]) => g.reduce((n, s) => n + (s ? s.split('\n').length : 0), 0);
  // Pages first, then forms; a form's object number may change, its drawing order may not.
  if (gb.join('\f') !== ga.join('\f')) problems.push('geometry changed (path operators differ)');
  const lb = await pdfPages(before), la = await pdfPages(after);
  for (let i = 0; i < Math.min(lb.length, la.length); i++) {
    for (const k of ['lines', 'layers', 'marks'] as const) {
      const a = JSON.stringify(lb[i][k] ?? null), b = JSON.stringify(la[i][k] ?? null);
      if (k === 'layers') { if (JSON.stringify(Object.values(lb[i].layers ?? {})) !== JSON.stringify(Object.values(la[i].layers ?? {}))) problems.push(`page ${i + 1}: CAD layer segments changed`); }
      else if (a !== b) problems.push(`page ${i + 1}: measured ${k} changed`);
    }
  }
  const cb = qtyMap(boqFromDrawingSet(lb, '')), ca = qtyMap(boqFromDrawingSet(la, ''));
  for (const [d, q] of cb) if (ca.get(d) !== q) problems.push(`count "${d}": ${q} -> ${ca.get(d) ?? 'missing'}`);
  for (const [d, q] of ca) if (!cb.has(d)) problems.push(`count "${d}" appeared after redaction (${q})`);
  const text = (await fileStrings(after).catch(() => '')) + '\n' + linesFromRuns(la);
  const terms = [...new Set([...seeds, ...termsOf(lb, [])])];
  const left = [...new Set([...residualScan(text, terms), ...identity.filter((s) => text.toLowerCase().includes(s.toLowerCase())).map((s) => 'literal:' + s)])];
  if (left.length) problems.push('identity left: ' + left.join('; '));
  return { ok: problems.length === 0, problems, pages: [pb, pa], geometry_ops: [nOps(gb), nOps(ga)], counts: { before: Object.fromEntries(cb), after: Object.fromEntries(ca) }, identity_left: left };
}
