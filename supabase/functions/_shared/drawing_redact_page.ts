// drawing_redact_page — the deterministic steps of drawing_redact, lifted out of its Deno.serve handler so a
// test can run the production code on a synthetic drawing (24 Sep 2026, sales_engineer; founder
// instructions 580 and 703: "removing the project details from the drawings perfectly without affecting
// them" — checked, not assumed).
//
// Two ways a page reaches a supplier with no model involved:
//   serverBoxedPage — a PDF page the SERVER can read (a text layer): the portal's raster of it, painted with
//     the server's own title-block boxes (anonymise.titleBlockBoxes via supplier_copy.supplierBoxes, sent as
//     manual_boxes by customer_api) plus every identity run the text layer locates (drawing_identity_text).
//     A page the server cannot read (a scan, a photo) is HELD whatever boxes came with it.
//   cadPages — a CAD original (DXF, binary DXF, DWG): drawn from its entities with the identity left out
//     (cad_render.ts). A DWG past the edge's ceiling, or a drawing too dense to draw inside the CPU cap, is
//     HELD, never half-drawn.
// Neither publishes anything by itself: drawing_redact uploads, records the run, and only then hands paths back.
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import type { PdfPage } from './pdf_text_positions.ts';
import { textLayerBoxes } from './drawing_identity_text.ts';
import { supplierPageReadable } from './supplier_copy.ts';
import { renderCadForSupplier } from './cad_render.ts';
import { readDwg } from './doc_read/dwg.ts';
import { TILING, markCells } from './drawing_pixel_gate.ts';

export type Box = { x: number; y: number; w: number; h: number };

// 21 Sep 2026: 1600 px across a 36x24 in sheet is 44 dpi — a 1/8-in note is 7 px tall and a supplier
// cannot read the tags this whole change exists to keep (founder instruction 580: the drawing content
// must survive). The portal already sends 2600 px (pdfRaster MAX_EDGE); it is now kept, not shrunk.
export const MAXW = 2600;
// The server's own boxes (anonymise.titleBlockBoxes) are computed from text positions and already padded; a
// 3% pad on them cut 1 in off the drawing beside every title block (measured on the mechanical set: the
// notes column and the VAV schedule lost their right edge). They get SERVER_MARGIN.
export const SERVER_MARGIN = 0.004;

export const stripB64 = (s: string) => String(s).replace(/^data:[^;]+;base64,/, '');
export function b64ToBytes(b64: string): Uint8Array { const bin = atob(stripB64(b64)); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return a; }
// Chunked so a full-page JPEG cannot blow the argument limit.
export function bytesToB64(u8: Uint8Array): string { let out = ''; const CH = 0x8000; for (let i = 0; i < u8.length; i += CH) out += String.fromCharCode.apply(null, Array.from(u8.subarray(i, i + CH))); return btoa(out); }

/** Solid black over each normalised box, padded by `pad`, clamped to the image. */
export function paintBoxes(target: Image, gs: Box[], pad = SERVER_MARGIN): void {
  const W2 = target.width, H2 = target.height;
  for (const g of gs) {
    let x = Math.floor((g.x - pad) * W2), y = Math.floor((g.y - pad) * H2);
    let w = Math.ceil((g.w + 2 * pad) * W2), h = Math.ceil((g.h + 2 * pad) * H2);
    x = Math.max(0, Math.min(x, W2 - 1)); y = Math.max(0, Math.min(y, H2 - 1));
    w = Math.max(1, Math.min(w, W2 - x)); h = Math.max(1, Math.min(h, H2 - y));
    target.composite(new Image(w, h).fill(0x000000ff), x, y);
  }
}

/**
 * The verifier's retry, as its own unit of pixel work (it_engineer, 2 Nov 2026). drawing_redact's model path used to
 * decode a page, encode it, then paint the retry's boxes and encode it AGAIN in the same worker; on 1 Nov 4 of 4 such
 * calls died "CPU Time exceeded" (HTTP 546, 5.8-14.4 s wall) and no drawing_redaction_runs row was ever written. The
 * retry now runs in a fresh worker (mode 'repaint'): it decodes the already-redacted JPEG, paints `regions` and
 * encodes once, so no worker does more than one decode and one encode of a page.
 */
