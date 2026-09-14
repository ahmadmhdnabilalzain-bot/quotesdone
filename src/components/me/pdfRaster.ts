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
const MAX_PAGES = 6;

let lib: Promise<any> | null = null;
function loadPdfjs(): Promise<any> {
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

export async function rasterisePdf(bytes: Uint8Array): Promise<{ mime: string; data: string }[]> {
  const pdfjs = await loadPdfjs();
  const pdf = await pdfjs.getDocument({ data: bytes }).promise;
  const out: { mime: string; data: string }[] = [];
  const n = Math.min(pdf.numPages, MAX_PAGES);
  for (let p = 1; p <= n; p++) {
    const page = await pdf.getPage(p);
    const v1 = page.getViewport({ scale: 1 });
    const vp = page.getViewport({ scale: Math.min(1.8, MAX_EDGE / Math.max(v1.width, v1.height)) });
    const c = document.createElement('canvas');
    c.width = Math.round(vp.width); c.height = Math.round(vp.height);
    await page.render({ canvasContext: c.getContext('2d') as CanvasRenderingContext2D, viewport: vp }).promise;
    out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1] });
  }
  return out;
}
