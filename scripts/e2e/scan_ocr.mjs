// scripts/e2e/scan_ocr.mjs: the words of a scanned PDF or a photo, read by code (OCR), for the accuracy harness.
// Seat: sales_engineer. 19 Oct 2026.
//
// WHY. A profile or catalogue with no text layer was read by the vision model, whose transcription code cannot check
// against the file, so its trades were held for the sales engineer (N07, N09, H01: every core trade "missed"). In the
// portal the supplier's own browser OCRs a scanned file (src/components/me/pdfRaster.ts renders each page with pdf.js on
// a canvas, ocrClient.ts reads it with tesseract.js); those words are code's reading of the file, so a quote can be
// checked against them. This runs the same pipeline: pdf.js renders each page in a headless Chromium (Playwright, already
// a dev dependency) at the portal's 2600 px long edge, and tesseract.js reads the PNG.
// Measured: rendering only the embedded images (an earlier version) read N09's catalogue as noise, because its words are
// vector outlines drawn over photos; the full-page render reads them.
//
//   node scripts/e2e/scan_ocr.mjs <file.pdf|.jpg|.png> [maxPages]   -> prints the text
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { createWorker } from 'tesseract.js';

export const OCR_MAX_PAGES = 20;   // = pdfRaster.PDF_MAX_PAGES
const MAX_EDGE = 2600;             // = pdfRaster.MAX_EDGE

async function renderPages(bytes, maxPages) {
  const { chromium } = await import('playwright');
  const pdfjsDir = join(dirname(createRequire(import.meta.url).resolve('pdfjs-dist/package.json')), 'build');
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.route('http://qd.local/**', (route) => {
      const f = new URL(route.request().url()).pathname.slice(1);
      if (f === 'doc.pdf') return route.fulfill({ body: Buffer.from(bytes), contentType: 'application/pdf' });
      if (f === 'index.html') return route.fulfill({ body: '<!doctype html><title>ocr</title>', contentType: 'text/html' });
      return route.fulfill({ body: readFileSync(join(pdfjsDir, f)), contentType: 'text/javascript' });
    });
    await page.goto('http://qd.local/index.html');
    return await page.evaluate(async ({ maxPages, maxEdge }) => {
      const pdfjs = await import('http://qd.local/pdf.min.mjs');
      pdfjs.GlobalWorkerOptions.workerSrc = 'http://qd.local/pdf.worker.min.mjs';
      const doc = await pdfjs.getDocument({ url: 'http://qd.local/doc.pdf' }).promise;
      const out = [];
      for (let p = 1; p <= Math.min(doc.numPages, maxPages); p++) {
        const pg = await doc.getPage(p);
        const v1 = pg.getViewport({ scale: 1 });
        const vp = pg.getViewport({ scale: maxEdge / Math.max(v1.width, v1.height) });
        const c = document.createElement('canvas'); c.width = Math.ceil(vp.width); c.height = Math.ceil(vp.height);
        const ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
        await pg.render({ canvasContext: ctx, viewport: vp }).promise;
        out.push(c.toDataURL('image/png').split(',')[1]);
      }
      return out;
    }, { maxPages, maxEdge: MAX_EDGE });
  } finally { await browser.close(); }
}

/** The OCR text of a scanned PDF or an image, pages in order. */
export async function ocrText(bytes, mime, maxPages = OCR_MAX_PAGES) {
  const pngs = /pdf/i.test(mime) ? (await renderPages(bytes, maxPages)).map((b) => Buffer.from(b, 'base64')) : [Buffer.from(bytes)];
  const worker = await createWorker(['eng']);
  if (process.env.QD_OCR_PSM) await worker.setParameters({ tessedit_pageseg_mode: process.env.QD_OCR_PSM });
  try {
    const parts = [];
    for (const png of pngs) parts.push((await worker.recognize(png)).data.text);
    return parts.join('\n');
  } finally { await worker.terminate(); }
}

if (process.argv[1]?.endsWith('scan_ocr.mjs') && process.argv[2]) {
  const f = process.argv[2];
  process.stdout.write(await ocrText(readFileSync(f), /\.pdf$/i.test(f) ? 'application/pdf' : 'image/' + f.split('.').pop(), Number(process.argv[3] || OCR_MAX_PAGES)));
}
