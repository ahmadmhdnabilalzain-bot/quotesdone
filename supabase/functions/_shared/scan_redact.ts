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
// THE DECISIONS, all fail-closed:
//   1. OCR the page. Lines, with boxes and confidence, become a PdfPage, so the SAME deterministic rules the
//      PDF path uses decide what is identity: anonymise.titleBlockBoxes (the title strip, labels with their
//      values, plot / Makani / licence / TRN / contact patterns, the customer's seed terms, revision tables)
//      and drawing_identity_text.textLayerBoxes (e-mails, URLs, phones, company suffixes, "Drawn by" ...).
//   2. HOLD if no title block is found, if the words inside it read below MIN_TITLE_CONF (a title block we
//      cannot read is a title block we cannot prove we covered), or if the page has too few words to judge.
//   3. Paint every box solid black.
//   4. OCR the PAINTED page again. HOLD if any line still reads as identity: the patterns, the seeds, and every
//      identity string the first pass found anywhere on the page.
// Only a page that passes all four is returned. The caller encodes it as a JPEG (from pixels: no metadata),
// uploads it and records the run, exactly as the CAD path does.
import { residualScan, seedTerms, stripSeeds, titleBlockBoxes } from './anonymise.ts';
import { COMPANY, LICENCE, seedHit } from './drawing_text_policy.ts';
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

/** OCR lines as the PdfPage the PDF path's rules read (normalised, top-left origin). */
export function pageOf(lines: OcrLine[], w: number, h: number): PdfPage {
  const runs: TextRun[] = lines.filter((l) => l.text.trim()).map((l) => ({ text: l.text.replace(/\s+/g, ' ').trim(), x: l.bbox.x0 / w, y: l.bbox.y0 / h, w: (l.bbox.x1 - l.bbox.x0) / w, h: (l.bbox.y1 - l.bbox.y0) / h }));
  return { width: w, height: h, rotate: 0, runs };
}

const words = (lines: OcrLine[]) => lines.flatMap((l) => l.words).filter((x) => /[A-Za-z0-9\u0600-\u06ff]/.test(x.text));
const inside = (b: Box, w: OcrWord, W: number, H: number) => { const cx = (w.bbox.x0 + w.bbox.x1) / 2 / W, cy = (w.bbox.y0 + w.bbox.y1) / 2 / H; return cx >= b.x && cx <= b.x + b.w && cy >= b.y && cy <= b.y + b.h; };

function paint(img: Rgba, boxes: Box[]): Rgba {
  const out = new Uint8ClampedArray(img.rgba);
  for (const g of boxes) {
    const x0 = Math.max(0, Math.floor((g.x - PAD) * img.w)), y0 = Math.max(0, Math.floor((g.y - PAD) * img.h));
    const x1 = Math.min(img.w, Math.ceil((g.x + g.w + PAD) * img.w)), y1 = Math.min(img.h, Math.ceil((g.y + g.h + PAD) * img.h));
    for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) { const k = (y * img.w + x) * 4; out[k] = 0; out[k + 1] = 0; out[k + 2] = 0; out[k + 3] = 255; }
  }
  return { w: img.w, h: img.h, rgba: out };
}

export type ScanResult =
  | { ok: true; image: Rgba; boxes: Box[]; detail: Record<string, unknown> }
  | { ok: false; held: 'too_few_words' | 'no_title_block_found' | 'title_block_unread' | 'title_block_low_confidence' | 'identity_survived_reocr'; detail: Record<string, unknown> };

/** One page: OCR, box, paint, re-OCR, and return it only if the re-read is clean. */
export async function redactScan(img: Rgba, ocr: Ocr, seeds: string[]): Promise<ScanResult> {
  const first = await ocr(rgbaToBmp(img));
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
  // PAGE-WIDE: the names the title block prints (its words, tokenised) join the customer's seeds, and every line
  // anywhere that carries a company word, a licence number or one of those names - fuzzily - is boxed too.
  const stripTerms = [...new Set([...stripSeeds(page, strip), ...seedTerms({ extra: stripSeeds(page, strip) })])];
  const terms = [...new Set([...seeds, ...stripTerms])];
  const party = (t: string) => COMPANY.test(t) || LICENCE.test(t) || ID_TEXT.test(t) || !!seedHit(t, terms);
  const pageWide = page.runs.filter((r) => party(r.text)).map((r) => ({ x: r.x, y: r.y, w: r.w, h: r.h }));
  const boxes = [...tb.boxes[0], ...textLayerBoxes([page], 0).boxes, ...pageWide];
  // Every string the first pass saw as identity is looked for again on the painted page.
  const found = page.runs.filter((r) => ID_TEXT.test(r.text) || ID_LABEL.test(r.text) || residualScan(r.text, seeds).length > 0).map((r) => r.text);
  const again = [...new Set([...terms, ...found.filter((t) => t.length >= 6).map((t) => t.toLowerCase())])];
  const painted = paint(img, boxes);
  const second = await ocr(rgbaToBmp(painted));
  // The re-read: patterns, company words and licence numbers, and every seed matched FUZZILY (edit distance up to 2
  // after squashing), since the second OCR may shift a letter of a name the first read cleanly.
  const left = pageOf(second, img.w, img.h).runs.filter((r) => ID_TEXT.test(r.text) || ID_LABEL.test(r.text) || COMPANY.test(r.text) || LICENCE.test(r.text) || residualScan(r.text, again).length > 0 || !!seedHit(r.text, again));
  if (left.length) return { ok: false, held: 'identity_survived_reocr', detail: { lines: left.length } };
  return { ok: true, image: painted, boxes, detail: { method: 'scan_ocr', words: ws.length, title_conf: Math.round(titleConf), boxes: boxes.length, reocr_lines: second.length } };
}
