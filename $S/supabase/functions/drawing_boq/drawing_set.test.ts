// drawing_set — a CAD drawing SET is read, counted and redacted with no model (21 Sep 2026, sales_engineer,
// founder instruction 580). deno test -A supabase/functions/drawing_boq/drawing_set.test.ts
//
// The fixture below is SYNTHETIC (ZZ DEMO, 555 numbers) but built in exactly the shape measured on two
// real US bid sets that scored 0 of 49 on 21 Sep 2026 (they are copyrighted and never enter the repo):
//   * the page is /Rotate 270 and its /Contents is an ARRAY OBJECT ("/Contents 4 0 R", 4 = "[5 0 R]");
//   * every drawn word sits inside a Form XObject whose /Matrix turns the sheet (a CAD export), and the
//     title block is a second form NESTED inside it, with a logo image;
//   * tags are written the CAD way: "EF" over "1" in a bubble, "IRH-1" in one run, a VAV "RTU1-2" beside
//     its reheat "RTU1-2-H", an air device "A" beside its neck "8x8" over its airflow "180";
//   * the title block carries a US phone, a bare web host, a street address, a city/ZIP line and a
//     project name with no "Project:" label — every one of which the old scrubbers let through.
// Each assertion is a regression the real sets exposed: if one of those causes comes back, a test here fails.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { residualScan, titleBlockBoxes } from '../_shared/anonymise.ts';
import { supplierPageReadable } from '../_shared/supplier_copy.ts';
import { boqFromDrawingSet, normTag, tagCounts, takeoff } from './drawing_set.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { empty } from '../_shared/doc_read/types.ts';

import { IDENTITY, sheetPdf } from './drawing_set.fixtures.ts';

const pages = await pdfPages(sheetPdf());
const page = pages[0];
const run = (s: string) => page.runs.find((r) => r.text === s)!;

Deno.test('the reader follows the /Contents array, both nested forms, and reports runs in the DISPLAY frame', () => {
  assertEquals(pages.length, 1);
  assertEquals(page.rotate, 270);
  for (const s of [...IDENTITY, 'M1.0', 'IRH-1', 'RTU1-2-H', 'WC/L-1', 'SCALE:']) assert(run(s), `run missing: ${s}`);
  // Positions are where the sheet SHOWS them after /Rotate, not where the unrotated page keeps them.
  const irh = run('IRH-1'); assert(Math.abs(irh.x - 0.40) < 0.003 && Math.abs(irh.y + irh.h * 0.8 - 0.30) < 0.01, JSON.stringify(irh));
  const m10 = run('M1.0'); assert(m10.x > 0.92 && m10.y > 0.85, JSON.stringify(m10));
  assert(!irh.vertical, 'upright text is not vertical');
  assertEquals(page.images?.length, 1);
  assert(page.images![0].x > 0.92, 'the logo is placed in the title block');
  assert((page.lines || []).some((l) => l.x1 === l.x2 && Math.abs(l.x1 - 0.915) < 0.002 && l.y2 - l.y1 > 0.8), 'the border line is kept');
  assert(supplierPageReadable(page), 'a rotated page with a text layer can be published');
});

Deno.test('the take-off counts tags the way an estimator does', () => {
  const { sheets, lines } = takeoff(pages);
  assertEquals(sheets[0].number, 'M1.0');
  assertEquals(sheets[0].kind, 'plan');
  assertEquals(sheets[0].scale, '1/8" = 1\'-0"');
  const q = (type: string) => lines.find((l) => l.type === type);
  assertEquals(q('tag:EF-1')?.qty, 1, 'a bubble "EF" over "1", drawn twice, is one fan');
  assertEquals(q('tag:IRH-1')?.qty, 1);
  assert(q('tag:RTU1-2')?.description.includes('reheat'), 'the VAV box and its -H reheat tag are one box');
  assertEquals(q('tag:RTU1-2-H'), undefined);
  assertEquals(q('air_device:A')?.qty, 3); assertEquals(q('air_device:A')?.qty_status, 'read');
  assertEquals(q('air_device:B')?.qty, 2);
  assertEquals(q('air_device:C')?.qty, 1); assertEquals(q('air_device:C')?.qty_status, 'to_confirm', 'a letter only continuing the series is ours to confirm');
  assertEquals(q('tag:WC/L-1:new')?.qty, 2);
  assert(!lines.some((l) => l.type.includes('FCO')), '(E) existing to remain is not scope');
  const note = lines.find((l) => l.section === 'Keyed notes')!;
  assertEquals(note.qty, 2); assertEquals(note.qty_status, 'to_confirm');
  assert(!lines.some((l) => /REMAIN/.test(l.description)), 'a note with no bubble / to remain is not an item');
  const duct = q('duct:rectangular')!; assertEquals(duct.qty, null); assert(duct.description.includes('16x14 (1" liner)'));
  assertEquals(q('pipe:3" SS')?.qty, null);
  // Nothing from the title block became a line.
  for (const l of lines) for (const s of IDENTITY) assert(!l.description.includes(s), `identity in a line: ${s}`);
});

