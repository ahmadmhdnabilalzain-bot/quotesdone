// anonymise — the gate before a supplier sees a drawing or a BOQ. Fixtures are built in memory.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/anonymise.test.ts
//
// Positive controls: the customer's name, phone, email, plot and Makani are present BEFORE and
// absent AFTER; every identifying run on a PDF sheet sits inside a box; ordinary BOQ words survive.
// Fail-closed controls: a scan page is 'low'; a seed the redactor cannot cut out holds the BOQ.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages, type PdfPage } from './pdf_text_positions.ts';
import { neutralName, norm, redactBoq, redactText, residualScan, seedTerms, titleBlockBoxes } from './anonymise.ts';

const LATIN1 = (s: string) => Uint8Array.from(s, (c) => c.charCodeAt(0) & 0xff);
function makePdf(lines: [number, number, string][]): Uint8Array {
  const content = lines.map(([x, y, t]) => `BT /F1 10 Tf 1 0 0 1 ${x} ${y} Tm (${t}) Tj ET`).join('\n');
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 1000 700] >>',
    '<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  objs.forEach((o, i) => { pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return LATIN1(pdf + 'trailer << /Root 1 0 R >>\n%%EOF\n');
}

const SEEDS = seedTerms({
  name: 'Mr Khalid Al Mansouri', email: 'khalid@mansouri-family.ae', phone: '+971 50 123 4567',
  project: 'Mansouri Villa Jumeirah', plot: '345-678', makani: '12345 67890',
});

Deno.test('seed terms: names, email parts, phone digits; generic words dropped', () => {
  for (const s of ['khalid', 'mansouri', 'mr khalid al mansouri', '501234567', '345678', '1234567890', 'jumeirah']) assert(SEEDS.includes(s), 'seed ' + s);
  for (const g of ['villa', 'dubai', 'llc', 'mr', 'al']) assert(!SEEDS.includes(g), 'generic word is not a seed: ' + g);
  assert(seedTerms({ name: 'أحمد المنصوري' }).includes('احمد'), 'alef variant normalised');
  assert(seedTerms({ name: 'أحمد المنصوري' }).includes('منصوري'), 'al- prefix also seeded bare');
  assert(!seedTerms({ company: 'Marble Tech LLC' }).includes('marble'), 'BOQ vocabulary never a lone seed');
});

Deno.test('generic identifiers are removed; ordinary BOQ text is not touched', () => {
  const src = 'Plot No. 345-679, Makani 22345 67891, P.O. Box 9876, call 050 765 4321, ops@acme.ae, Villa 12 Al Wasl Road, DWG No. A-101, DEWA 2003456789, قطعة رقم ٣٤٥';
  const r = redactText(src, []);
  for (const leak of ['345-679', '22345', '9876', '765 4321', 'acme', 'Villa 12', 'Wasl', 'A-101', '2003456789', '٣٤٥']) assert(!r.text.includes(leak), `removed: ${leak} -> ${r.text}`);
  assert(r.hits >= 8);
  assertEquals(residualScan(r.text, []), []);
  for (const ok of ['Porcelain tiles 600x600 to wall, 45 sqm', 'SKIRTING 45 lm', 'D1 SINGLE LEAF DOOR 900x2100 6 nos', 'Gypsum ceiling 32.5 m2']) {
    assertEquals(redactText(ok, SEEDS).text, ok, 'no false removal: ' + ok);
  }
});

Deno.test('label lines lose their value: Client:, Drawn by, المالك:', () => {
  const t = redactText('Client: Omar Haddad\nDRAWN BY SK\nالمالك: عمر حداد\nPorcelain tile 20 sqm', []).text;
  for (const leak of ['Omar', 'SK', 'عمر']) assert(!t.includes(leak), 'removed ' + leak + ': ' + t);
  assert(t.includes('Porcelain tile 20 sqm'));
});

Deno.test('Arabic seeds match through diacritics and alef variants', () => {
  const seeds = seedTerms({ name: 'احمد المنصوري' });
  const src = 'فيلا المنصوريّ — السيد أحمد، بلاط بورسلان ٢٠ م٢';
  assert(norm(src).includes('منصوري') && norm(src).includes('احمد'), 'present before');
  const t = redactText(src, seeds).text;
  assert(!norm(t).includes('منصوري') && !norm(t).includes('احمد'), 'absent after: ' + t);
  assert(t.includes('بلاط بورسلان'), 'trade words kept');
});

