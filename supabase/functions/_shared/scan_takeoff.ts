// scan_takeoff — a SCANNED PDF drawing counted like a vector one (28 Sep 2026, sales_engineer; founder ledger 31,
// 580, 701: "the sales engineer reads it and counts the elements correctly").
//
// MEASURED BEFORE THIS FILE: a scanned PDF (no text layer) read as needs:'ocr' with 0 quantities
// (every_drawing_format.test.ts), and the CAD worker's scan job redacted the page pictures but returned boq:null.
// The take-off rules (drawing_boq/drawing_set.ts: plans only, tags per sheet, a WC drawn on two plans of the same
// floor counted once) read TEXT RUNS with positions, and OCR lines are exactly that once placed on the page.
//
// WHAT IT DOES: (1) scanPdfImages takes each page's scan out of the PDF — the largest image the page paints, as
// DCTDecode (JPEG, what scanners write) or FlateDecode 8-bit Gray / RGB; anything else (CCITT, JBIG2, JPX, a
// predictor, a page with no image) is said, never guessed. (2) scanTakeoff OCRs every page (scripts/lib/scan_ocr.ts
// on the CAD worker — the same pinned tesseract.js the customer's browser runs), turns the lines into the PdfPage
// shape (scan_redact.pageOf), and runs the SAME take-off as a vector set, then the #902 identity gate.
// It runs on the CAD worker (OCR is minutes of CPU, never the edge).
// deno-lint-ignore-file no-explicit-any
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { pageOf, rgbaToBmp, type Ocr, type OcrLine, type OcrWord, type Rgba } from './scan_redact.ts';
import type { PdfPage } from './pdf_text_positions.ts';
import { linesFromRuns, pdfPageImages } from './pdf_text_positions.ts';
import { boqFromDrawingSet } from '../drawing_boq/drawing_set.ts';
import { drawingIdentityTerms, gateDrawingBoq } from './drawing_identity_gate.ts';

export type ScanImages = { ok: true; pages: Rgba[] } | { ok: false; held: string; detail?: string };

/** Each page's scanned image (the largest one it paints), decoded to RGBA. Read with the estate's own PDF reader
 *  (pdf_text_positions.pdfPageImages): this file only READS a PDF, so it carries no PDF-writing library. */
export async function scanPdfImages(bytes: Uint8Array): Promise<ScanImages> {
  const imgs = await pdfPageImages(bytes);
  if (!imgs.length) return { ok: false, held: 'pdf_unreadable' };
  const pages: Rgba[] = [];
  for (const [i, im] of imgs.entries()) {
    if (!im) return { ok: false, held: 'scan_page_has_no_image', detail: `page ${i + 1}` };
    if (/\/DCTDecode\b/.test(im.dict)) {
      const img = await Image.decode(im.raw) as Image;
      pages.push({ w: img.width, h: img.height, rgba: new Uint8ClampedArray(img.bitmap) });
      continue;
    }
    if (im.inflated && /\/BitsPerComponent\s+8\b/.test(im.dict) && !/\/DecodeParms\b/.test(im.dict)) {
      const n = /\/ColorSpace\s*\/DeviceGray\b/.test(im.dict) ? 1 : /\/ColorSpace\s*\/DeviceRGB\b/.test(im.dict) ? 3 : 0;
      const raw = im.inflated, w = im.w, h = im.h;
      if (!n || raw.length < w * h * n) return { ok: false, held: 'scan_image_colour_space', detail: `page ${i + 1}` };
      const rgba = new Uint8ClampedArray(w * h * 4);
      for (let k = 0; k < w * h; k++) { const r = raw[k * n], g = raw[k * n + (n === 3 ? 1 : 0)], bb = raw[k * n + (n === 3 ? 2 : 0)]; rgba.set([r, g, bb, 255], k * 4); }
      pages.push({ w, h, rgba });
      continue;
    }
    return { ok: false, held: 'scan_image_codec', detail: `page ${i + 1}: ${(im.dict.match(/\/Filter\s*(\/\w+)/) || [])[1] || 'none'}` };
  }
  return { ok: true, pages };
}

/**
 * OCR lines split where the words stand apart. Sparse-text OCR joins labels on one baseline into one line
 * (measured on the ZZ scan: "FCU-2 FCU-3", two tags 70 px apart, came back as ONE line, so FCU-3 was never
 * counted), while CAD writes each label as its own run. A gap wider than GAP x the line's mean character width
 * starts a new run; ordinary word spacing ("MEETING ROOM 102") does not.
 */
export const GAP = 2.2;
export function labelLines(lines: OcrLine[]): OcrLine[] {
  const out: OcrLine[] = [];
  for (const l of lines) {
    const ws = (l.words || []).filter((w) => w.text.trim());
    if (ws.length < 2) { out.push(l); continue; }
    const chars = ws.reduce((a, w) => a + w.text.length, 0);
    const cw = ws.reduce((a, w) => a + (w.bbox.x1 - w.bbox.x0), 0) / Math.max(1, chars);
    let cur: OcrWord[] = [ws[0]];
    const flush = () => out.push({ text: cur.map((w) => w.text).join(' '), conf: Math.min(...cur.map((w) => w.conf)), words: cur,
      bbox: { x0: Math.min(...cur.map((w) => w.bbox.x0)), y0: Math.min(...cur.map((w) => w.bbox.y0)), x1: Math.max(...cur.map((w) => w.bbox.x1)), y1: Math.max(...cur.map((w) => w.bbox.y1)) } });
    for (let i = 1; i < ws.length; i++) {
      if (ws[i].bbox.x0 - ws[i - 1].bbox.x1 > GAP * cw) { flush(); cur = []; }
      cur.push(ws[i]);
    }
    flush();
  }
  return out;
}

/** OCR every scanned page and take it off with the vector set's rules, through the identity gate. */
export async function scanTakeoff(images: Rgba[], ocr: Ocr): Promise<{ pages: PdfPage[]; boq: any | null; found: string[] }> {
  const pages: PdfPage[] = [];
  for (const img of images) pages.push(pageOf(labelLines(await ocr(rgbaToBmp(img))), img.w, img.h));
  const set = boqFromDrawingSet(pages, '');
  if (!set) return { pages, boq: null, found: [] };
  const g = gateDrawingBoq(set, drawingIdentityTerms(linesFromRuns(pages)), false);
  return { pages, boq: g.boq, found: g.found };
}
