// Finds text that overlaps other text in a rendered PDF, read back out of the PDF file itself.
//   node scripts/legal/pdf_text_overlaps.mjs <file.pdf> [...more]      exit 1 when any page has an overlap
// Every text run pdf.js extracts becomes a box: x..x+width across, baseline-0.22*size..baseline+0.78*size
// up. Two boxes that share more than 0.75pt in BOTH directions overlap — ink on ink. Runs laid end to end
// on one line touch but do not overlap, so they pass.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const require = createRequire(import.meta.url);
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')).href);
pdfjs.GlobalWorkerOptions.workerSrc = pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.worker.mjs')).href;

const EPS = 0.75;
export async function overlapsIn(bytes) {
  const doc = await pdfjs.getDocument({ data: new Uint8Array(bytes), disableFontFace: true, verbosity: 0 }).promise;
  const found = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const { items } = await page.getTextContent();
    const boxes = items.filter((it) => it.str && it.str.trim() && it.width > 0).map((it) => {
      const size = Math.hypot(it.transform[2], it.transform[3]) || it.height || 8;
      const x = it.transform[4], y = it.transform[5];
      return { s: it.str, x0: x, x1: x + it.width, y0: y - 0.22 * size, y1: y + 0.78 * size };
    });
    for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
      const a = boxes[i], b = boxes[j];
      const w = Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0), h = Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0);
      if (w > EPS && h > EPS) found.push({ page: p, a: a.s.slice(0, 50), b: b.s.slice(0, 50), w: +w.toFixed(1), h: +h.toFixed(1) });
    }
  }
  return found;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  let bad = 0;
  for (const f of process.argv.slice(2)) {
    const o = await overlapsIn(readFileSync(f));
    console.log(`${o.length ? 'OVERLAP' : 'ok     '} ${f}${o.length ? '  ' + o.length : ''}`);
    for (const x of o.slice(0, 8)) console.log(`    p${x.page}  "${x.a}"  ×  "${x.b}"  (${x.w}×${x.h}pt)`);
    if (o.length) bad++;
  }
  process.exit(bad ? 1 : 0);
}
