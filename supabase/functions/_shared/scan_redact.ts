// scan_redact — a SCANNED drawing page or a photo, redacted by code OCR with no model, and held unless the
// result is proved clean by reading it again (24 Sep 2026, sales_engineer; founder instructions 32, 579 "OCR for
// scanned drawings", 580, 703).
//
// MEASURED BEFORE: a page with no text layer (a scan, a photo, a CAD raster) was HELD every time
// (supplier_copy.supplierPageReadable), because the server had no words to box and the model is held. So no
// scanned drawing could ever reach a supplier.
//
// WHERE IT RUNS: on the CAD worker (scripts/cad_read_worker.ts, a GitHub runner with no edge CPU cap). The OCR
// engine is INJECTED (`ocr`), so this file holds only the decisions and a test can drive it with the real engine.
// The worker uses tesseract.js 7.0.0 (Apache-2.0), the same engine and the same self-hosted eng + ara language
// data (public/ocr/lang) the customer's browser already runs. It is free and pinned, and nothing leaves the runner.
//
// FAIL CLOSED (second review of #967, 25 Sep 2026). The first version boxed what a rule RECOGNISED as identity, so
// a stamp "ZZ ORBIT ENGINEERING" turned 90 or 30 degrees in the drawing body, and a body note "BY ZZ OMEGA", were
// published. Now a page is published only when every piece of text on it has been READ and CLEARED:
//   1. OCR the page at 0, 90, 180 and 270 degrees (the language data has no orientation model, so every quarter
//      turn is read; a word is READ when OCR gives it READ_CONF or more).
//   2. HOLD if no title block is found, if the words inside it read below MIN_TITLE_CONF (a title block we
//      cannot read is a title block we cannot prove we covered), or if the page has too few words to judge.
//   3. Box the title block (anonymise.titleBlockBoxes, drawing_identity_text.textLayerBoxes), every line anywhere
//      that names a party (company words, licence numbers, contacts, the title block's own names and the
//      customer's seeds, fuzzily), and every line, at any orientation, that is not drawing content by the same
//      policy the CAD renderer uses (drawing_text_policy.isDrawingContent): an unknown word is withheld.
//   4. Paint every box solid black, and OCR the PAINTED page again at all four orientations. HOLD if any line still
//      reads as identity, or any read word outside the boxes is not drawing content.
//   5. HOLD if ink that looks like text is left that no read word covers (unreadInk): text at 30 degrees, a
//      smeared stamp, a word OCR could not read is text we cannot prove clean.
// Only a page that passes all five is returned. The caller encodes it as a JPEG (from pixels: no metadata),
// uploads it and records the run, exactly as the CAD path does.
import { residualScan, seedTerms, stripSeeds, titleBlockBoxes } from './anonymise.ts';
import { drawingLocation, isDrawingContent, namesParty, partyLabel, seedHit } from './drawing_text_policy.ts';
import { ID_LABEL, ID_TEXT, textLayerBoxes } from './drawing_identity_text.ts';
import type { PdfPage, TextRun } from './pdf_text_positions.ts';

export type Box = { x: number; y: number; w: number; h: number };
export type OcrWord = { text: string; conf: number; bbox: { x0: number; y0: number; x1: number; y1: number } };
export type OcrLine = { text: string; conf: number; bbox: { x0: number; y0: number; x1: number; y1: number }; words: OcrWord[] };
/** The engine: an encoded image (BMP) in, its text lines with pixel boxes and 0-100 confidence out. */
export type Ocr = (image: Uint8Array) => Promise<OcrLine[]>;
export type Rgba = { w: number; h: number; rgba: Uint8ClampedArray };

/** Mean word confidence inside the title strip below this holds the page (tesseract's 0-100 scale). */
export const MIN_TITLE_CONF = 70;
/** A page from which OCR reads fewer words than this cannot be judged, so it is held. */
export const MIN_WORDS = 8;
/** Padding added round each box, as a share of the page (drawing_redact_page SERVER_MARGIN). */
const PAD = 0.004;
/** A word read below this confidence within NEAR of the title strip's edge holds the page. */
export const MIN_NEAR_CONF = 60;
const NEAR = 0.04;
/** A word is READ (its text is judged, and its ink counts as covered) at this confidence or more. Measured 25 Sep
 *  2026 on the ZZ scan: its dimensions "6000" and "4000", touching a dimension line and the frame, read at 51-55. */
