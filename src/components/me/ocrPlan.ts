// ocrPlan — HOW a drawing image is prepared for OCR. Pure: no browser API, no library, so the same
// plan runs in the customer's browser (ocrClient.ocrDrawing, via canvas) and in the fixture test
// (supabase/functions/drawing_boq/drawing_image_ocr.test.ts, via sharp). One plan, one measurement.
//
// MEASURED 14 Sep 2026 on the founder's sample fire alarm layout (1474 x 1038 px), tesseract.js 7.0.0
// LSTM, English, counting distinct "L1/NN" address tags read (70 exist):
//   one pass, the image as it is (the path customers had) ............................  0
//   3x upscale, luminance threshold 170, sparse-text mode (PSM 11), 1400 px tiles .... 37
//   the same with red ink removed first .............................................. 27  (worse)
//   the same keeping only blue ink (the tags are blue) ...............................  3  (far worse)
//   threshold 200 instead of 170 ..................................................... 13
//   PSM 6 (a uniform block) instead of 11 ............................................ 14
//   4x upscale, 1600 px tiles ........................................................ 39
//   union of the 4x and 3x passes, OCR-tolerant tag reading ........................... see the test
// Drawing text is small, scattered and never in paragraphs: upscaling gives the LSTM enough pixels
// per stroke, the threshold removes the anti-aliased haze around thin lines, and sparse mode stops
// tesseract from trying to flow a floor plan into columns. Tiles keep each recognise call inside
// tesseract's comfortable image size; they overlap by a third so a label cut by one tile edge is
// whole in the next (at 150 px overlap the drawing reference was read in two halves).
//
// WHAT IT DOES NOT DO: decide what the text means. That is drawing_from_ocr.ts on the server side.

export type Rect = { x: number; y: number; w: number; h: number };
export type OcrPass = { scale: number; tile: number; psm: '11' };
export type OcrLine = { text: string; bbox: Rect; pass: number };

/** Passes in the order they run. A phone gets the first only (see ocrDrawing). */
export const OCR_PASSES: OcrPass[] = [
  { scale: 4, tile: 1600, psm: '11' },
  { scale: 3, tile: 1400, psm: '11' },
];
export const THRESHOLD = 170;
export const OVERLAP = 1 / 3;
/** Longest side after upscaling. Bounds a canvas a browser can hold (4x of a 1500 px sheet is 6000). */
export const MAX_SIDE = 6400;

export function scaleFor(pass: OcrPass, w: number, h: number): number {
  return Math.max(1, Math.min(pass.scale, MAX_SIDE / Math.max(w, h)));
}

/** RGB(A) -> one byte per pixel, ink 0 / paper 255. Transparent pixels are paper. */
export function binarize(px: Uint8Array | Uint8ClampedArray, channels: 3 | 4, w: number, h: number): Uint8Array {
  const out = new Uint8Array(w * h);
  for (let i = 0, p = 0; i < out.length; i++, p += channels) {
    if (channels === 4 && px[p + 3] < 16) { out[i] = 255; continue; }
    const l = 0.299 * px[p] + 0.587 * px[p + 1] + 0.114 * px[p + 2];
    out[i] = l < THRESHOLD ? 0 : 255;
  }
  return out;
}

export function tiles(W: number, H: number, tile: number, overlap = OVERLAP): Rect[] {
  const step = Math.max(64, Math.round(tile * (1 - overlap)));
  const out: Rect[] = [];
  for (let y = 0; y < H; y += step) {
    for (let x = 0; x < W; x += step) {
      const w = Math.min(tile, W - x), h = Math.min(tile, H - y);
      if (w >= 64 && h >= 64) out.push({ x, y, w, h });
      if (x + tile >= W) break;
    }
    if (y + tile >= H) break;
  }
  return out;
}

/**
 * Lines from every tile and pass, in page coordinates (original pixels), with duplicates from tile
 * overlaps removed: the same text whose boxes overlap is one line. Sorted top-to-bottom, left-to-right,
 * so a label is followed by the value printed under it.
 */
export function mergeLines(lines: OcrLine[]): OcrLine[] {
  const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
  const kept: OcrLine[] = [];
  // Same place = the boxes overlap by more than half of the smaller one. Merely touching was not
  // enough: two stacked tags ("L1/17" over "L1/18") touch, and one of them was dropped.
  const same = (a: Rect, b: Rect) => {
    const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)), iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
    return ix * iy > 0.5 * Math.min(a.w * a.h, b.w * b.h);
  };
  for (const l of lines.map((l) => ({ ...l, text: norm(l.text) })).filter((l) => l.text.length > 0)) {
    const dup = kept.find((k) => same(k.bbox, l.bbox) && (k.text === l.text || k.text.includes(l.text) || l.text.includes(k.text)));
    if (dup) { if (l.text.length > dup.text.length) { dup.text = l.text; dup.bbox = l.bbox; } continue; }
    kept.push(l);
  }
  return kept.sort((a, b) => (Math.abs(a.bbox.y - b.bbox.y) < Math.min(a.bbox.h, b.bbox.h) * 0.5 ? a.bbox.x - b.bbox.x : a.bbox.y - b.bbox.y));
}

/** The text the server reads: one merged line per row. */
export const linesToText = (lines: { text: string }[]) => lines.map((l) => l.text).join('\n');

/**
 * The sheet's skew in degrees, by projection profile (19 Oct 2026, founder: deskew phone photos before OCR). Dark
 * pixels of a copy scaled to <= 800 px are projected onto rows at each angle in -6..6 (0.25 steps); text lines and
 * walls make the sharpest profile (largest sum of squared row counts) when level. The result is the CORRECTION:
 * rotate the image by it (clockwise positive, as canvas rotate and sharp.rotate). Measured on the sample sheet turned 1.5 deg: reads 1.5. ponytail: +-6 deg only; a photo held
 * sideways is the 90 deg turns' job.
 */
export function skewDegrees(px: Uint8Array | Uint8ClampedArray, channels: 3 | 4, w: number, h: number): number {
  const k = Math.max(1, Math.ceil(Math.max(w, h) / 800)), sw = Math.floor(w / k), sh = Math.floor(h / k);
  const xs: number[] = [], ys: number[] = [];
  for (let y = 0; y < sh; y++) for (let x = 0; x < sw; x++) {
    const p = ((y * k) * w + x * k) * channels;
    if (px[p] * 0.299 + px[p + 1] * 0.587 + px[p + 2] * 0.114 < 128) { xs.push(x - sw / 2); ys.push(y - sh / 2); }
  }
  let best = 0, bestScore = -1;
  const rows = new Float64Array(sw + sh + 4);
  for (let a = -6; a <= 6 + 1e-9; a += 0.25) {
    const t = a * Math.PI / 180, s = Math.sin(t), c = Math.cos(t);
    rows.fill(0);
    for (let i = 0; i < xs.length; i++) rows[Math.round(ys[i] * c + xs[i] * s + (sw + sh) / 2)]++;
    let score = 0; for (const r of rows) score += r * r;
    if (score > bestScore) { bestScore = score; best = a; }
  }
  return best;
}