export async function repaintJpeg(jpg: Uint8Array, regions: Box[], pad: number, quality = 82): Promise<Uint8Array> {
  const img = await Image.decode(jpg) as Image;
  paintBoxes(img, regions, pad);
  return await img.encodeJPEG(quality);
}

/** One view the pixel gate shows the model (drawing_pixel_gate.planTiles): `tile` cut from the page and scaled to
 *  tile.outW x tile.outH (UP when the page was drawn smaller), one decode and one encode in its own worker. */
export async function tileJpeg(jpg: Uint8Array, tile: { x: number; y: number; w: number; h: number; outW: number; outH: number }, quality = 85, mark?: string): Promise<Uint8Array> {
  let img = await Image.decode(jpg) as Image;
  const x = Math.max(0, Math.min(img.width - 1, Math.floor(tile.x * img.width))), y = Math.max(0, Math.min(img.height - 1, Math.floor(tile.y * img.height)));
  const w = Math.max(1, Math.min(img.width - x, Math.ceil(tile.w * img.width))), h = Math.max(1, Math.min(img.height - y, Math.ceil(tile.h * img.height)));
  if (x || y || w !== img.width || h !== img.height) img = img.crop(x, y, w, h);
  const ow = Math.max(1, Math.round(tile.outW || w)), oh = Math.max(1, Math.round(tile.outH || h));
  if (ow !== img.width || oh !== img.height) img = img.resize(ow, oh);
  if (mark) img = withMarkBand(img, mark);
  return await img.encodeJPEG(quality);
}

// ── THE READING MARK (round 3, 13 Nov 2026, sales_engineer; brief f3_finish: an ALWAYS-CLEAN model, one that answers
// "clean" without looking, published every page the code floor left identity on - the reviewer's v01 and v12 - because
// nothing showed whether a tile had been read). Every view the pixel gate shows the model carries, in a white band BELOW
// the drawing (never over it), a number of drawing_pixel_gate.MARK_DIGITS digits the gate drew at random for that one
// call, in drawing_pixel_gate.MARK_FONT at MARK_SCALE: 7 x 2 = 14 px tall, above the 12 px the tiling promises for 6 pt text. The model
// must copy it into its answer ("mark" in PIXEL_VERIFY_SYS); an answer without the right number is no reading and the
// page is HELD. A model that answers without reading the tile cannot know the number.
/** `img` with a white band of TILING.markPx under it carrying `mark` (drawing_pixel_gate.markCells: digits only). */
export function withMarkBand(img: Image, mark: string): Image {
  const out = new Image(img.width, img.height + TILING.markPx).fill(0xffffffff);
  out.composite(img, 0, 0);
  for (const c of markCells(mark, img.height)) out.drawBox(c.x + 1, c.y + 1, c.w, c.h, 0x000000ff);   // drawBox is 1-based
  return out;
}

/** Where an image shows ink, on an n x n grid (row-major): a cell with more than `minDark` of its pixels dark. Decode
 *  only (released_file_pages.inkAgrees compares it with the file's own reading). */
export async function inkCells(jpg: Uint8Array, n: number, minDark = 0.002): Promise<{ cells: boolean[]; w: number; h: number }> {
  const img = await Image.decode(jpg) as Image;
  const W = img.width, H = img.height, bm = img.bitmap, dark = new Array(n * n).fill(0), all = new Array(n * n).fill(0);
  const step = Math.max(1, Math.floor(Math.min(W, H) / 800));      // a 2600 px page is sampled every 2-3 px
  for (let y = 0; y < H; y += step) { const r = Math.min(n - 1, Math.floor(y * n / H)); for (let x = 0; x < W; x += step) {
    const k = (y * W + x) * 4, c = r * n + Math.min(n - 1, Math.floor(x * n / W));
    all[c]++; if (bm[k] * 0.3 + bm[k + 1] * 0.59 + bm[k + 2] * 0.11 < 160) dark[c]++;
  } }
  return { cells: dark.map((d, i) => all[i] > 0 && d / all[i] > minDark), w: W, h: H };
}