export const READ_CONF = 50;
/** A reading at one orientation is set aside only when another orientation reads the same place this much better
 *  (mean word confidence): upside down, "OFFICE 101" reads as Arabic-looking junk at 66-76 against 86-90 upright.
 *  A narrower margin keeps BOTH readings, and each is judged - the fail-closed side. */
const BETTER_BY = 10;
/** Text-like ink: a connected blob whose longer side is between these shares of the page's shorter / longer side. */
const GLYPH_MIN = 0.006, GLYPH_MAX = 0.05;
/** SMALL TYPE (13 Nov 2026, anonymity audit B, G2). A glyph under GLYPH_MIN was taken for speckle. MEASURED: once the strip
 *  was read magnified, the clean 2600 px raster of the auditor's A1 pool sheet was PUBLISHED with its 7 pt edge text
 *  ("ZZ DEMO CORAL POOLS CONSULTANTS LLC"), the vertical "AL BARSHA 2" and an e-mail address readable, because type that
 *  small (about 5 px at 79 dpi) is neither read by OCR nor counted as ink. A run of SMALL_WORD or more glyph-sized blobs
 *  down to SMALL_GLYPH_MIN of the page, linked like letters, is a word too, and an unread one holds the page. */
const SMALL_GLYPH_MIN = 0.0022, SMALL_WORD = 4;
/** FAINT INK (same day, same sheet): the diagonal watermark "ZZ DEMO CORAL POOLS - CONFIDENTIAL" is printed at 85% grey,
 *  lighter than the 50% the ink test counted, and OCR did not read it at any turn, so the page was published with the
 *  consultant's name across it. Glyph-sized blobs down to this summed RGB (about 88% grey) are ink too. */
const FAINT_INK = 3 * 226;

/**
 * x positions (0..1) of long vertical ruled lines: columns whose longest dark run is at least half the page
 * height. A title block is a ruled box; its inner edge is one of these (review of #967: the strip was cut 1% left
 * of the leftmost evidence, so a firm name printed further left in the same ruled block was published).
 */
export function verticalRules(img: Rgba): number[] {
  const out: number[] = [];
  for (let x = 0; x < img.w; x++) {
    let run = 0, best = 0;
    for (let y = 0; y < img.h; y++) { const k = (y * img.w + x) * 4; if (img.rgba[k] < 110) { run++; if (run > best) best = run; } else run = 0; }
    if (best >= img.h * 0.5 && (!out.length || x - out[out.length - 1] * img.w > 3)) out.push(x / img.w);
  }
  return out;
}

/** RGBA to a 24-bit BMP: an uncompressed format every OCR engine reads, with no codec needed to write it. */
export function rgbaToBmp(img: Rgba): Uint8Array {
  const row = Math.ceil((img.w * 3) / 4) * 4, size = 54 + row * img.h;
  const b = new Uint8Array(size), dv = new DataView(b.buffer);
  b[0] = 0x42; b[1] = 0x4d; dv.setUint32(2, size, true); dv.setUint32(10, 54, true); dv.setUint32(14, 40, true);
  dv.setInt32(18, img.w, true); dv.setInt32(22, img.h, true); dv.setUint16(26, 1, true); dv.setUint16(28, 24, true);
  dv.setUint32(34, row * img.h, true); dv.setInt32(38, 2835, true); dv.setInt32(42, 2835, true);
  for (let y = 0; y < img.h; y++) {
    const o = 54 + (img.h - 1 - y) * row;
    for (let x = 0; x < img.w; x++) { const k = (y * img.w + x) * 4; b[o + x * 3] = img.rgba[k + 2]; b[o + x * 3 + 1] = img.rgba[k + 1]; b[o + x * 3 + 2] = img.rgba[k]; }
  }
  return b;
}

