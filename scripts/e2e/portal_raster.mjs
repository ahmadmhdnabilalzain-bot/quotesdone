// scripts/e2e/portal_raster.mjs — a PDF rasterised EXACTLY as the customer portal does it (src/components/me/pdfRaster.ts:
// pdf.js in a browser, long edge 2600 px, JPEG 0.8, at most 20 pages). Moved out of drawing_reaches_suppliers.mjs on
// 3 Nov 2026 so every_drawing_format_is_read.mjs sends a PDF drawing through the same door the portal uses.
import http from 'node:http';

// ── rasterise exactly as src/components/me/pdfRaster.ts does ──────────────────────────────────────────
export async function rasterise(pdf) {
  const { chromium } = await import('playwright');
  const PDFJS = new URL('../../node_modules/pdfjs-dist/build/', import.meta.url);
  const srv = http.createServer(async (q, s) => {
    if (q.url === '/doc.pdf') { s.setHeader('Content-Type', 'application/pdf'); return s.end(pdf); }
    if (q.url === '/') { s.setHeader('Content-Type', 'text/html'); return s.end('<!doctype html><title>r</title>'); }
    const f = new URL('.' + q.url.replace('/pdfjs/', '/'), PDFJS);
    try { const { readFileSync } = await import('node:fs'); s.setHeader('Content-Type', 'text/javascript'); s.end(readFileSync(f)); } catch { s.statusCode = 404; s.end(); }
  });
  await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
  const port = srv.address().port;
  const b = await chromium.launch(); const pg = await b.newPage();
  await pg.goto(`http://127.0.0.1:${port}/`);
  const images = await pg.evaluate(async () => {
    const pdfjs = await import('/pdfjs/pdf.min.mjs');
    pdfjs.GlobalWorkerOptions.workerSrc = '/pdfjs/pdf.worker.min.mjs';
    // pdfjs-dist 6 refuses a bare string ("getDocument - expected either data, range, or url"): 18 Oct, run 39079803518.
    const pdf = await pdfjs.getDocument({ url: '/doc.pdf' }).promise; const out = [];
    for (let p = 1; p <= Math.min(pdf.numPages, 20); p++) {
      const page = await pdf.getPage(p); const v1 = page.getViewport({ scale: 1 });
      const vp = page.getViewport({ scale: Math.min(1.8, 2600 / Math.max(v1.width, v1.height)) });
      const c = document.createElement('canvas'); c.width = Math.round(vp.width); c.height = Math.round(vp.height);
      await page.render({ canvasContext: c.getContext('2d'), viewport: vp }).promise;
      out.push({ mime: 'image/jpeg', data: c.toDataURL('image/jpeg', 0.8).split(',')[1], w: c.width, h: c.height });
    }
    return out;
  });
  await b.close(); srv.close();
  return images;
}