Deno.test('schedule rows read by OCR name the product and say so; OCR crumbs are normalised', () => {
  assertEquals(normTag('RTU 1'), 'RTU-1'); assertEquals(normTag('Cc'), 'C'); assertEquals(normTag('RTU-3 (DOAS)'), 'RTU-3');
  const { lines } = takeoff(pages, [{ page: 1, rows: [['TAG', 'MANUF.', 'MODEL'], ['EF 1', 'ZZ FANCO', 'GC-128'], ['Cc', 'ZZ GRILLE', 'PXP-AA']] }]);
  const ef = lines.find((l) => l.type === 'tag:EF-1')!;
  assert(ef.description.includes('ZZ FANCO, GC-128 (schedule read by OCR — to confirm)'), ef.description);
  assertEquals(lines.find((l) => l.type === 'air_device:C')?.qty_status, 'read', 'a schedule row confirms the letter is an air device');
});

Deno.test('redaction: the title strip and every identity elsewhere are boxed, nothing is left, and the drawing survives', () => {
  const r = titleBlockBoxes(pages, ['zz demo customer']);
  assertEquals(r.confidence, 'medium', r.residual.join('; '));
  assertEquals(r.residual, []);
  const boxes = r.boxes[0];
  const covered = (x: { x: number; y: number; w: number; h: number }) => boxes.some((b) => x.x >= b.x - 1e-6 && x.y >= b.y - 1e-6 && x.x + x.w <= b.x + b.w + 1e-6 && x.y + x.h <= b.y + b.h + 1e-6);
  for (const s of IDENTITY) assert(covered(run(s)), `not covered: ${s}`);
  assert(covered(page.images![0]), 'the logo is covered');
  assert(covered(page.runs.find((x) => x.text.startsWith('COORDINATE SHUTDOWNS'))!), 'the project name repeated in a note is boxed (a seed from the strip)');
  assert(covered(run('ZZTOWN, CO')), 'a "LOCATION:" label written as its own run takes its value');
  const strip = r.strips[0]!; assert(strip.x > 0.9 && strip.x < 0.915, 'the strip snaps to the border line, not into the drawing');
  // What a supplier sees keeps every tag: counts on the painted output equal counts on the original,
  // painted with drawing_redact's SERVER_MARGIN.
  const M = 0.004;
  const visible = (_i: number, x: { x: number; y: number; w: number; h: number }) => !boxes.some((b) => x.x + x.w / 2 >= b.x - M && x.x + x.w / 2 <= b.x + b.w + M && x.y + x.h / 2 >= b.y - M && x.y + x.h / 2 <= b.y + b.h + M);
  assertEquals(tagCounts(pages, visible), tagCounts(pages));
  // And nothing identifying is left on any run a supplier can still read.
  for (const x of page.runs.filter((x) => visible(0, x))) assertEquals(residualScan(x.text, []), [], x.text);
});

Deno.test('the BOQ drawing_boq returns is scrubbed and marks what is ours to confirm', () => {
  const out = boqFromDrawingSet(pages, 'ZZ DEMO CRIME LAB REMODEL mechanical works')!;
  assertEquals(out.method, 'drawing_set');
  assertEquals(out.category, 'mep_hvac');
  const json = JSON.stringify(out);
  for (const s of IDENTITY) assert(!json.includes(s), `identity reached the BOQ: ${s}`);
  assert(out.boq.some((l) => l.qty_status === 'to_confirm'));
  assert(out.missing_info.some((m) => /LENGTHS are not printed/.test(m)));
});

Deno.test('OCR-derived lines are never ready: the portal OCR fallback marks them to confirm', () => {
  // The four invented lines of the baseline were exactly this shape: noise with a number and a unit.
  const r = boqFromExtracted(empty('pdf'), '', 'Ere Mill || + | I 0 99 5 m\nCONG ARACEAE SS ENERRGESGH 107 nos');
  assert(r.boq.length >= 1);
  for (const l of r.boq) assertEquals((l as { qty_status?: string }).qty_status, 'to_confirm', l.description);
});