/** The page turned `q` quarter turns clockwise. */
export function quarterTurn(img: Rgba, q: number): Rgba {
  if (!(q % 4)) return img;
  const { w: W, h: H } = img, T = q % 2 ? { w: H, h: W } : { w: W, h: H };
  const out = new Uint8ClampedArray(T.w * T.h * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const [u, v] = q === 1 ? [H - 1 - y, x] : q === 2 ? [W - 1 - x, H - 1 - y] : [y, W - 1 - x];
    const s = (y * W + x) * 4, d = (v * T.w + u) * 4;
    out[d] = img.rgba[s]; out[d + 1] = img.rgba[s + 1]; out[d + 2] = img.rgba[s + 2]; out[d + 3] = 255;
  }
  return { w: T.w, h: T.h, rgba: out };
}
type PB = { x0: number; y0: number; x1: number; y1: number };
/** A box read on the page turned `q` quarter turns, in the unturned page's pixels. */
function unturn(b: PB, q: number, W: number, H: number): PB {
  if (q === 1) return { x0: b.y0, x1: b.y1, y0: H - 1 - b.x1, y1: H - 1 - b.x0 };
  if (q === 2) return { x0: W - 1 - b.x1, x1: W - 1 - b.x0, y0: H - 1 - b.y1, y1: H - 1 - b.y0 };
  if (q === 3) return { x0: W - 1 - b.y1, x1: W - 1 - b.y0, y0: b.x0, y1: b.x1 };
  return b;
}
type Read = OcrLine & { q: number };
/** OCR at all four quarter turns; every line and word comes back in the unturned page's pixels, tagged with q. */
async function readAllWays(img: Rgba, ocr: Ocr, k = 1): Promise<Read[]> {
  const out: Read[] = [];
  for (const q of [0, 1, 2, 3]) {
    const turned = quarterTurn(img, q);
    const lines: OcrLine[] = k > 1 ? await readZoomed(turned, { x: 0, y: 0, w: 1, h: 1 }, k, ocr) : await ocr(rgbaToBmp(turned));
    for (const l of lines) {
      out.push({ ...l, q, bbox: unturn(l.bbox, q, img.w, img.h), words: (l.words || []).map((w) => ({ ...w, bbox: unturn(w.bbox, q, img.w, img.h) })) });
    }
  }
  return out;
}

/** OCR lines as the PdfPage the PDF path's rules read (normalised, top-left origin). */
export function pageOf(lines: OcrLine[], w: number, h: number): PdfPage {
  const runs: TextRun[] = lines.filter((l) => l.text.trim()).map((l) => ({ text: l.text.replace(/\s+/g, ' ').trim(), x: l.bbox.x0 / w, y: l.bbox.y0 / h, w: (l.bbox.x1 - l.bbox.x0) / w, h: (l.bbox.y1 - l.bbox.y0) / h }));
  return { width: w, height: h, rotate: 0, runs };
}

const ALNUM = /[A-Za-z0-9\u0600-\u06ff]/;
const words = (lines: OcrLine[]) => lines.flatMap((l) => l.words).filter((x) => ALNUM.test(x.text));
const inside = (b: Box, w: OcrWord, W: number, H: number) => { const cx = (w.bbox.x0 + w.bbox.x1) / 2 / W, cy = (w.bbox.y0 + w.bbox.y1) / 2 / H; return cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h; };
const boxOf = (b: PB, W: number, H: number): Box => ({ x: b.x0 / W, y: b.y0 / H, w: (b.x1 - b.x0) / W, h: (b.y1 - b.y0) / H });
/** The read words of a line, and that text: a word OCR could barely read is not judged here (unreadInk judges it). */
const readText = (l: OcrLine) => l.words.filter((w) => w.conf >= READ_CONF && ALNUM.test(w.text)).map((w) => w.text).join(' ').trim();
const scoreOf = (l: OcrLine) => { const ws = l.words.filter((w) => ALNUM.test(w.text)); const n = ws.reduce((a, w) => a + w.text.length, 0); return n ? ws.reduce((a, w) => a + w.conf * w.text.length, 0) / n : 0; };
const areaOf = (b: PB) => Math.max(0, b.x1 - b.x0) * Math.max(0, b.y1 - b.y0);
const overlap = (a: PB, b: PB) => { const i = areaOf({ x0: Math.max(a.x0, b.x0), y0: Math.max(a.y0, b.y0), x1: Math.min(a.x1, b.x1), y1: Math.min(a.y1, b.y1) }); return i / Math.max(1, Math.min(areaOf(a), areaOf(b))); };
/** The readings that stand: a line is dropped only when a line read at another orientation over the same place
 *  (overlapping 30% of the smaller) scores BETTER_BY more. Every reading that stands is judged. */
