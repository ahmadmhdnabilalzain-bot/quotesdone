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
import { isDrawingContent, namesParty, partyLabel, seedHit } from './drawing_text_policy.ts';
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
/** Text-like ink: a connected blob whose longer side is between these shares of the page's shorter / longer side.
 *  Third review of #967: 0.05 missed "OMEGA" underlined (one blob 161 px wide on a 2600 px page); 0.08 takes it. */
const GLYPH_MIN = 0.006, GLYPH_MAX = 0.08;
/** Below a glyph but not speckle: blobs this many pixels across (or more) that stand in a row are small print. */
const SUB_MIN = 3;

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
async function readAllWays(img: Rgba, ocr: Ocr): Promise<Read[]> {
  const out: Read[] = [];
  for (const q of [0, 1, 2, 3]) {
    for (const l of await ocr(rgbaToBmp(quarterTurn(img, q)))) {
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
 * The page's paper, and what counts as INK on it. Third review of #967: ink judged as "darker than mid-grey" missed
 * a grey watermark (200), grey text (190) and a light-blue stamp (120, 170, 240). Ink is now any pixel whose DARKEST
 * channel is 20 below the paper - the 90th percentile of the darkest channel, sampled - and never lighter than 235.
 */
export function inkLevel(img: Rgba): number {
  const n = img.w * img.h, step = Math.max(1, Math.floor(n / 50_000)), v: number[] = [];
  for (let i = 0; i < n; i += step) v.push(Math.min(img.rgba[i * 4], img.rgba[i * 4 + 1], img.rgba[i * 4 + 2]));
  v.sort((x, y) => x - y);
  return Math.min(235, v[Math.floor(v.length * 0.9)] - 20);
}

/**
 * Text-like ink that nothing READ covers. Ink blobs (inkLevel) that are not under a painted box and whose middle is
 * not inside (a little beyond) something OCR read are OPEN. Returned, as boxes:
 *   - every cluster of `minCluster` or more open GLYPH-sized blobs (GLYPH_MIN..GLYPH_MAX of the page), linked to
 *     neighbours within a glyph's size. Scans use 1 (third review: an underlined word is ONE blob, and "unread text is
 *     held only in twos" let it through); a rendered CAD page uses 3, since its device symbols are single blobs;
 *   - every ROW of 4 or more open blobs smaller than a glyph but SUB_MIN pixels or more, of like size, on one
 *     line, each within twice its size of the next: small print (third review: 11 px type was below a glyph).
 * Walls, frames and painted boxes are larger than a glyph; scanner speckle is smaller than SUB_MIN.
 */
export function unreadInk(img: Rgba, covered: PB[], painted: Uint8Array = new Uint8Array(img.w * img.h), o: { minCluster?: number } = {}): PB[] {
  const { w: W, h: H } = img, lab = new Uint8Array(W * H);
  const lo = GLYPH_MIN * Math.min(W, H), hi = GLYPH_MAX * Math.max(W, H), level = inkLevel(img);
  // A painted pixel is a box, not ink, so ink touching a box is judged on its own.
  const dark = (i: number) => !painted[i] && Math.min(img.rgba[i * 4], img.rgba[i * 4 + 1], img.rgba[i * 4 + 2]) < level;
  const blobs: (PB & { n: number })[] = [], subs: (PB & { n: number })[] = [];
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
    if (size >= lo && size <= hi && b.n >= 12) blobs.push(b);
    else if (size >= SUB_MIN && size < lo && b.n >= 4) subs.push(b);
  }
  const cov = (b: PB) => { const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2; return covered.some((c) => { const p = 0.35 * Math.max(8, Math.min(c.x1 - c.x0, c.y1 - c.y0)); return cx >= c.x0 - p && cx <= c.x1 + p && cy >= c.y0 - p && cy <= c.y1 + p; }); };
  const cluster = (list: PB[], link: (a: PB, c: PB) => boolean) => {
    const parent = list.map((_, i) => i);
    const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    const order = list.map((_, i) => i).sort((i, j) => list[i].x0 - list[j].x0);
    const reach = Math.max(0, ...list.map((b) => 2 * Math.max(b.x1 - b.x0, b.y1 - b.y0)));
    for (let ii = 0; ii < order.length; ii++) for (let jj = ii + 1; jj < order.length && list[order[jj]].x0 - list[order[ii]].x1 <= reach; jj++) {
      if (link(list[order[ii]], list[order[jj]])) parent[find(order[ii])] = find(order[jj]);
    }
    const groups = new Map<number, PB[]>();
    list.forEach((b, i) => { const r = find(i); (groups.get(r) ?? groups.set(r, []).get(r)!).push(b); });
    return [...groups.values()];
  };
  const hull = (g: PB[]): PB => ({ x0: Math.min(...g.map((b) => b.x0)), y0: Math.min(...g.map((b) => b.y0)), x1: Math.max(...g.map((b) => b.x1)), y1: Math.max(...g.map((b) => b.y1)) });
  const sz = (b: PB) => Math.max(b.x1 - b.x0, b.y1 - b.y0);
  const glyphs = cluster(blobs.filter((b) => !cov(b)), (a, c) => { const g = Math.max(sz(a), sz(c)); return Math.max(c.x0 - a.x1, a.x0 - c.x1) <= g && Math.max(c.y0 - a.y1, a.y0 - c.y1) <= g; })
    .filter((g) => g.length >= (o.minCluster ?? 1)).map(hull);
  const rows = cluster(subs.filter((b) => !cov(b)), (a, c) => {
    const s1 = sz(a), s2 = sz(c), g = Math.max(s1, s2);
    if (g > 2.5 * Math.min(s1, s2)) return false;
    const overlap = Math.min(a.y1, c.y1) - Math.max(a.y0, c.y0);
    return overlap >= 0.3 * Math.min(a.y1 - a.y0 + 1, c.y1 - c.y0 + 1) && Math.max(c.x0 - a.x1, a.x0 - c.x1) <= 2 * g;
  }).filter((g) => g.length >= 4).map(hull);
  return [...glyphs, ...rows];
}

/**
 * A CAD page drawn by cad_render, read back by OCR before it is published (third review of #967: text drawn as
 * geometry - SHX exploded, a PDF converted to DWG - is linework cad_render cannot judge). Read all four ways up;
 * HOLD when:
 *   - any line reads as a party: a company word, a licence number, a contact, a party label, a seed (fuzzily);
 *   - a word of 3 or more letters is read where cad_render drew NO text (`textsPx`): words drawn as lines;
 *   - text-like ink no read word and no drawn text covers stands in a row of 3 or more glyphs, or as small print.
 */
export async function verifyRenderedCad(img: Rgba, ocr: Ocr, seeds: string[], textsPx: { x: number; y: number; w: number; h: number }[]): Promise<{ ok: true; detail: Record<string, unknown> } | { ok: false; held: 'identity_read_back' | 'text_drawn_as_geometry' | 'unread_ink'; detail: Record<string, unknown> }> {
  const all = standing(await readAllWays(img, ocr));
  const drawn: PB[] = textsPx.map((t) => ({ x0: t.x, y0: t.y, x1: t.x + t.w, y1: t.y + t.h }));
  const onDrawn = (b: PB) => drawn.some((d) => overlap(b, d) >= 0.5);
  const party = all.filter((l) => namesParty(l.text) || partyLabel(l.text) || !!seedHit(l.text, seeds) || residualScan(l.text, seeds).length > 0);
  if (party.length) return { ok: false, held: 'identity_read_back', detail: { lines: party.length } };
  const geometry = all.filter((l) => /[A-Za-z]{3,}/.test(readText(l)) && !onDrawn(l.bbox));
  if (geometry.length) return { ok: false, held: 'text_drawn_as_geometry', detail: { lines: geometry.length, sample: geometry.slice(0, 3).map((l) => ({ q: l.q, conf: Math.round(l.conf), at: l.bbox })) } };
  const read = all.flatMap((l) => l.words.filter((w) => w.conf >= READ_CONF && ALNUM.test(w.text)).map((w) => w.bbox));
  const unread = unreadInk(img, [...drawn, ...read], undefined, { minCluster: 3 });
  if (unread.length) return { ok: false, held: 'unread_ink', detail: { clusters: unread.length, at: unread.slice(0, 12) } };
  return { ok: true, detail: { method: 'cad_ocr_reread', lines: all.length, orientations: 4 } };
}

export type ScanResult =
  | { ok: true; image: Rgba; boxes: Box[]; detail: Record<string, unknown> }
  | { ok: false; held: 'too_few_words' | 'no_title_block_found' | 'title_block_unread' | 'title_block_low_confidence' | 'identity_survived_reocr' | 'unread_ink'; detail: Record<string, unknown> };

/** One page: OCR every way up, box, paint, re-OCR every way up, and return it only if all of it was read and is clean. */
export async function redactScan(img: Rgba, ocr: Ocr, seeds: string[]): Promise<ScanResult> {
  const all = await readAllWays(img, ocr);
  const first = all.filter((l) => l.q === 0);
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
  // A word OCR could barely read right beside the strip may be the title block's own text, misread: hold.
  const nearLow = ws.filter((x) => x.conf < MIN_NEAR_CONF && x.bbox.x1 / img.w >= strip.x - NEAR && x.bbox.x0 / img.w < strip.x);
  if (nearLow.length) return { ok: false, held: 'title_block_low_confidence', detail: { near_strip_low_conf_words: nearLow.length } };
  const inStrip = ws.filter((x) => inside(strip, x, img.w, img.h));
  if (!inStrip.length) return { ok: false, held: 'title_block_unread', detail: { strip } };
  const titleConf = inStrip.reduce((n, x) => n + x.conf, 0) / inStrip.length;
  if (titleConf < MIN_TITLE_CONF) return { ok: false, held: 'title_block_low_confidence', detail: { title_conf: Math.round(titleConf), words_in_title: inStrip.length } };
  // PAGE-WIDE, EVERY WAY UP: the names the title block prints join the customer's seeds; every line that names a
  // party, and every line whose read words are not drawing content, is boxed wherever it stands.
  const stripTerms = [...new Set([...stripSeeds(page, strip), ...seedTerms({ extra: stripSeeds(page, strip) })])];
  const terms = [...new Set([...seeds, ...stripTerms])];
  const party = (t: string) => namesParty(t) || partyLabel(t) || !!seedHit(t, terms);
  const notContent = (l: OcrLine) => judged(l) && !isDrawingContent(readText(l));
  const pageWide = standing(all).filter((l) => party(l.text) || notContent(l)).map((l) => boxOf(l.bbox, img.w, img.h));
  const boxes = [...tb.boxes[0], ...textLayerBoxes([page], 0).boxes, ...pageWide];
  // Every string the first pass saw as identity is looked for again on the painted page.
  const found = all.filter((r) => ID_TEXT.test(r.text) || ID_LABEL.test(r.text) || residualScan(r.text, seeds).length > 0).map((r) => r.text);
  const again = [...new Set([...terms, ...found.filter((t) => t.length >= 6).map((t) => t.toLowerCase())])];
  const mask = maskOf(img, boxes);
  const painted = paint(img, mask);
  const second = standing(await readAllWays(painted, ocr));
  const under = (l: OcrLine) => boxes.some((b) => inside(b, { text: '', conf: 0, bbox: l.bbox }, img.w, img.h));
  // The re-read: patterns, company words and licence numbers, every seed matched FUZZILY, and any read word outside
  // the boxes that is not drawing content.
  const left = second.filter((r) => namesParty(r.text) || partyLabel(r.text) || residualScan(r.text, again).length > 0 || !!seedHit(r.text, again) || (!under(r) && notContent(r)));
  if (left.length) return { ok: false, held: 'identity_survived_reocr', detail: { lines: left.length, sample: left.slice(0, 3).map((l) => ({ q: l.q, conf: Math.round(l.conf) })) } };
  // Everything that looks like text must have been read: a word read at READ_CONF, at any orientation, covers it,
  // and so does the line it stands in (a dash or a colon between read words).
  const read = second.flatMap((l) => { const ws = l.words.filter((w) => w.conf >= READ_CONF && ALNUM.test(w.text)); return ws.length ? [...ws.map((w) => w.bbox), l.bbox] : []; });
  const unread = unreadInk(painted, read, mask);
  if (unread.length) return { ok: false, held: 'unread_ink', detail: { clusters: unread.length, at: unread.slice(0, 12) } };
  return { ok: true, image: painted, boxes, detail: { method: 'scan_ocr', words: ws.length, title_conf: Math.round(titleConf), boxes: boxes.length, reocr_lines: second.length, orientations: 4 } };
}
