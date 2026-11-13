// boq_from_text + pdf_text_positions — a drawing's text layer read with no model.
// deno test supabase/functions/drawing_boq/boq_from_text.test.ts
//
// Positive control: a one-page PDF built here with a finish schedule, a door-schedule row and a
// title block. The schedule quantities must come back as BOQ lines; the title block's company,
// phone and email must NOT appear in any line (the output is shown to competing suppliers), and
// must be locatable in page coordinates so drawing_redact can box them.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { boqFromLines, boqFromPages } from './boq_from_text.ts';

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

const PDF = makePdf([
  [50, 650, 'FLOOR FINISH SCHEDULE'],
  [50, 620, 'LIVING ROOM PORCELAIN TILE 32.5 m2'],
  [50, 600, 'MASTER BEDROOM PARQUET 18 sqm'],
  [50, 580, 'SKIRTING 45 lm'],
  [50, 560, 'D1 SINGLE LEAF DOOR 900x2100 6'],
  [800, 60, 'AL NAHDA CONSULTANTS LLC'],
  [800, 45, 'Tel +971 4 555 1234'],
  [800, 30, 'info@alnahda-consult.ae'],
]);

Deno.test('text runs come back with page coordinates, top-left origin', async () => {
  const pages = await pdfPages(PDF);
  assertEquals(pages.length, 1);
  assertEquals(pages[0].rotate, 0);
  const tb = pages[0].runs.find((r) => r.text.includes('CONSULTANTS'))!;
  assert(tb.x > 0.75 && tb.y > 0.85, `title block run sits bottom-right (x=${tb.x}, y=${tb.y})`);
});

Deno.test('schedule quantities become BOQ lines; identity never does', async () => {
  const out = boqFromPages(await pdfPages(PDF));
  const find = (u: string, q: number) => out.boq.find((b) => b.unit === u && b.qty === q);
  assert(find('sqm', 32.5), 'living room area read');
  assert(find('sqm', 18), 'bedroom area read');
  assertEquals(find('lm', 45)?.confidence, 'medium');
  const door = out.boq.find((b) => b.item.startsWith('D1'));
  assert(door && door.qty === 6 && door.unit === 'nos' && door.confidence === 'low', 'schedule row counted, low confidence');
  const all = JSON.stringify(out.boq);
  for (const leak of ['CONSULTANTS', '555 1234', 'alnahda']) assert(!all.includes(leak), 'no identity in BOQ: ' + leak);
  assertEquals(out.method, 'pdf_text_layer');
  assert(out.missing_info[0].includes('no drawing geometry was measured'));
});

Deno.test('no text layer gives an empty boq and says why, never a guess', async () => {
  const out = boqFromPages(await pdfPages(LATIN1('not a pdf')));
  assertEquals(out.boq.length, 0);
  assert(out.missing_info.some((m) => m.includes('not a PDF we could open')));
});

Deno.test('a BOQ row whose description carries any Arabic is not read (suppliers always English)', () => {
  const items = boqFromLines([{ page: 1, text: '2.01 مقبس 13A socket nr 10' }, { page: 1, text: '2.02 13A twin socket outlet nr 4' }]);
  assertEquals(items.map((i) => i.description), ['13A twin socket outlet']);
});

Deno.test('the e-mail pattern is linear: 50 KB of "Al-Al-..." in milliseconds, and a 70-character local part still goes whole', async () => {
  // Second review of the anonymity fix (13 Nov 2026): without its lookbehind the pattern retried from every character and
  // took 1.6 s on this input; with it, 0.3-0.5 ms. No {1,64} bound: that would have left a 70-character address.
  const { EMAIL_RE } = await import('./boq_from_text.ts');
  const s = 'Al-'.repeat(17_000);
  const t0 = performance.now();
  s.replace(EMAIL_RE, '');
  const ms = performance.now() - t0;
  assert(ms < 150, `took ${ms.toFixed(0)} ms`);
  const long = 'x'.repeat(70) + '@example.invalid';
  assertEquals(('mail ' + long + ' now').replace(EMAIL_RE, ''), 'mail  now');
  assertEquals('zz.site@example.invalid'.replace(EMAIL_RE, ''), '');
});
