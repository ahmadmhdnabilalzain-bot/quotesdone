// PDF -> page images, in the browser, with pdf.js served from our own bundle.
//
// This used to inject https://cdnjs.cloudflare.com/.../pdf.min.js at runtime. On a network that
// blocks cdnjs (common on corporate and site Wi-Fi) the script never loaded, the catch returned
// images:[] and the customer was told the file "could not be read" — a transport failure reported as
// a bad drawing (website audit 14 Sep 2026). pdfjs-dist is now a dependency: the library is a
// dynamic import (only fetched when a PDF is actually attached, so it costs the portal's first
// load nothing) and the worker is bundled through new URL(..., import.meta.url).

// scale 1.8 assumed a letter-sized page. A real construction sheet is ANSI D or A1, so 1.8 produced
// 21-megapixel pages and drawing_redact's isolate was killed (HTTP 546 on a single page). The long
// edge is capped at 2600px, which extracted 23 BoQ line items from the same schedules.
const MAX_EDGE = 2600;
// 21 Sep 2026 (sales_engineer, founder instruction 580): this was 6. The real 8-sheet mechanical
// permit set measured today put its floor plan and roof plan on sheets 7 and 8, so neither was ever
// rendered, OCR'd or shared. customer_api analyze_drawing caps at the same number (MAX_DRAWING_PAGES).
export const PDF_MAX_PAGES = 20;

let lib: Promise<any> | null = null;
export function loadPdfjs(): Promise<any> {
  if (!lib) {
    lib = import('pdfjs-dist').then((m: any) => {
      const pdfjs = m.default || m;
      try {
        pdfjs.GlobalWorkerOptions.workerPort = new Worker(new URL('pdfjs-dist/build/pdf.worker.min.mjs', import.meta.url), { type: 'module' });
      } catch (_e) { /* no Worker (very old browser): pdf.js falls back to its fake worker */ }
      return pdfjs;
    });
  }
  return lib;
}

export async function openPdf(bytes: Uint8Array): Promise<any> {
  const pdfjs = await loadPdfjs();
  // pdf.js takes ownership of (detaches) the buffer it is given; a copy keeps the caller's bytes usable.
  return pdfjs.getDocument({ data: bytes.slice() }).promise;
}

/** Each sheet's own text and the page count, for the glance said at once (./drawingGlance.ts, 19 Nov 2026). Text only: no
 *  page is rendered, so it answers before rasterisePdf. Shown to the customer only; never sent. */
export async function pdfPageTexts(bytes: Uint8Array): Promise<{ pages: number; texts: string[] }> {
  const pdf = await openPdf(bytes);
  const n = Math.min(pdf.numPages, PDF_MAX_PAGES);
  const texts: string[] = [];
  for (let p = 1; p <= n; p++) {
    const page = await pdf.getPage(p);
    const tc = await page.getTextContent();
    texts.push((tc.items || []).map((it: any) => String(it?.str || '')).join(' '));
    page.cleanup();
  }
  return { pages: n, texts };
}

export async function rasterisePdf(bytes: Uint8Array): Promise<{ mime: string; data: string }[]> {
  const pdf = await openPdf(bytes);
  const out: { mime: string; data: string }[] = [];
  const n = Math.min(pdf.numPages, PDF_MAX_PAGES);
  for (let p = 1; p <= n; p++) {
    const page = await pdf.getPage(p);
    const v1 = page.getViewport({ scale: 1 });
    const vp = page.getViewport({ scale: Math.min(1.8, MAX_EDGE / Math.max(v1.width, v1.height)) });
    const c = document.createElement('canvas');
    c.width = Math.round(vp.width); c.height = Math.round(vp.height);
    // ANNOTATIONS ARE NOT DRAWN (13 Nov 2026, independent review of the anonymity fix, item 3): pdf.js draws them by
    // default, so a FreeText markup "Owner Kareem asks for blue tiles - Villa 15 Al Barsha 2" reached a supplier's page
    // although no server rule reads /Annots. Annotations are not the drawing; the released vector file drops them too
    // (pdf_vector_redact DROP_PAGE). 0 = pdf.js AnnotationMode.DISABLE.
    await page.render({ canvasContext: c.getContext('2d') as CanvasRenderingContext2D, viewport: vp, annotationMode: 0 } as any).promise;
    out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1] });
    page.cleanup();
  }
  return out;
}

// ── A PAGE AT READING RESOLUTION, AS ONE GRAYSCALE BUFFER (21 Sep 2026) ──────────────────────────────
// The schedule reader (ocrClient.ocrSchedules + supabase/functions/_shared/table_grid.ts) needs the
// sheet at ~200 dpi, not 72: a 36x24 sheet is then 7200x4800 = 34.6 MP. Safari refuses a canvas over
// 16,777,216 px (4096^2), so the page is rendered in TILES of at most 4000x4000 through viewport
// offsets and each tile's luma copied into one Uint8Array (1 byte/px: 34.6 MB for that sheet). One tile
// canvas exists at a time. A page that would exceed MAX_GRAY_PX at the asked dpi is rendered at the dpi
// that fits (an A0 sheet at 200 dpi would be 62 MP), so memory stays bounded whatever is uploaded.
const TILE = 4000;
const MAX_GRAY_PX = 48_000_000;

export type GrayPage = { data: Uint8Array; w: number; h: number; dpi: number };

export async function renderPageGray(src: any, pageNo: number, dpi = 200, maxPx = MAX_GRAY_PX): Promise<GrayPage> {
  const pdf = src instanceof Uint8Array ? await openPdf(src) : src;
  const page = await pdf.getPage(pageNo);
  const v1 = page.getViewport({ scale: 1 }); // 72 units per inch, in the display frame (after /Rotate)
  let scale = dpi / 72;
  const px = v1.width * v1.height * scale * scale;
  if (px > maxPx) scale *= Math.sqrt(maxPx / px);
  const W = Math.round(v1.width * scale), H = Math.round(v1.height * scale);
  const out = new Uint8Array(W * H);
  const c = document.createElement('canvas');
  const ctx = c.getContext('2d', { willReadFrequently: true }) as CanvasRenderingContext2D;
  for (let ty = 0; ty < H; ty += TILE) {
    for (let tx = 0; tx < W; tx += TILE) {
      const tw = Math.min(TILE, W - tx), th = Math.min(TILE, H - ty);
      c.width = tw; c.height = th;
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, tw, th);
      const vp = page.getViewport({ scale, offsetX: -tx, offsetY: -ty });
      await page.render({ canvasContext: ctx, viewport: vp, annotationMode: 0 } as any).promise;   // as above: no annotations
      const d = ctx.getImageData(0, 0, tw, th).data;
      for (let y = 0; y < th; y++) {
        let o = (ty + y) * W + tx, i = y * tw * 4;
        for (let x = 0; x < tw; x++, i += 4) out[o++] = (d[i] * 77 + d[i + 1] * 150 + d[i + 2] * 29) >> 8;
      }
    }
  }
  c.width = c.height = 0; // release the tile's backing store now, not at the next GC
  page.cleanup();
  return { data: out, w: W, h: H, dpi: scale * 72 };
}
