// scan_takeoff — a SCANNED PDF drawing set counted by the real OCR engine, no model: the ZZ DEMO plumbing and HVAC
// sheet as a raster (slightly turned, speckled, no text layer), put into a PDF the way a scanner writes it (JPEG),
// then read back out, OCR'd and taken off. The count must be the hand count: FD-1 x7, WC-1 x5, FCU x3; and on a
// 2-sheet scanned set (plumbing + mechanical plan of the same floor) the 5 WCs drawn on both are counted ONCE.
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. --allow-env --allow-net=deno.land,esm.sh \
//     supabase/functions/_shared/scan_takeoff.check.ts
//
// A .check.ts for the same reason as scan_redact.check.ts: the OCR engine needs --allow-env and imagescript's codec
// fetches its .wasm, which the `npm test` Deno suite does not grant. Nothing real, nothing sent anywhere.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { scanPdfImages, scanTakeoff } from './scan_takeoff.ts';
import { PDF_COUNTS, zzScanRgba, zzScanText } from './doc_read/zz_demo_drawings.fixtures.ts';
import { tesseractOcr } from '../../../scripts/lib/scan_ocr.ts';

const FD: [number, number][] = [[160, 230], [330, 300], [520, 230], [650, 560], [900, 280], [1100, 560], [1420, 280]];
const WC: [number, number][] = [[160, 600], [420, 600], [1000, 230], [1200, 600], [1500, 560]];

/** One scanned sheet: the ZZ DEMO scan plus tagged fixtures and a view title. */
function sheet(view: string, fd: [number, number][], wc: [number, number][], fcu: string[], number = 'P-1.01') {
  const img = zzScanRgba({ rotateDeg: 0.3, noise: 0.001 });
  // Each sheet its own number, as a consultant issues a set (the fixture draws E-1.01 on every scan).
  for (let y = 1140; y < 1230; y++) for (let x = 1960; x < 2450; x++) { const k = (y * img.w + x) * 4; img.rgba[k] = img.rgba[k + 1] = img.rgba[k + 2] = 255; }
  zzScanText(img, 1970, 1200, 40, number);
  for (const [x, y] of fd) zzScanText(img, x, y, 26, 'FD-1');
  for (const [x, y] of wc) zzScanText(img, x, y, 26, 'WC-1');
  fcu.forEach((f, i) => zzScanText(img, 850 + i * 170, 470, 26, f));
  zzScanText(img, 600, 820, 34, view);
  return img;
}
/** A scanner's PDF, written by hand the way scanners write one: each page one JPEG (DCTDecode) painted over the
 *  whole sheet, no text layer. Hand-written, not a PDF library, so no test path makes a document (the template rule). */
/** A scanner's PDF, written by hand the way scanners write one: each page one JPEG (DCTDecode) painted over the
 *  whole sheet, no text layer. Hand-written, not a PDF library, so no test path makes a document (the template rule). */
async function scannedPdf(imgs: { w: number; h: number; rgba: Uint8ClampedArray }[]): Promise<Uint8Array> {
  const enc = (t: string) => new TextEncoder().encode(t);
  const parts: Uint8Array[] = [enc('%PDF-1.4\n')];
  const offs: number[] = []; let len = parts[0].length;
  const add = (...chunks: Uint8Array[]) => { offs.push(len); for (const c of chunks) { parts.push(c); len += c.length; } };
  const n = imgs.length, kids = imgs.map((_, i) => `${3 + i * 3} 0 R`).join(' ');
  add(enc('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'));
  add(enc(`2 0 obj\n<< /Type /Pages /Kids [${kids}] /Count ${n} >>\nendobj\n`));
  for (const [i, r] of imgs.entries()) {
    const im = new Image(r.w, r.h); im.bitmap.set(r.rgba);
    const jpg = await im.encodeJPEG(88);
    const W = (r.w * 0.72).toFixed(2), H = (r.h * 0.72).toFixed(2), page = 3 + i * 3;
    const content = `q ${W} 0 0 ${H} 0 0 cm /Im1 Do Q`;
    add(enc(`${page} 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /XObject << /Im1 ${page + 1} 0 R >> >> /Contents ${page + 2} 0 R >>\nendobj\n`));
    add(enc(`${page + 1} 0 obj\n<< /Type /XObject /Subtype /Image /Width ${r.w} /Height ${r.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpg.length} >>\nstream\n`), jpg, enc('\nendstream\nendobj\n'));
    add(enc(`${page + 2} 0 obj\n<< /Length ${content.length} >>\nstream\n${content}\nendstream\nendobj\n`));
  }
  const xref = len;
  const rows = offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('');
  parts.push(enc(`xref\n0 ${offs.length + 1}\n0000000000 65535 f \n${rows}trailer\n<< /Size ${offs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`));
  const out = new Uint8Array(parts.reduce((t, p) => t + p.length, 0));
  let k = 0; for (const p of parts) { out.set(p, k); k += p.length; }
  return out;
}
const qty = (boq: any, re: RegExp) => boq?.boq?.find((l: any) => re.test(l.description))?.qty;

Deno.test({ name: 'a scanned PDF sheet is counted: FD-1 x7, WC-1 x5, FCU x3 (hand count)', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const pdf = await scannedPdf([sheet('GROUND FLOOR PLUMBING AND HVAC PLAN', FD, WC, ['FCU-1', 'FCU-2', 'FCU-3'])]);
  const s = await scanPdfImages(pdf);
  assert(s.ok, JSON.stringify(s));
  if (!s.ok) return;
  const e = await tesseractOcr('eng+ara');
  try {
    const t = await scanTakeoff(s.pages, e.ocr);
    assert(t.boq, 'no take-off: ' + JSON.stringify(t.pages[0].runs.map((r) => r.text)));
    assertEquals([qty(t.boq, /FD-1/), qty(t.boq, /WC-1/), qty(t.boq, /FCU-1/), qty(t.boq, /FCU-2/), qty(t.boq, /FCU-3/)], [PDF_COUNTS['FD-1'], PDF_COUNTS['WC-1'], 1, 1, 1], JSON.stringify(t.boq.boq.map((l: any) => [l.description, l.qty])));
    assertEquals(JSON.stringify(t.boq).match(/ZZ|ORBIT|RASHID|KAREEM|HARBOUR|EXAMPLE|0017/gi), null, 'identity reached the scanned take-off');
  } finally { await e.done(); }
} });

Deno.test({ name: 'a 2-sheet scanned set: the WCs drawn on the plumbing AND the mechanical plan are counted once', sanitizeResources: false, sanitizeOps: false, fn: async () => {
  const pdf = await scannedPdf([sheet('GROUND FLOOR PLUMBING PLAN', FD, WC, ['FCU-1']), sheet('GROUND FLOOR MECHANICAL PLAN', [], WC, ['FCU-2', 'FCU-3'], 'M-1.01')]);
  const s = await scanPdfImages(pdf);
  assert(s.ok && s.pages.length === 2, JSON.stringify(s.ok ? s.pages.length : s));
  if (!s.ok) return;
  const e = await tesseractOcr('eng+ara');
  try {
    const t = await scanTakeoff(s.pages, e.ocr);
    assert(t.boq, 'no take-off');
    assertEquals([qty(t.boq, /FD-1/), qty(t.boq, /WC-1/)], [PDF_COUNTS['FD-1'], PDF_COUNTS['WC-1']], JSON.stringify(t.boq.boq.map((l: any) => [l.description, l.qty])));
  } finally { await e.done(); }
} });