Deno.test('BOQ: client name gone from section/description/summary; residual holds (fail-closed)', () => {
  const boq = {
    drawing_type: 'Mansouri Villa ground floor', summary: 'Flooring for Mr Khalid Al Mansouri, call +971 50 123 4567',
    boq: [
      { section: 'Mansouri residence', item: 'PORCELAIN TILE', description: 'Porcelain tiles 600x600 to wall for Khalid', qty: 32.5, unit: 'sqm', basis: 'printed on page 1: "LIVING ROOM PORCELAIN TILE 32.5 m2"', confidence: 'medium' },
    ],
    keywords: ['tiles', 'mansouri'], assumptions: ['Plot 345-678 access by road'], missing_info: ['Read from the PDF text layer only.'],
  };
  const before = JSON.stringify(boq).toLowerCase();
  assert(before.includes('mansouri') && before.includes('khalid') && before.includes('123 4567'));
  const r = redactBoq(boq, SEEDS);
  const after = JSON.stringify(r.boq).toLowerCase();
  for (const leak of ['mansouri', 'khalid', '123 4567', '345-678']) assert(!after.includes(leak), 'absent: ' + leak);
  assertEquals(r.held, false, r.reasons.join('; '));
  assertEquals(r.boq.boq[0].item, 'PORCELAIN TILE');
  assertEquals(r.boq.boq[0].qty, 32.5);
  assertEquals(r.boq.boq[0].unit, 'sqm');

  // Glued into one word, the name escapes word-boundary redaction — and the scan must catch it.
  const glued = redactBoq({ summary: 'Fit-out for AlMansouriGroup HQ' }, SEEDS);
  assertEquals(glued.held, true);
  assert(glued.reasons.includes('seed:mansouri'));
  assertEquals(redactBoq({ summary: 'tiles' }, []).held, true, 'no seeds = cannot prove absence = held');
});

const SHEET = makePdf([
  [50, 680, 'MANSOURI RESIDENCE GROUND FLOOR PLAN'],
  [50, 620, 'LIVING ROOM PORCELAIN TILE 32.5 m2'],
  [50, 600, 'MASTER BEDROOM PARQUET 18 sqm'],
  [780, 200, 'REV DATE DESCRIPTION'],
  [780, 185, 'A 01/09/2026 ISSUED FOR TENDER'],
  [780, 140, 'CLIENT: MR KHALID AL MANSOURI'],
  [780, 125, 'PROJECT: MANSOURI VILLA JUMEIRAH'],
  [780, 110, 'PLOT NO. 345-678 MAKANI 12345 67890'],
  [780, 95, 'DRAWN BY: AK CHECKED: RS'],
  [780, 80, 'DWG NO. A-101'],
  [780, 65, 'Tel +971 50 123 4567'],
  [780, 50, 'khalid@mansouri-family.ae'],
]);
const inside = (b: { x: number; y: number; w: number; h: number }, r: { x: number; y: number; w: number; h: number }) =>
  r.x >= b.x && r.y >= b.y && r.x + r.w <= b.x + b.w + 1e-9 && r.y + r.h <= b.y + b.h + 1e-9;

Deno.test('title block: every seed/identity run is boxed, the schedule is not', async () => {
  const pages = await pdfPages(SHEET);
  const out = titleBlockBoxes(pages, SEEDS);
  assertEquals(out.confidence, 'medium', out.residual.join('; '));
  assertEquals(out.residual, []);
  const boxes = out.boxes[0];
  const ident = pages[0].runs.filter((r) => residualScan(r.text, SEEDS).length || /CLIENT|DRAWN|DWG|REV|Tel/.test(r.text));
  assertEquals(ident.length, 9);
  for (const r of ident) assert(boxes.some((b) => inside(b, r)), 'boxed: ' + r.text);
  const revRow = pages[0].runs.find((r) => r.text.startsWith('A 01/09/2026'))!;
  assert(boxes.some((b) => inside(b, revRow)), 'revision table row boxed with its header');
  for (const r of pages[0].runs.filter((r) => /LIVING ROOM|MASTER BEDROOM/.test(r.text))) assert(!boxes.some((b) => inside(b, r)), 'not boxed: ' + r.text);
  for (const b of boxes) assert(b.x >= 0 && b.y >= 0 && b.x + b.w <= 1 + 1e-9 && b.y + b.h <= 1 + 1e-9, 'normalised 0..1');
});

Deno.test('a scan page (no text layer) is low confidence: the caller must hold', () => {
  const scan: PdfPage = { width: 1000, height: 700, rotate: 0, runs: [] };
  const out = titleBlockBoxes([scan], SEEDS);
  assertEquals(out.confidence, 'low');
  assertEquals(out.boxes, [[]]);
  assertEquals(titleBlockBoxes([], SEEDS).confidence, 'low');
});

Deno.test('text with no findable title block is low (it is likely vectors or a form)', () => {
  const p: PdfPage = { width: 1000, height: 700, rotate: 0, runs: [{ text: 'GROUND FLOOR PLAN', x: 0.1, y: 0.1, w: 0.1, h: 0.014 }] };
  assertEquals(titleBlockBoxes([p], SEEDS).confidence, 'low');
});

Deno.test('neutral file name carries nothing of the customer', () => {
  const n = neutralName('.JPG', 'Khalid Al Mansouri drawing.pdf', 1);
  assert(/^rfq-[0-9a-f]{8}-drawing-01\.jpg$/.test(n), n);
  assertEquals(n, neutralName('jpg', 'Khalid Al Mansouri drawing.pdf', 1), 'deterministic');
  assert(!n.toLowerCase().includes('mansouri'));
});
