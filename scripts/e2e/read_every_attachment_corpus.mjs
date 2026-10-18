// scripts/e2e/read_every_attachment_corpus.mjs — the SYNTHETIC ZZ DEMO sample for ruling 1177 (every attachment is read).
// Assigned: sales_engineer + customer_support (reading), it_engineer (the harness).
//
// Every file is INVENTED and generated from code: no real customer, supplier or project; every name starts "ZZ DEMO".
// Each file carries the words that MUST come back when it is read (truth.json `must`), and a quotation its total.
// Covered: a text BOQ PDF, the same BOQ as a phone-style scan (JPG) and as an image-only scanned PDF, a drawing as a
// vector PDF and as a PNG, a supplier quotation as a text PDF and as a skewed photo, and ONE deliberately degraded
// file (a tiny, heavily blurred scan) that is expected to be held — the only "unreadable" the ruling allows.
//
//   node scripts/e2e/read_every_attachment_corpus.mjs --out <dir>
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';
import { demoPdf, demoOfficePlanPdf, demoOfficePlanPng } from '../lib/demo_pdf.mjs';

const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const BOQ = ['ZZ DEMO Fitout - Bill of Quantities', 'Item  Description                      Qty   Unit',
  '1     Gypsum board false ceiling         120   m2', '2     Emulsion paint to walls            300   m2',
  '3     Split AC unit 1.5 TR               12    nos', '4     Porcelain floor tiles 600x600      85    m2'];
const QUOTE = ['ZZ DEMO Interiors LLC - Quotation Q-0091', 'Item  Description                 Qty   Rate    Amount',
  '1     Gypsum partition            120   95      11400', '2     Emulsion paint              300   12      3600',
  'Total AED 15000', 'Validity 30 days. Payment 50% advance.'];

const svgPage = (lines, w = 1240, h = 1000) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#fbfbf6"/>`
  + lines.map((l, k) => `<text x="70" y="${110 + k * 72}" font-family="Courier New, monospace" font-size="30" fill="#111">${xml(l)}</text>`).join('') + '</svg>');

/** An image-only PDF (one JPEG painted over the page): what a scanner writes. No text layer at all. */
function scannedPdf(jpeg, w, h) {
  const objs = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>',
    { dict: `<< /Type /XObject /Subtype /Image /Width ${w} /Height ${h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>`, data: jpeg }];
  const c = Buffer.from('q 595 0 0 842 0 0 cm /Im1 Do Q\n', 'latin1');
  objs.push({ dict: `<< /Length ${c.length} >>`, data: c });
  const parts = [Buffer.from('%PDF-1.4\n%\xe2\xe3\xcf\xd3\n', 'latin1')]; let len = parts[0].length; const offs = [];
  objs.forEach((o, i) => {
    offs.push(len);
    const b = typeof o === 'string' ? Buffer.from(`${i + 1} 0 obj\n${o}\nendobj\n`, 'latin1')
      : Buffer.concat([Buffer.from(`${i + 1} 0 obj\n${o.dict}\nstream\n`, 'latin1'), o.data, Buffer.from('\nendstream\nendobj\n', 'latin1')]);
    parts.push(b); len += b.length;
  });
  parts.push(Buffer.from(`xref\n0 ${objs.length + 1}\n0000000000 65535 f \n` + offs.map((o) => String(o).padStart(10, '0') + ' 00000 n \n').join('')
    + `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${len}\n%%EOF\n`, 'latin1'));
  return Buffer.concat(parts);
}

export async function buildCorpus(out) {
  mkdirSync(out, { recursive: true });
  const docs = [];
  const save = (id, file, bytes, mime, meta) => { writeFileSync(join(out, file), bytes); docs.push({ id, file, mime, ...meta }); };
  const boqMust = ['gypsum', '120', 'paint', '300', 'split'];
  save('boq_text_pdf', 'zz_boq_text.pdf', demoPdf(BOQ.map((l) => [l, 11])), 'application/pdf', { path: 'customer BOQ (customer_api analyze_document)', must: boqMust, degraded: false });
  const boqJpg = await sharp(await sharp(svgPage(BOQ)).png().toBuffer()).rotate(2, { background: '#ffffff' }).blur(0.6).jpeg({ quality: 78 }).toBuffer();
  save('boq_scan_jpg', 'zz_boq_scan.jpg', boqJpg, 'image/jpeg', { path: 'customer BOQ photo (drawing_boq document mode)', must: boqMust, degraded: false });
  const boqFlat = await sharp(svgPage(BOQ)).flatten({ background: '#ffffff' }).jpeg({ quality: 80 }).toBuffer();
  const m = await sharp(boqFlat).metadata();
  save('boq_scan_pdf', 'zz_boq_scan.pdf', scannedPdf(boqFlat, m.width, m.height), 'application/pdf', { path: 'scanned BOQ PDF (doc_extract / drawing_boq)', must: boqMust, degraded: false });
  const planMust = ['meeting', 'room'];
  save('drawing_pdf', 'zz_plan.pdf', demoOfficePlanPdf(), 'application/pdf', { path: 'drawing PDF (drawing_boq)', must: planMust, degraded: false });
  save('drawing_png', 'zz_plan.png', demoOfficePlanPng(), 'image/png', { path: 'drawing PNG (drawing_boq photo)', must: planMust, degraded: false });
  const qMust = ['gypsum', '15000'];
  save('quote_text_pdf', 'zz_quote_text.pdf', demoPdf(QUOTE.map((l) => [l, 11])), 'application/pdf', { path: 'supplier quotation (quote review / quote_extract)', must: qMust, total: 15000, degraded: false });
  const qJpg = await sharp(await sharp(svgPage(QUOTE)).png().toBuffer()).affine([[1, 0.04], [0.02, 0.98]], { background: '#d8d8d8' }).rotate(-2, { background: '#d8d8d8' }).blur(0.7).jpeg({ quality: 72 }).toBuffer();
  save('quote_scan_jpg', 'zz_quote_scan.jpg', qJpg, 'image/jpeg', { path: 'supplier quotation photo (quote review)', must: qMust, total: 15000, degraded: false });
  // DELIBERATELY DEGRADED: 120 px wide and blurred to mush. The ruling's one allowed "unreadable".
  const bad = await sharp(await sharp(svgPage(BOQ)).png().toBuffer()).resize(120).blur(6).jpeg({ quality: 20 }).toBuffer();
  save('degraded_jpg', 'zz_degraded.jpg', bad, 'image/jpeg', { path: 'deliberately degraded scan', must: [], degraded: true });
  writeFileSync(join(out, 'truth.json'), JSON.stringify({ built_at: new Date().toISOString(), docs }, null, 1));
  return docs;
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('read_every_attachment_corpus.mjs')) {
  const i = process.argv.indexOf('--out');
  if (i > 0) { const d = await buildCorpus(process.argv[i + 1]); console.log(`${d.length} documents in ${process.argv[i + 1]}`); }
}
