// released_file_pages — THE PAGES A BROWSER SENDS ARE THE PAGES OF THE FILE, OR THE FILE IS NOT RELEASED (second review
// of the anonymity fix, item 1, 13 Nov 2026, sales_engineer).
//
// MEASURED: drawing_redact mode 'verify_file' gated whatever JPEGs the caller sent for a pending vector PDF and released
// the file. Nothing tied them to the file: `images.slice(0, 20)`, so ONE image of a 5-page file released pages 2-5 that
// no model had seen, and a blank or unrelated image passed the model just as well. There is no PDF rasteriser in the
// edge runtime (pdf.js needs a canvas, no pdfium / mupdf wasm is bundled; imagescript decodes JPEG and PNG only), so the
// server cannot draw the pages itself. It reads the file instead and checks each image against its own reading:
//  1. COUNT: exactly one image per page of the pending file (pdfPages), at most PIXEL_PAGE_CAP pages, else held.
//  2. SHAPE: each image's aspect is the page's (MediaBox, quarter turns applied) within ASPECT_TOLERANCE.
//  3. INK: on an INK_GRID x INK_GRID grid, the cells where the file draws (text runs, stroked lines, paths, pictures,
//     layer strokes) must have ink in or beside them in the image (`cover` >= INK_COVER), and the image's ink must lie
//     in or beside cells where the file draws (`precision` >= INK_PRECISION). MEASURED on five sheets rendered by
//     pdftoppm at 2600 px (13 Nov 2026): every page against its own image 0.81-1.00 cover and 1.00 precision; a blank
//     image 0 cover; an image inked everywhere low precision; 15 of the 20 cross pairs (sheet A's file, sheet B's
//     image) refused, at 0.67-0.89 cover or 0.79-0.96 precision.
//     LIMIT: the 5 that passed print one template with different words in the same places (columns of notes), or are
//     the same sheet plus or minus one picture; such pages are not told apart at this grid; each image is still a page the model checks, and the count rule still holds.
//  4. DENSITY (round 3, 13 Nov 2026): a released FILE can be zoomed by the supplier, so its page image must carry the
//     pixels the tiles ask for (TILING: 6 pt at 12 px, 5.67 px a mm), within DENSITY_TOLERANCE. The gate scales a tile
//     UP to 12 px, so without this a 600 px image of an A1 sheet passed the count, shape and ink rules and the model was
//     shown 6 pt text at about 1.5 px, blurred to 12: nothing to read, "clean", and the vector file released.
//     An A3 page needs 2,381 px on its long side, an A1 page 4,769 px.
// Pure: drawing_redact/index.ts decodes the images (one per worker) and reads the file; this module only compares.
import type { PdfPage } from './pdf_text_positions.ts';
import { TILING } from './drawing_pixel_gate.ts';

export const INK_GRID = 32;
export const ASPECT_TOLERANCE = 0.03;
export const INK_COVER = 0.75;
export const INK_PRECISION = 0.97;

/** The page's display aspect (width / height), quarter turns applied. */
export const pageAspect = (p: Pick<PdfPage, 'width' | 'height' | 'rotate'>) => (Math.abs(p.rotate || 0) % 180 === 90 ? p.height / p.width : p.width / p.height);
export const aspectMatches = (p: Pick<PdfPage, 'width' | 'height' | 'rotate'>, wPx: number, hPx: number) => wPx > 0 && hPx > 0 && Math.abs((wPx / hPx) / pageAspect(p) - 1) <= ASPECT_TOLERANCE;

