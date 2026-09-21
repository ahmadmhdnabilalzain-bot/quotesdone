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

// ── the synthetic sheet, written in DISPLAY coordinates (a, b = fraction across, fraction down) ─────
const W = 1728, H = 2592;            // user space (portrait); shown rotated 270 as 2592 x 1728
const DW = H, DH = W;
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (a: number, b: number, size: number, s: string) => `BT /F1 ${size} Tf 1 0 0 1 ${(a * DW).toFixed(1)} ${((1 - b) * DH).toFixed(1)} Tm (${esc(s)}) Tj ET\n`;
const line = (a1: number, b1: number, a2: number, b2: number) => `${(a1 * DW).toFixed(1)} ${((1 - b1) * DH).toFixed(1)} m ${(a2 * DW).toFixed(1)} ${((1 - b2) * DH).toFixed(1)} l S\n`;

// A diffuser tag: the letter, then its neck size over its airflow, offsets as measured on the real plan.
const device = (a: number, b: number, letter: string, neck: string, cfm: string) => t(a, b, 11, letter) + t(a + 0.005, b - 0.003, 11, neck) + t(a + 0.005, b + 0.003, 11, cfm);
const IDENTITY = ['(555) 010-7400', 'ZZDEMODESIGN.COM', '1039 ZZ MAIN STREET', 'ZZTOWN, CO  80550', 'ZZ DEMO CRIME LAB REMODEL', 'PROJECT NO:', 'ZZ-2018-040'];
const plan =
  line(0.915, 0.05, 0.915, 0.95) +                                            // the title-block border
  t(0.35, 0.80, 20, 'MAIN FLOOR PLAN - MECHANICAL') + t(0.35, 0.82, 11, 'SCALE:') + t(0.372, 0.82, 11, '1/8" = 1\'-0"') +
  t(0.300, 0.300, 9, 'EF') + t(0.3012, 0.3065, 9, '1') +                    // tag bubble: type over number
  t(0.600, 0.200, 9, 'EF') + t(0.6012, 0.2065, 9, '1') +                    // the same fan drawn again: still one fan
  t(0.40, 0.30, 11, 'IRH-1') + t(0.50, 0.30, 11, 'RTU1-2') + t(0.50, 0.33, 11, 'RTU1-2-H') +
  device(0.20, 0.50, 'A', '8x8', '180') + device(0.25, 0.50, 'A', '6x6', '100') + device(0.30, 0.55, 'A', '8x8', '180') +
  device(0.20, 0.60, 'B', '10x10', '--') + device(0.25, 0.60, 'B', '8x8', '--') +
  t(0.40, 0.62, 11, 'C') +                                                    // a bare letter continuing the series
  t(0.45, 0.45, 11, 'WC/L-1') + t(0.45, 0.50, 11, 'WC/L-1') + t(0.55, 0.50, 11, '(E)FCO') +
  t(0.60, 0.60, 11, '16x14 (1" LNR)') + t(0.60, 0.65, 11, '3" SS') +
  t(0.75, 0.10, 20, 'WORK NOTES:') +
  t(0.755, 0.15, 11, '1.') + t(0.762, 0.15, 11, 'PROVIDE MAN BARS AT EXTERIOR WALL PENETRATION.') +
  t(0.755, 0.17, 11, '2.') + t(0.762, 0.17, 11, 'EXISTING DUCT TO REMAIN.') +
  t(0.35, 0.45, 11, '1') + t(0.45, 0.70, 11, '1') +                           // two bubbles for note 1
  t(0.10, 0.90, 9, 'COORDINATE SHUTDOWNS WITH ZZ DEMO CRIME LAB REMODEL STAFF.') +
  t(0.10, 0.93, 9, 'LOCATION:') + t(0.15, 0.93, 9, 'ZZTOWN, CO') +
  'q /Fm2 Do Q\n';
const titleBlock = IDENTITY.map((s, i) => t(0.925, 0.10 + i * 0.04, 10, s)).join('') + t(0.93, 0.90, 30, 'M1.0') +
  t(0.925, 0.80, 10, 'MAIN FLOOR PLAN - MECHANICAL') +
  `q ${(0.05 * DW).toFixed(1)} 0 0 ${(0.03 * DH).toFixed(1)} ${(0.93 * DW).toFixed(1)} ${((1 - 0.60) * DH).toFixed(1)} cm /Im1 Do Q\n`;

function sheetPdf(): Uint8Array {
  const objs: string[] = [];
  const add = (s: string) => { objs.push(s); return objs.length; };
  const stream = (dict: string, body: string) => `<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
  add('<< /Type /Catalog /Pages 2 0 R >>');                                                                  // 1
  add('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');                                                          // 2
  add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Rotate 270 /Resources << /XObject << /Fm1 6 0 R >> >> /Contents 4 0 R >>`); // 3
  add('[5 0 R]');                                                                                             // 4: an ARRAY object
  add(stream('', 'q /Fm1 Do Q'));                                                                            // 5
  // Form 1: the drawing, turned to the display frame by its /Matrix (display y-up -> user space for /Rotate 270).
  add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Matrix [0 -1 1 0 0 ${H}] /Resources << /Font << /F1 8 0 R >> /XObject << /Fm2 7 0 R /Im1 9 0 R >> >>`, plan)); // 6
  add(stream(`/Type /XObject /Subtype /Form /BBox [0 0 ${DW} ${DH}] /Resources << /Font << /F1 8 0 R >> /XObject << /Im1 9 0 R >> >>`, titleBlock)); // 7: nested
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');                                             // 8
  add(stream('/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8', '\x00\xff')); // 9: the "logo"
  let out = '%PDF-1.4\n';
  objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  out += 'trailer\n<< /Root 1 0 R >>\n%%EOF\n';
  return new TextEncoder().encode(out);
}

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