function standing(lines: Read[]): Read[] {
  const sc = lines.map(scoreOf);
  return lines.filter((l, i) => !lines.some((m, j) => m.q !== l.q && sc[j] >= sc[i] + BETTER_BY && overlap(l.bbox, m.bbox) >= 0.3));
}
/** A line whose read words say something: one read character is a box edge or a stray mark, not a word. */
const judged = (l: OcrLine) => readText(l).replace(/[^A-Za-z0-9\u0600-\u06ff]/g, '').length >= 2;

/** Which pixels the boxes paint (1), with the same padding paint() uses. */
function maskOf(img: { w: number; h: number }, boxes: Box[]): Uint8Array {
  const m = new Uint8Array(img.w * img.h);
  for (const g of boxes) {
    const x0 = Math.max(0, Math.floor((g.x - PAD) * img.w)), y0 = Math.max(0, Math.floor((g.y - PAD) * img.h));
    const x1 = Math.min(img.w, Math.ceil((g.x + g.w + PAD) * img.w)), y1 = Math.min(img.h, Math.ceil((g.y + g.h + PAD) * img.h));
    for (let y = y0; y < y1; y++) m.fill(1, y * img.w + x0, y * img.w + x1);
  }
  return m;
}
function paint(img: Rgba, mask: Uint8Array): Rgba {
  const out = new Uint8ClampedArray(img.rgba);
  for (let i = 0; i < mask.length; i++) if (mask[i]) { const k = i * 4; out[k] = 0; out[k + 1] = 0; out[k + 2] = 0; out[k + 3] = 255; }
  return { w: img.w, h: img.h, rgba: out };
}

/**
 * Text-like ink that nothing READ covers: dark connected blobs the size of a glyph (GLYPH_MIN..GLYPH_MAX of the
 * page), not under a painted box and not inside (a little beyond) a word OCR read, linked to their neighbours
 * within a glyph's height. Returns the clusters of two or more such blobs: each is text no one has read. Walls,
 * frames and painted boxes are one large blob and are not glyphs; scanner speckle is smaller than a glyph.
 */