/** The grid cells (row-major booleans) where the file draws something. */
export function expectedInk(p: PdfPage, n = INK_GRID): boolean[] {
  const g = new Array(n * n).fill(false);
  const cell = (v: number) => Math.max(0, Math.min(n - 1, Math.floor(v * n)));
  const box = (x: number, y: number, w: number, h: number) => { for (let r = cell(y); r <= cell(y + h); r++) for (let c = cell(x); c <= cell(x + w); c++) g[r * n + c] = true; };
  const seg = (x1: number, y1: number, x2: number, y2: number) => { const k = Math.max(1, Math.ceil(Math.max(Math.abs(x2 - x1), Math.abs(y2 - y1)) * n * 2)); for (let i = 0; i <= k; i++) { const t = i / k; g[cell(y1 + (y2 - y1) * t) * n + cell(x1 + (x2 - x1) * t)] = true; } };
  for (const r of p.runs || []) if (r.text.trim()) box(r.x, r.y, r.w, r.h);
  for (const l of p.lines || []) seg(l.x1, l.y1, l.x2, l.y2);
  for (const im of p.images || []) box(im.x, im.y, im.w, im.h);
  // A path's box is drawn whole when small (a symbol, a hatch patch) or FILLED (a solid hatch, a poured slab); a large
  // stroked one (a border, a frame) only along its edge.
  for (const pa of p.paths || []) { if (pa.clip) continue; if (pa.w * pa.h < 0.02 || /(?:^|\s)(?:f\*?|F|B\*?|b\*?)\s*$/.test(pa.text)) box(pa.x, pa.y, pa.w, pa.h); else { seg(pa.x, pa.y, pa.x + pa.w, pa.y); seg(pa.x, pa.y + pa.h, pa.x + pa.w, pa.y + pa.h); seg(pa.x, pa.y, pa.x, pa.y + pa.h); seg(pa.x + pa.w, pa.y, pa.x + pa.w, pa.y + pa.h); } }
  for (const s of Object.values(p.layers || {})) for (let i = 0; i + 3 < s.length; i += 4) seg(s[i], s[i + 1], s[i + 2], s[i + 3]);
  for (const gr of p.glyphRows || []) box(gr.x, gr.y, gr.w, gr.h);
  return g;
}

const dilate = (g: boolean[], n: number) => g.map((_, i) => { const r = Math.floor(i / n), c = i % n; for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) { const rr = r + dr, cc = c + dc; if (rr >= 0 && cc >= 0 && rr < n && cc < n && g[rr * n + cc]) return true; } return false; });
/** Does the image's ink (cells, row-major) fall where the file draws, and only there? (See 3. INK above.) */
export function inkAgrees(expected: boolean[], seen: boolean[], n = INK_GRID): { ok: boolean; cover: number; precision: number } {
  const e = expected.filter(Boolean).length, s = seen.filter(Boolean).length;
  if (!e) return { ok: !s, cover: s ? 0 : 1, precision: s ? 0 : 1 };
  const nearSeen = dilate(seen, n), nearExpected = dilate(expected, n);
  const cover = expected.filter((x, i) => x && nearSeen[i]).length / e;
  const precision = s ? seen.filter((x, i) => x && nearExpected[i]).length / s : 0;
  return { ok: cover >= INK_COVER && precision >= INK_PRECISION, cover, precision };
}

export const DENSITY_TOLERANCE = 0.97;
/** The long side in px a page image must have for TILING.textPt text to be TILING.minTextPx px (see 4. DENSITY). */
export const pxNeeded = (p: Pick<PdfPage, 'width' | 'height'>) => Math.ceil(Math.max(p.width, p.height) * TILING.minTextPx / TILING.textPt);   // points to px: 1 pt of text at minTextPx / textPt px
/** Does an image of wPx x hPx carry the page at the density the tiles need? */
export const imageDenseEnough = (p: Pick<PdfPage, 'width' | 'height'>, wPx: number, hPx: number) => Math.max(wPx, hPx) >= DENSITY_TOLERANCE * pxNeeded(p);

/** The count rule: one image per page, and a page count the gate will check at all. */
export function pageCountHolds(pages: number, images: number, cap: number): string | null {
  if (pages < 1) return 'file_has_no_pages';
  if (pages > cap) return 'file_over_page_cap';
  if (images !== pages) return 'image_count_is_not_page_count';
  return null;
}
