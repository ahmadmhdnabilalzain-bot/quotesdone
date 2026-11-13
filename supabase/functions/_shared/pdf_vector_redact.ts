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
import { redactText, residualScan, runCovered, seedTerms, titleBlockBoxes, type Box } from './anonymise.ts';
import { supplierBoxes } from './supplier_copy.ts';
import { textLayerBoxes } from './drawing_identity_text.ts';
import { drawingLocation } from './drawing_location.ts';
import { drawingIdentityTerms } from './drawing_identity_gate.ts';
import { boqFromDrawingSet } from '../drawing_boq/drawing_set.ts';

const LATIN1 = new TextDecoder('latin1');
const latin1 = (s: string) => { const u = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i) & 0xff; return u; };
const SHOW = new Set(['Tj', 'TJ', "'", '"']);
/** Path construction and painting, clipping and the CTM: what "the geometry" is in a content stream. */
const PATH = new Set(['m', 'l', 'c', 'v', 'y', 're', 'h', 'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'n', 'W', 'W*', 'cm', 'q', 'Q', 'w']);
const EPS = 1e-6;
const inside = (b: Box, r: { x: number; y: number; w: number; h: number }) => r.x >= b.x - EPS && r.y >= b.y - EPS && r.x + r.w <= b.x + b.w + EPS && r.y + r.h <= b.y + b.h + EPS;
const touches = (b: Box, r: { x: number; y: number; w: number; h: number }) => r.x < b.x + b.w - EPS && r.x + r.w > b.x + EPS && r.y < b.y + b.h - EPS && r.y + r.h > b.y + EPS;
/** Logo-sized, as anonymise.titleBlockBoxes (d) sizes it: anything larger is drawing content, never cut. */
const LOGO_AREA = 0.03;

export type PdfRedactResult =
  | { ok: true; bytes: Uint8Array; removed_runs: number; removed_images: number; removed_paths: number; kept_runs: number; terms: string[] }
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

// PageLabels (every viewer shows them in its page box), Dests, the structure tree (alt text) and MarkInfo were released
// carrying the area and the firm (13 Nov 2026, independent review item 7); none of them draws anything.
const DROP_DOC = ['Metadata', 'OpenAction', 'AA', 'Names', 'AcroForm', 'PieceInfo', 'Outlines', 'Threads', 'SpiderInfo', 'URI', 'Perms', 'Legal', 'PageLabels', 'Dests', 'StructTreeRoot', 'MarkInfo', 'Lang', 'Collection'];
const DROP_PAGE = ['Annots', 'Metadata', 'PieceInfo', 'Thumb', 'AA', 'B', 'StructParents', 'Tabs', 'PresSteps'];

function strOf(v: unknown): string | null {
  if (v instanceof PDFString || v instanceof PDFHexString) return v.decodeText();
  return null;
}

/** Remove what the FILE says about itself and everything unreachable from the catalogue. */
function scrubFile(doc: PDFDocument, terms: string[], drawn: Map<string, Set<string>> = new Map()) {
  const ctx = doc.context;
  let layerNo = 0;
  const fonts = new Map<string, string>();
  const fontName = (v: unknown) => { const k = String((v as { asString?: () => string })?.asString?.() ?? v); if (!fonts.has(k)) fonts.set(k, `FONT${fonts.size + 1}`); return fonts.get(k)!; };
  // XObjects NO CONTENT DRAWS are dropped (review item 7: a Form in /Resources that nothing ever Do'd carried "OWNER AL
  // BARSHA SOUTH" into the released file). `drawn` names, per resources dictionary, the XObjects a Do of the page or of
  // a drawn form uses; every other name is removed from that dictionary, and reachability then deletes the object.
  // Every dictionary, direct ones inside others included (a page's /Resources and a font are usually direct).
  const dicts: PDFDict[] = [];
  const seenD = new Set<PDFDict>();
  const collect = (v: unknown) => {
    if (v instanceof PDFRawStream) { collect(v.dict); return; }
    if (v instanceof PDFDict) { if (seenD.has(v)) return; seenD.add(v); dicts.push(v); for (const [, x] of v.entries()) if (!(x instanceof PDFRef)) collect(x); return; }
    if (v instanceof PDFArray) for (const x of v.asArray()) if (!(x instanceof PDFRef)) collect(x);
  };
  for (const [, obj] of ctx.enumerateIndirectObjects()) collect(obj);
  const used = new Set([...drawn.values()].flatMap((x) => [...x]));
  for (const d of dicts) {
    const xo0 = d.get(PDFName.of('XObject'));
    const xo = xo0 instanceof PDFRef ? ctx.lookup(xo0) : xo0;
    if (xo instanceof PDFDict && drawn.size) for (const [k] of xo.entries()) if (!used.has(k.asString().replace(/^\//, ''))) xo.delete(k);
  }
  const cat = doc.catalog;
  for (const k of DROP_DOC) cat.delete(PDFName.of(k));
  for (const p of doc.getPages()) for (const k of DROP_PAGE) p.node.delete(PDFName.of(k));
  // Optional content (CAD layer) names: a layer can be named after the consultant or the project.
  for (const d of dicts) {
    d.delete(PDFName.of('Metadata'));
    // Layer names and font names are RENAMED NEUTRALLY, never redacted in place (review item 7: /BaseFont
    // "ZZDemoCoralPools-ArjanVilla" and an OCG named after the area were released; a word a rule does not know survives
    // a redaction, never a rename).
    if (d.get(PDFName.of('Type')) === PDFName.of('OCG') && d.get(PDFName.of('Name'))) d.set(PDFName.of('Name'), PDFHexString.fromText(`LAYER-${++layerNo}`));
    if (d.get(PDFName.of('Type')) === PDFName.of('Font') || d.get(PDFName.of('Type')) === PDFName.of('FontDescriptor')) {
      for (const k of ['BaseFont', 'FontName']) if (d.get(PDFName.of(k))) d.set(PDFName.of(k), PDFName.of(fontName(d.get(PDFName.of(k)))));
      d.delete(PDFName.of('FontFamily'));
    }
  }
  void terms;
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

export type CutPlan =
  | { ok: true; drop: Map<string, Set<number>>; dropImg: Map<string, Set<string>>; counts: { removedRuns: number; keptRuns: number; removedImages: number; removedPaths: number } }
  | { ok: false; held: string; detail?: string };

/**
 * Which operators to cut, per content stream: every identity run, every painted path and image wholly inside the
 * title area. FAIL CLOSED (review of #1056): an identity run whose operator the reader could not locate (no `at`)
 * HOLDS the whole file. It used to `return` out of that page's loop, which left the run in AND skipped the page's
 * logo and image cuts; the verifier would have caught the text, but not a skipped vector logo.
 */
export function cutPlan(vpages: { num: number; page: PdfPage }[], boxes: Box[][], areas: Box[][], pages: PdfPage[], terms: string[]): CutPlan {
  const drop = new Map<string, Set<number>>();       // stream key -> operator indexes to cut
  const dropImg = new Map<string, Set<string>>();    // stream key -> image names cut there
  const mark = (key: string, op: number) => { (drop.get(key) ?? drop.set(key, new Set()).get(key)!).add(op); };
  let removedRuns = 0, keptRuns = 0, removedImages = 0, removedPaths = 0;
  for (const [i, vp] of vpages.entries()) {
    const all = [...boxes[i], ...textLayerBoxes(pages, i).boxes];
    const keyOf = (at: string) => { const [s, op] = at.split(':'); return { key: s === 'p' ? 'p' + vp.num : s, op: Number(op) }; };
    for (const r of vp.page.runs as TextRun[]) {
      // A tilted run (a watermark) is under a staircase of boxes, none of which holds it whole (13 Nov 2026, finding L4).
      const identity = all.some((b) => !(b as { slice?: boolean }).slice && inside(b, r)) || (!!r.quad && runCovered(all, r)) || residualScan(r.text, terms).length > 0 || !!drawingLocation(r.text);
      if (!identity) { keptRuns++; continue; }
      if (!r.at) return { ok: false, held: 'identity_run_not_located', detail: `page ${i + 1}` };
      const k = keyOf(r.at); mark(k.key, k.op); removedRuns++;
    }
    // A VECTOR logo or stamp (28 Sep 2026): a painted path wholly inside the title strip is cut, operators and
    // operands; a clipping path never is. Everything outside the strip stays byte-identical (verifyPdfRedaction).
    for (const p of vp.page.paths ?? []) {
      if (p.clip || !areas[i].some((b) => inside(b, p))) continue;
      const k = keyOf(p.at + ':0');
      for (const op of p.ops) mark(k.key, op);
      removedPaths++;
    }
    // An image TOUCHING the title area is cut too, not only one wholly inside it (3 Nov 2026,
    // identity_never_leaks_before_reveal.mjs: 6 of 60 anonymised PDFs still showed a logo or a signature laid across
    // the strip's edge — 0.80..0.90 against a strip from 0.816). A logo-sized one is cut; a larger one straddling the
    // title block cannot be judged here and HOLDS the file.
    for (const im of vp.page.images ?? []) {
      if (!areas[i].some((b) => touches(b, im))) continue;
      if (!areas[i].some((b) => inside(b, im)) && im.w * im.h > LOGO_AREA) return { ok: false, held: 'image_straddles_title_block', detail: `page ${i + 1}` };
      if (!im.at || !im.name) return { ok: false, held: 'title_image_not_located', detail: `page ${i + 1}` };
      const k = keyOf(im.at); mark(k.key, k.op); removedImages++;
      (dropImg.get(k.key) ?? dropImg.set(k.key, new Set()).get(k.key)!).add(im.name);
    }
  }
  return { ok: true, drop, dropImg, counts: { removedRuns, keptRuns, removedImages, removedPaths } };
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

  const areas = titleAreas(tb, boxes);
  const plan = cutPlan(view.pages, boxes, areas, pages, terms);
  if (!plan.ok) return plan;
  const { drop, dropImg } = plan;
  const { removedRuns, keptRuns, removedImages, removedPaths } = plan.counts;

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
  // Every XObject name a kept Do uses, in the page contents and every form (after the cuts).
  const drawnNames = new Map<string, Set<string>>();
  const doNames = (src: string) => { const out = new Set<string>(); let last: string | undefined; for (const tk of tokens(src)) { if (tk.t === 'name') last = tk.v; else if (tk.t === 'op') { if (tk.v === 'Do' && last) out.add(last); last = undefined; } } return out; };
  for (const p of doc.getPages()) for (const r of contentRefs(p.node)) { const t = rawText(doc, r); if (t !== null) drawnNames.set('c' + r.toString(), doNames(t)); }
  for (const [num, src] of view.forms) drawnNames.set('f' + num, doNames(drop.has('f' + num) ? cutOperators(src, drop.get('f' + num)!).src : src));
  scrubFile(doc, terms, drawnNames);
  const out = await doc.save({ useObjectStreams: false, updateFieldAppearances: false });
  return { ok: true, bytes: out, removed_runs: removedRuns, removed_images: removedImages, removed_paths: removedPaths, kept_runs: keptRuns, terms };
}

/**
 * The reader and pdf-lib decode the same operators for these pages (13 Nov 2026, review item 4): the preview's boxes
 * come from the reader, so a page whose content the reader cuts short (an "endstream" inside a string, a filter only
 * one of them knows) is not boxed from a reading a viewer disagrees with. The file path already held on this; the
 * preview path now does too. `only` = [from, to).
 */
export async function readerAgrees(bytes: Uint8Array, only?: [number, number]): Promise<boolean> {
  try {
    const view = await pdfRedactionView(bytes);
    if (!view) return false;
    const doc = await PDFDocument.load(bytes, { updateMetadata: false });
    const pl = doc.getPages();
    if (pl.length !== view.pages.length) return false;
    const ws = (x: string) => x.replace(/\s+/g, ' ').trim();
    for (let i = only ? only[0] : 0; i < (only ? Math.min(only[1], pl.length) : pl.length); i++) {
      const texts = contentRefs(pl[i].node).map((r) => rawText(doc, r));
      if (texts.some((t) => t === null) || ws(texts.join('\n')) !== ws(view.pages[i].content)) return false;
    }
    return true;
  } catch (_e) { return false; }
}

// ── verification ────────────────────────────────────────────────────────────────────────────────────

/** The title area of each page: the title strip and the title-block boxes. */
export function titleAreas(tb: { strips: (Box | null)[]; regions?: Box[][] }, boxes: Box[][]): Box[][] {
  // Since 13 Nov 2026 the areas whose GRAPHICS go are titleBlockBoxes' regions (strip, block, revision table, key plan,
  // picture), not every run's box: a staircase along a 28-degree watermark would otherwise have cut Section A-A's own
  // linework out of the vector file (anonymity audit B, finding L4).
  if (tb.regions) return boxes.map((_b, i) => [...(tb.strips[i] ? [tb.strips[i]!] : []), ...(tb.regions![i] ?? [])]);
  return boxes.map((b, i) => [...(tb.strips[i] ? [tb.strips[i]!] : []), ...b]);
}

/** Every painted path OUTSIDE the title areas, as its exact source text, per page in drawing order (forms included
 *  where they are drawn). Equal before and after = the geometry a supplier measures is byte-identical. */
export function geometrySignature(view: NonNullable<Awaited<ReturnType<typeof pdfRedactionView>>>, areas: Box[][]): string[] {
  return view.pages.map((p, i) => (p.page.paths ?? []).filter((q) => q.clip || !(areas[i] ?? []).some((b) => inside(b, q))).map((q) => q.text).join('\n'));
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

/**
 * What a READER of the file can see or extract, decoded (13 Nov 2026, anonymity audit B finding G1): every dictionary
 * string (the document information, annotations, outlines, form fields, layer names, attachment names), every stream
 * that is not drawn ink (XMP metadata, an embedded file, JavaScript, an unknown stream) decoded, but NOT a page's or a
 * form's content stream and NOT a font program or its ToUnicode map. MEASURED: reading those raw read an embedded
 * font's licence URL ("dejavu.sourceforge.net") as a url/email and content-stream coordinates such as
 * "1129.323 17.00787" as a +971 phone, so the vector PDF of all three auditor sheets was held for identity no viewer
 * shows. The words a content stream DRAWS are checked as the reader decodes them (pdfPages runs, every angle), which is
 * the text a viewer shows and copies.
 */
export async function readerStrings(bytes: Uint8Array): Promise<string> {
  const doc = await PDFDocument.load(bytes, { updateMetadata: false });
  const ctx = doc.context;
  const skip = new Set<string>();
  const refOf = (v: unknown) => (v instanceof PDFRef ? v.toString() : null);
  for (const p of doc.getPages()) for (const r of contentRefs(p.node)) skip.add(r.toString());
  for (const [ref, o] of ctx.enumerateIndirectObjects()) {
    const d = o instanceof PDFDict ? o : o instanceof PDFRawStream ? o.dict : null;
    if (!d) continue;
    if (o instanceof PDFRawStream && (d.get(PDFName.of('Subtype')) === PDFName.of('Form') || d.get(PDFName.of('Subtype')) === PDFName.of('Image'))) skip.add(ref.toString());
    for (const k of ['FontFile', 'FontFile2', 'FontFile3', 'ToUnicode', 'CIDSet', 'CIDToGIDMap']) { const r = refOf(d.get(PDFName.of(k))); if (r) skip.add(r); }
  }
  const parts: string[] = [];
  // Names too (review item 7): a font, a layer, a destination or a resource can be NAMED after the owner or the area.
  const nm = (v: unknown) => (v instanceof PDFName ? v.asString().replace(/^\//, '').replace(/#([0-9A-Fa-f]{2})/g, (_m, h) => String.fromCharCode(parseInt(h, 16))).replace(/[_-]+/g, ' ') : null);
  const dictText = (d: PDFDict) => { for (const [k, v] of d.entries()) { const kn = nm(k); if (kn) parts.push(kn); const s = strOf(v) ?? nm(v); if (s !== null) parts.push(s); if (v instanceof PDFArray) for (const x of v.asArray()) { const t = strOf(x) ?? nm(x); if (t !== null) parts.push(t); } if (v instanceof PDFDict) dictText(v); } };
  for (const [ref, o] of ctx.enumerateIndirectObjects()) {
    if (o instanceof PDFRawStream) {
      dictText(o.dict);
      if (skip.has(ref.toString())) continue;
      try { parts.push(new TextDecoder('utf-8').decode(decodePDFRawStream(o).decode())); } catch { parts.push('<undecodable stream>'); }
    } else if (o instanceof PDFDict) dictText(o);
    else { const s = strOf(o); if (s !== null) parts.push(s); }
  }
  for (const [k, v] of Object.entries(ctx.trailerInfo)) if (v && k !== 'Root' && k !== 'Size') parts.push(String(v));
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
  const lb = await pdfPages(before), la = await pdfPages(after);
  const tb = titleBlockBoxes(await pdfPages(before, undefined, { layers: false }), [...new Set([...seeds, ...termsOf(lb, [])])]);
  const areas = titleAreas(tb, tb.boxes);
  const gb = vb ? geometrySignature(vb, areas) : [], ga = va ? geometrySignature(va, areas) : [];
  const nOps = (g: string[]) => g.reduce((n, s) => n + (s ? s.split('\n').length : 0), 0);
  // Pages first, then forms; a form's object number may change, its drawing order may not.
  if (gb.join('\f') !== ga.join('\f')) problems.push('geometry changed (a path outside the title block differs)');
  const out = (i: number, xs: { x1?: number; y1?: number; x2?: number; y2?: number; x?: number; y?: number; w?: number; h?: number }[] | undefined) =>
    JSON.stringify((xs ?? []).filter((q) => { const b = q.x1 !== undefined ? { x: q.x1, y: q.y1!, w: q.x2! - q.x1, h: q.y2! - q.y1! } : { x: q.x!, y: q.y!, w: q.w!, h: q.h! }; return !(areas[i] ?? []).some((a) => inside(a, b)); }));
  for (let i = 0; i < Math.min(lb.length, la.length); i++) {
    if (out(i, lb[i].lines) !== out(i, la[i].lines)) problems.push(`page ${i + 1}: measured lines outside the title block changed`);
    if (out(i, lb[i].marks) !== out(i, la[i].marks)) problems.push(`page ${i + 1}: marks outside the title block changed`);
  }
  // The counts are the DRAWING's: what the take-off reads from the text the redaction keeps. MEASURED 13 Nov 2026 on
  // the auditor's B1: the original's take-off was one line, "Demolition: P-1 — Pump", made because the consultant's
  // name "ZZ DEMO CORAL POOLS" read as a demolition sheet; once that name was cut the line could never come back, and
  // the file was held for a count the drawing never had. Identity runs (the same rule cutPlan applies) are set aside
  // before the original is counted.
  const termsB = [...new Set([...seeds, ...termsOf(lb, [])])];
  const allB = tb.boxes.map((b, i) => [...b, ...textLayerBoxes(lb, i).boxes]);
  const contentOnly = lb.map((p, i) => ({ ...p, runs: p.runs.filter((r) => !((allB[i] ?? []).some((b) => !(b as { slice?: boolean }).slice && inside(b, r)) || (!!r.quad && runCovered(allB[i] ?? [], r)) || residualScan(r.text, termsB).length > 0)) }));
  const cb = qtyMap(boqFromDrawingSet(contentOnly, '')), ca = qtyMap(boqFromDrawingSet(la, ''));
  for (const [d, q] of cb) if (ca.get(d) !== q) problems.push(`count "${d}": ${q} -> ${ca.get(d) ?? 'missing'}`);
  for (const [d, q] of ca) if (!cb.has(d)) problems.push(`count "${d}" appeared after redaction (${q})`);
  // RUN BY RUN, LINE BY LINE (review item 11): the pieces were joined with "\n" and the address pattern then spanned
  // "C40\nTOWER CRANE\nSTREET LIGHT" and held a clean sheet. Each string a reader can find is judged on its own.
  const pieces = [...(await readerStrings(after).catch(() => '<unreadable>')).split('\n'), ...linesFromRuns(la).split('\n'), ...la.flatMap((p) => p.runs.map((r) => r.text))].map((x) => x.trim()).filter(Boolean);
  const terms = [...new Set([...seeds, ...termsOf(lb, [])])];
  const lowerAll = pieces.join('\n').toLowerCase();
  const left = [...new Set([...pieces.flatMap((x) => residualScan(x, terms)), ...pieces.map(drawingLocation).filter((x): x is string => !!x).map((x) => 'place:' + x),
    ...identity.filter((s) => lowerAll.includes(s.toLowerCase())).map((s) => 'literal:' + s)])];
  // Every byte the file carries, font programs and content streams included, holds none of the TERMS (the customer's
  // seeds and what the sheet's own labels name): readerStrings judges shapes on what a reader sees; this judges names.
  const raw = (await fileStrings(after).catch(() => '')).toLowerCase().replace(/[^a-z0-9\u0600-\u06ff]+/g, '');
  for (const t of [...seeds, ...terms.filter((x) => /\s/.test(x))]) { const k = t.toLowerCase().replace(/[^a-z0-9\u0600-\u06ff]+/g, ''); if (k.length >= 6 && !/^\d+$/.test(k) && raw.includes(k)) left.push('bytes:' + t.slice(0, 30)); }
  if (left.length) problems.push('identity left: ' + left.join('; '));
  return { ok: problems.length === 0, problems, pages: [pb, pa], geometry_ops: [nOps(gb), nOps(ga)], counts: { before: Object.fromEntries(cb), after: Object.fromEntries(ca) }, identity_left: left };
}