export function unreadInk(img: Rgba, covered: PB[], painted: Uint8Array = new Uint8Array(img.w * img.h), mode: 'normal' | 'small' | 'faint' = 'normal'): PB[] {
  const small = mode === 'small';
  const { w: W, h: H } = img, lab = new Uint8Array(W * H);
  const lo = (small ? SMALL_GLYPH_MIN : GLYPH_MIN) * Math.min(W, H), hi = (small ? GLYPH_MIN : GLYPH_MAX) * Math.max(W, H);
  // A painted pixel is a box, not ink, so ink touching a box is judged on its own.
  const cut = mode === 'faint' ? FAINT_INK : 384;
  const dark = (i: number) => !painted[i] && (img.rgba[i * 4] + img.rgba[i * 4 + 1] + img.rgba[i * 4 + 2]) < cut;
  const blobs: (PB & { n: number })[] = [];
  const stack: number[] = [];
  for (let s = 0; s < W * H; s++) {
    if (lab[s] || !dark(s)) continue;
    const b = { x0: W, y0: H, x1: 0, y1: 0, n: 0 };
    lab[s] = 1; stack.push(s);
    while (stack.length) {
      const i = stack.pop()!, x = i % W, y = (i - x) / W;
      b.n++; if (x < b.x0) b.x0 = x; if (x > b.x1) b.x1 = x; if (y < b.y0) b.y0 = y; if (y > b.y1) b.y1 = y;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const X = x + dx, Y = y + dy; if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
        const j = Y * W + X; if (!lab[j] && dark(j)) { lab[j] = 1; stack.push(j); }
      }
    }
    const size = Math.max(b.x1 - b.x0 + 1, b.y1 - b.y0 + 1);
    if (size >= lo && size <= hi && b.n >= (small ? 6 : 12)) blobs.push(b);
  }
  const cov = (b: PB) => { const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2; return covered.some((c) => { const p = 0.35 * Math.max(8, Math.min(c.x1 - c.x0, c.y1 - c.y0)); return cx >= c.x0 - p && cx <= c.x1 + p && cy >= c.y0 - p && cy <= c.y1 + p; }); };
  const open = blobs.filter((b) => !cov(b));
  const parent = open.map((_, i) => i);
  const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  for (let i = 0; i < open.length; i++) for (let j = i + 1; j < open.length; j++) {
    const a = open[i], c = open[j], g = Math.max(a.x1 - a.x0, a.y1 - a.y0, c.x1 - c.x0, c.y1 - c.y0);
    if (Math.max(c.x0 - a.x1, a.x0 - c.x1) <= g && Math.max(c.y0 - a.y1, a.y0 - c.y1) <= g) parent[find(i)] = find(j);
  }
  const groups = new Map<number, PB[]>();
  open.forEach((b, i) => { const r = find(i); (groups.get(r) ?? groups.set(r, []).get(r)!).push(b); });
  return [...groups.values()].filter((g) => g.length >= (small ? SMALL_WORD : 2)).map((g) => ({ x0: Math.min(...g.map((b) => b.x0)), y0: Math.min(...g.map((b) => b.y0)), x1: Math.max(...g.map((b) => b.x1)), y1: Math.max(...g.map((b) => b.y1)) }));
}

/** The title strip is read again at this magnification (see redactScan). */
export const STRIP_ZOOM = 3;
/** How many more times a page is boxed and read again for spans that fail only the vocabulary (see redactScan). */
export const EXTRA_ROUNDS = 2;
/** A region of the page, magnified `k` times (bilinear), as its own image. */
export function zoomRegion(img: Rgba, b: Box, k: number): { image: Rgba; x0: number; y0: number } {
  const x0 = Math.max(0, Math.floor(b.x * img.w)), y0 = Math.max(0, Math.floor(b.y * img.h));
  const x1 = Math.min(img.w, Math.ceil((b.x + b.w) * img.w)), y1 = Math.min(img.h, Math.ceil((b.y + b.h) * img.h));
  const W = Math.max(1, (x1 - x0) * k), H = Math.max(1, (y1 - y0) * k), out = new Uint8ClampedArray(W * H * 4);
  for (let y = 0; y < H; y++) {
    const sy = Math.min(y1 - 1, y0 + (y + 0.5) / k - 0.5), ya = Math.max(y0, Math.floor(sy)), yb = Math.min(y1 - 1, ya + 1), fy = Math.max(0, sy - ya);
    for (let x = 0; x < W; x++) {
      const sx = Math.min(x1 - 1, x0 + (x + 0.5) / k - 0.5), xa = Math.max(x0, Math.floor(sx)), xb = Math.min(x1 - 1, xa + 1), fx = Math.max(0, sx - xa);
      const d = (y * W + x) * 4;
      for (let c = 0; c < 3; c++) {
        const p = (xx: number, yy: number) => img.rgba[(yy * img.w + xx) * 4 + c];
        out[d + c] = (p(xa, ya) * (1 - fx) + p(xb, ya) * fx) * (1 - fy) + (p(xa, yb) * (1 - fx) + p(xb, yb) * fx) * fy;
      }
      out[d + 3] = 255;
    }
  }
  return { image: { w: W, h: H, rgba: out }, x0, y0 };
}
/** OCR of a region magnified `k` times, its boxes back in the page's pixels. */
/** Read in tiles of at most this many magnified pixels a side (a whole A1 strip at 3x is past what the engine takes). */
const TILE = 1800;
async function readZoomed(img: Rgba, b: Box, k: number, ocr: Ocr): Promise<Read[]> {
  const out: Read[] = [];
  const tw = TILE / k / img.w, th = TILE / k / img.h, ovx = 80 / img.w, ovy = 60 / img.h;   // tile size and overlap, as page shares
  for (let y = b.y; y < b.y + b.h - 1e-9; y += th - ovy) {
    for (let x = b.x; x < b.x + b.w - 1e-9; x += tw - ovx) {
      const z = zoomRegion(img, { x, y, w: Math.min(tw, b.x + b.w - x), h: Math.min(th, b.y + b.h - y) }, k);
      const back = (q: PB): PB => ({ x0: z.x0 + q.x0 / k, y0: z.y0 + q.y0 / k, x1: z.x0 + q.x1 / k, y1: z.y0 + q.y1 / k });
      // A line cut by an inner tile edge is read again whole in the neighbouring tile (the overlap); the cut reading is dropped.
      const W = z.image.w, H = z.image.h;
      const edge = (q: PB) => (y > b.y && q.y0 < 2 * k) || (y + th < b.y + b.h && q.y1 > H - 2 * k) || (x > b.x && q.x0 < 2 * k) || (x + tw < b.x + b.w && q.x1 > W - 2 * k);
      for (const l of await ocr(rgbaToBmp(z.image))) if (!edge(l.bbox)) out.push({ ...l, q: 0, bbox: back(l.bbox), words: (l.words || []).map((w) => ({ ...w, bbox: back(w.bbox) })) });
    }
  }
  return out;
}
/** Type this small (median word height in page pixels) is read with the whole page magnified PAGE_ZOOM times. MEASURED
 *  13 Nov 2026 on the clean 2600 px raster of the auditor's A1 pool sheet (79 dpi, 7-9 pt type about 8-10 px tall):
 *  read as it stands, its edge text, its vertical area name and an e-mail were neither read nor counted as ink; read at
 *  3x, the title strip went from a mean confidence of 59 to 90. */