/** Boxes arrive as JSON: clamp to 0..1, drop empty ones, at most MAX_BOXES. Boxes only ever ADD black, so the cap
 *  guards memory, not trust. It was 60 until 13 Nov 2026: the server's own boxes now include a staircase of up to 160
 *  slices along a tilted run (anonymise.runCover), and a cap that silently dropped the rest would have published the
 *  tail of a watermark or a key plan's box. */
export const MAX_BOXES = 1200;
export function cleanBoxes(mb: unknown): Box[] | null {
  if (!Array.isArray(mb)) return null;
  const c = (v: unknown) => Math.max(0, Math.min(1, Number(v) || 0));
  return mb.slice(0, MAX_BOXES).map((g: any) => ({ x: c(g?.x), y: c(g?.y), w: c(g?.w), h: c(g?.h) })).filter((g) => g.w > 0 && g.h > 0);
}

/**
 * ANONYMITY 27 Jul 2026. A redacted page is handed to matched suppliers as a SIGNED URL, and a signed URL
 * contains the object path. The caller's prefix selects ONLY the namespace (its first segment); the rest
 * is an opaque random UUID not derivable from the customer, the inquiry, the file name or the time.
 */
export function supplierPagePrefix(callerPrefix: unknown): string {
  const ns = (String(callerPrefix || 'redacted').split('/')[0] || 'redacted').replace(/[^A-Za-z0-9._-]/g, '_');
  return `${ns}/${crypto.randomUUID()}/page`;
}

// painted: every box blackened on the page, page fractions, with the margin it was painted at (drawing_code_floor.unreadTextHold).
export type PageOut = { ok: true; jpg: Uint8Array; image: Image; detail: Record<string, unknown>; painted?: Box[] } | { ok: false; skipped: string };

/** Boxes painted at one margin; a page's paint is a list of these, painted in order. */
export type PaintGroup = { boxes: Box[]; pad: number };

/**
 * ONE DECODE, THE BOXES, ONE ENCODE (17 Nov 2026, sales_engineer). The pixel half of a page's redaction, as its own unit of
 * work: drawing_redact runs it in a worker of its own (mode 'paint'), as it already ran the tiles and the repaint.
 * MEASURED on the 8-sheet ZZ DEMO set (2600 x 1733 px, local deno, cold): decode 460 ms, the boxes 8 ms, encode 300 ms.
 * In the worker that also read the PDF and asked the gate's 25 views that was ~1.6 s of CPU, and on the edge every
 * sheet died "CPU Time exceeded" (HTTP 546 at 2,205-2,551 ms; scripts/e2e/drawing_reaches_suppliers.mjs, 17 Nov 14:44
 * UTC): no page reached a supplier. Same steps, same order, same quality as before: the bytes are identical
 * (drawing_redact/a_sheet_is_redacted_within_the_edge_budget.check.ts).
 */
export async function paintedJpeg(raster: Uint8Array, groups: PaintGroup[], quality = 82): Promise<{ jpg: Uint8Array; image: Image }> {
  let img = await Image.decode(raster) as Image;
  if (img.width > MAXW) img = img.resize(MAXW, Image.RESIZE_AUTO);
  for (const g of groups) paintBoxes(img, g.boxes, g.pad);
  // Re-encoded from pixels: no text layer, no annotation, no /Info metadata and no EXIF survive into it.
  return { jpg: await img.encodeJPEG(quality), image: img };
}

export type BoxPlan = { ok: true; boxes: Box[]; detail: Record<string, unknown>; painted: Box[] } | { ok: false; skipped: string };

/**
 * What the server paints on a PDF page it can read (no pixels touched): the boxes that came with it and every identity run
 * the text layer locates, at SERVER_MARGIN; `painted` is the same boxes with their margin (drawing_code_floor.unreadTextHold).
 * `pdf` holds the source PDF's pages (pdfPages), `pageIndex` is this raster's page in it.
 */
export function serverBoxPlan(pdf: PdfPage[], pageIndex: number, boxes: Box[] | null): BoxPlan {
  // A missing / non-array entry means the page was not reviewed: never published.
  if (!boxes) return { ok: false, skipped: 'not_reviewed_by_customer' };
  const tl = textLayerBoxes(pdf, pageIndex);
  // TRUST BOUNDARY (14 Sep 2026): boxes prove nothing on a page the server cannot read. Such a page is held.
  if (!supplierPageReadable(pdf[pageIndex], tl.rotated)) return { ok: false, skipped: boxes.length ? 'held_unverifiable_client_boxes_ignored' : 'held_unverified_no_text_no_boxes' };
  const all = [...boxes, ...tl.boxes];
  const painted = all.map((b) => ({ x: b.x - SERVER_MARGIN, y: b.y - SERVER_MARGIN, w: b.w + 2 * SERVER_MARGIN, h: b.h + 2 * SERVER_MARGIN }));
  return { ok: true, boxes: all, detail: { manual_boxes: boxes.length, text_layer_boxes: tl.boxes.length }, painted };
}

/**
 * One portal raster of a PDF page, painted with the server's boxes and the text layer's identity boxes, in this worker
 * (serverBoxPlan, then paintedJpeg). drawing_redact itself plans here and paints in a worker of its own.
 */
export async function serverBoxedPage(raster: Uint8Array, pdf: PdfPage[], pageIndex: number, boxes: Box[] | null, quality = 82): Promise<PageOut> {
  const plan = serverBoxPlan(pdf, pageIndex, boxes);
  if (!plan.ok) return plan;
  let out: { jpg: Uint8Array; image: Image };
  try { out = await paintedJpeg(raster, [{ boxes: plan.boxes, pad: SERVER_MARGIN }], quality); } catch (_e) { return { ok: false, skipped: 'decode_failed' }; }
  return { ok: true, jpg: out.jpg, image: out.image, detail: plan.detail, painted: plan.painted };
}

export type CadOut =
  | { ok: true; jpg: Uint8Array; image: Image; detail: Record<string, unknown>; drawn_texts: string[] }
  | { ok: false; skipped: string; detail?: string };

const isDwg = (b: Uint8Array) => /^AC10\d\d$/.test(new TextDecoder('latin1').decode(b.subarray(0, 6)));

/**
 * A CAD original drawn for a supplier with its identity left out. `maxDwgBytes` is dwg.ts's edge ceiling on
 * the edge and Infinity on the CAD worker; `maxSegments` likewise (the worker has no CPU cap).
 */
export async function cadPage(original: Uint8Array, seeds: string[], opts: { maxDwgBytes?: number; maxSegments?: number; identity?: Set<string> } = {}): Promise<CadOut> {
  let input: Uint8Array | string = original;
  if (isDwg(original)) {
    const r = await readDwg(original, { filename: 'drawing.dwg', depth: 0 }, opts.maxDwgBytes);
    if (!r.ok) return { ok: false, skipped: 'dwg_unreadable', detail: r.detail };
    if (!r.dxf_text) return { ok: false, skipped: 'dwg_not_read_on_edge', detail: r.notes.join(' ').slice(0, 200) };
    input = r.dxf_text;
  }
  const g = await renderCadForSupplier(input, { seeds, maxSegments: opts.maxSegments, identity: opts.identity });
  if (!g.ok) return { ok: false, skipped: 'cad_render_' + g.reason, detail: g.detail };
  const image = new Image(g.width, g.height);
  image.bitmap.set(g.rgba);
  // Encoded from pixels this module drew: no EXIF, no XMP, no comment segment.
  const jpg = await image.encodeJPEG(85);
  return { ok: true, jpg, image, drawn_texts: g.drawn_texts,
    detail: { width: g.width, height: g.height, texts_withheld: g.withheld.texts, title_regions: g.withheld.regions, ...g.counts, notes: g.notes } };
}