export const SMALL_TYPE_PX = 14, PAGE_ZOOM = 2;

export type ScanResult =
  | { ok: true; image: Rgba; boxes: Box[]; detail: Record<string, unknown> }
  | { ok: false; held: 'too_few_words' | 'no_title_block_found' | 'title_block_unread' | 'title_block_low_confidence' | 'identity_survived_reocr' | 'unread_ink'; detail: Record<string, unknown> };

/** One page: OCR every way up, box, paint, re-OCR every way up, and return it only if all of it was read and is clean. */
/** `zoom`: the strip's second, magnified reading (STRIP_ZOOM; 1 = none, for a stub engine that answers in fixed pixels). */
export async function redactScan(img: Rgba, ocr: Ocr, seeds: string[], opts: { zoom?: number } = {}): Promise<ScanResult> {
  let all = await readAllWays(img, ocr);
  let first = all.filter((l) => l.q === 0);
  // Small type: the whole page is read again magnified, and every later reading of it too.
  const hs = words(first).map((w) => w.bbox.y1 - w.bbox.y0).sort((a, b) => a - b);
  const pk = (opts.zoom ?? STRIP_ZOOM) > 1 && hs.length && hs[Math.floor(hs.length / 2)] < SMALL_TYPE_PX ? PAGE_ZOOM : 1;
  if (pk > 1) { all = await readAllWays(img, ocr, pk); first = all.filter((l) => l.q === 0); }
  const ws = words(first);
  if (ws.length < MIN_WORDS) return { ok: false, held: 'too_few_words', detail: { words: ws.length } };
  const page = pageOf(first, img.w, img.h);
  const tb = titleBlockBoxes([page], seeds);
  const strip = tb.strips[0];
  if (!strip || tb.confidence !== 'medium') return { ok: false, held: 'no_title_block_found', detail: { confidence: tb.confidence, residual: tb.residual.slice(0, 5) } };
  // THE TITLE BLOCK IS THE RULED BOX, not just the evidence column: its left edge moves to the nearest long ruled
  // line within 35% of the sheet to the left of the evidence (only for a right-hand strip).
  if (strip.x > 0.5 && strip.y === 0 && strip.h === 1) {
    const rule = verticalRules(img).filter((x) => x < strip.x && strip.x - x <= 0.35 && x > 0.4).sort((a, b) => b - a)[0];
    if (rule !== undefined) { const x = Math.max(0, rule - 0.004); strip.w += strip.x - x; strip.x = x; tb.boxes[0].push({ ...strip }); }
  }
  // THE STRIP IS READ AGAIN, MAGNIFIED (13 Nov 2026, sales_engineer; anonymity audit B finding G2). MEASURED: a CLEAN
  // 2600 px raster of the auditor's A1 pool sheet was held at title_conf 59 against 70, every time. The threshold was
  // not wrong and neither was the strip: the strip's 7-9 pt type is about 10 px tall at 2600 px across an A1 sheet
  // (79 dpi), below what tesseract reads well ("VILA", "BARSHAZ,", "BRAVING" for DRAWING, "2026/8p/55821"). The strip
  // and the band beside it are now OCR'd at STRIP_ZOOM x, and that reading is the one the strip is judged and seeded on.
  const band: Box = { x: Math.max(0, strip.x - NEAR), y: strip.y, w: Math.min(1, strip.x + strip.w) - Math.max(0, strip.x - NEAR), h: strip.h };
  const k = opts.zoom ?? STRIP_ZOOM;
  const zoomed = k > 1 ? await readZoomed(img, band, k, ocr) : first;
  if (k > 1) all.push(...zoomed);
  const zws = words(zoomed);
  const zpage = pageOf(zoomed, img.w, img.h);
  // A word OCR could barely read right beside the strip may be the title block's own text, misread: hold.
  const nearLow = zws.filter((x) => x.conf < MIN_NEAR_CONF && x.bbox.x1 / img.w >= strip.x - NEAR && x.bbox.x0 / img.w < strip.x);
  if (nearLow.length) return { ok: false, held: 'title_block_low_confidence', detail: { near_strip_low_conf_words: nearLow.length } };
  const inStrip = zws.filter((x) => inside(strip, x, img.w, img.h));
  if (!inStrip.length) return { ok: false, held: 'title_block_unread', detail: { strip } };
  const titleConf = inStrip.reduce((n, x) => n + x.conf, 0) / inStrip.length;
  if (titleConf < MIN_TITLE_CONF) return { ok: false, held: 'title_block_low_confidence', detail: { title_conf: Math.round(titleConf), words_in_title: inStrip.length } };
  // PAGE-WIDE, EVERY WAY UP: the names the title block prints join the customer's seeds; every line that names a
  // party, and every line whose read words are not drawing content, is boxed wherever it stands.
  const strSeeds = [...new Set([...stripSeeds(page, strip), ...stripSeeds(zpage, strip)])];
  const stripTerms = [...new Set([...strSeeds, ...seedTerms({ extra: strSeeds })])];
  const terms = [...new Set([...seeds, ...stripTerms])];
  const party = (t: string) => namesParty(t) || partyLabel(t) || !!seedHit(t, terms);
  const notContent = (l: OcrLine) => judged(l) && !isDrawingContent(readText(l));
  const stood = standing(all);
  // Every UPRIGHT reading is judged too, not only the readings that stand (13 Nov 2026): on the clean B1 raster an upright
  // line "DEEP END FFL 5L88LNCE TANK …" was set aside for a better-scoring reading at another turn, never boxed, and then
  // stood on the painted page and held it. Judging it in the first pass boxes it (fail closed: a misread is covered).
  const pageWide = [...new Set([...stood, ...first])].filter((l) => party(l.text) || drawingLocation(l.text) || notContent(l)).map((l) => boxOf(l.bbox, img.w, img.h));
  // The first reading of ink that read as drawing content (13 Nov 2026): on the clean B1 raster the re-read of the
  // painted page held the sheet on "For site access cal)" and "DEEP END FFL 5L88LNCE TANK" - the same unchanged ink
  // the first pass read as "For site access call" and "DEEP END FFL -1.80 BALANCE TANK", misread a second time. A
  // re-read line over the same place as a first reading that WAS content is judged by every identity rule below, but
  // not by the vocabulary a second time. Painting only removes ink; it cannot turn content into a party.
  const firstContent = stood.filter((l) => judged(l) && isDrawingContent(readText(l)) && !party(l.text) && !drawingLocation(l.text));
  const same = (a: PB, b: PB) => areaOf({ x0: Math.max(a.x0, b.x0), y0: Math.max(a.y0, b.y0), x1: Math.min(a.x1, b.x1), y1: Math.min(a.y1, b.y1) }) / Math.max(1, areaOf(a), areaOf(b));
  // Same place: the two boxes overlap by half of the larger, or the re-read lies (60% or more) inside the first reading.
  const within = (r: PB, f: PB) => areaOf({ x0: Math.max(r.x0, f.x0), y0: Math.max(r.y0, f.y0), x1: Math.min(r.x1, f.x1), y1: Math.min(r.y1, f.y1) }) / Math.max(1, areaOf(r));
  const wasContent = (r: OcrLine) => firstContent.some((f) => same(f.bbox, r.bbox) >= 0.5 || within(r.bbox, f.bbox) >= 0.6);
  const boxes = [...tb.boxes[0], ...textLayerBoxes([page], 0).boxes, ...pageWide];
  // Every string the first pass saw as identity is looked for again on the painted page.
  const found = all.filter((r) => ID_TEXT.test(r.text) || ID_LABEL.test(r.text) || residualScan(r.text, seeds).length > 0).map((r) => r.text);
  const again = [...new Set([...terms, ...found.filter((t) => t.length >= 6).map((t) => t.toLowerCase())])];
  // The re-read: patterns, company words and licence numbers, every seed matched FUZZILY, and any read word outside
  // the boxes that is not drawing content. REMOVE, THEN READ AGAIN (13 Nov 2026, anonymity audit B finding G2; FIX_COMMON
  // "when in doubt REMOVE the span"): a line the re-read finds that only fails the VOCABULARY (no party, seed, pattern
  // or place in it) is a span nobody proved, and it is boxed and the page read once more, up to EXTRA_ROUNDS times. MEASURED
  // on the clean B1 raster: the painted page held on "ROOFING. Ci" and "For site access cal)", halves of lines whose
  // other half a box had covered. A line that names a party, a seed or a place still HOLDS the page at once.
  let mask = maskOf(img, boxes), painted = paint(img, mask);
  let second = standing(await readAllWays(painted, ocr, pk));
  const under = (l: OcrLine) => boxes.some((b) => inside(b, { text: '', conf: 0, bbox: l.bbox }, img.w, img.h));
  const named = (r: OcrLine) => namesParty(r.text) || partyLabel(r.text) || residualScan(r.text, again).length > 0 || !!seedHit(r.text, again) || !!drawingLocation(r.text);
  for (let round = 0; ; round++) {
    const ident = second.filter(named);
    if (ident.length) return { ok: false, held: 'identity_survived_reocr', detail: { lines: ident.length, sample: ident.slice(0, 3).map((l) => ({ q: l.q, conf: Math.round(l.conf) })) } };
    const unproved = second.filter((r) => !under(r) && notContent(r) && !wasContent(r));
    if (!unproved.length) break;
    if (round >= EXTRA_ROUNDS) return { ok: false, held: 'identity_survived_reocr', detail: { lines: unproved.length, rounds: round, sample: unproved.slice(0, 3).map((l) => ({ q: l.q, conf: Math.round(l.conf) })) } };
    boxes.push(...unproved.map((l) => boxOf(l.bbox, img.w, img.h)));
    mask = maskOf(img, boxes); painted = paint(img, mask);
    second = standing(await readAllWays(painted, ocr, pk));
  }
  // Everything that looks like text must have been read: a word read at READ_CONF, at any orientation, covers it.
  const read = second.flatMap((l) => l.words.filter((w) => w.conf >= READ_CONF && ALNUM.test(w.text)).map((w) => w.bbox));
  const unread = [...unreadInk(painted, read, mask), ...unreadInk(painted, read, mask, 'small'), ...unreadInk(painted, read, mask, 'faint')];
  if (unread.length) return { ok: false, held: 'unread_ink', detail: { clusters: unread.length, at: unread.slice(0, 12) } };
  return { ok: true, image: painted, boxes, detail: { method: 'scan_ocr', words: ws.length, title_conf: Math.round(titleConf), boxes: boxes.length, reocr_lines: second.length, orientations: 4 } };
}
