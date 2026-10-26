// drawing_lengths — duct and pipe lengths from CAD layers, and keyed-note bubbles by their outlines
// (22 Sep 2026, sales_engineer; founder instructions 30, 579, 580, 31, 63, 64).
// deno test -A supabase/functions/drawing_boq/drawing_lengths.test.ts
//
// Each assertion replays a cause measured on the two real bid sets (local only): if the reader stops
// reading optional content, if dashes are summed without their gaps, if a wall pairs with its liner, if a
// single-line branch is dropped, if a stray number counts as a bubble, or if two different notes that
// share a first sentence are merged, a test here fails.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { MAX_MEASURED_LINES, measureDucts, measurePipes, parseScale, pipeService, scaleLabels, feet, tooDense } from './drawing_lengths.ts';
import { boqFromDrawingSet, lengthsForSet, mergeLengths, takeoff } from './drawing_set.ts';
import { layeredSetPdf } from './drawing_lengths.fixtures.ts';

const pages = await pdfPages(layeredSetPdf());
const [plumb, mech] = pages;

Deno.test('scales parse to real inches per paper point, and never guess', () => {
  assertEquals(parseScale('1/8" = 1\'-0"')! * 72, 96);
  assertEquals(parseScale('1/4"=1\'-0"')! * 72, 48);
  assertEquals(parseScale('3/16" = 1\'-0"')! * 72, 64);
  assertEquals(parseScale('1:100')! * 72, 100);
  assertEquals(parseScale('NTS'), null);
  assertEquals(parseScale('AS NOTED'), null);
});

Deno.test('layer names say the system; existing layers are not scope', () => {
  assertEquals(pipeService('P-SANR')?.svc, 'SS');
  assertEquals(pipeService('P -VENT')?.svc, 'V');
  assertEquals(pipeService('P-DOMW-CW')?.svc, 'CW');
  assertEquals(pipeService('P-DOMW-HW')?.svc, 'HW');
  assertEquals(pipeService('P-EXIST-SANR')?.existing, true);
  assertEquals(pipeService('P-ANNO'), null);
  assertEquals(pipeService('M-HVAC-DUCT'), null);
});

Deno.test('the reader returns optional-content layers with their segments, widths and closed outlines', () => {
  for (const l of ['P-SANR', 'P-VENT', 'P-EXIST-SANR', 'M-ANNO']) assert(plumb.layers?.[l]?.length, `layer missing: ${l}`);
  assertEquals(plumb.layerWidths!['P-SANR'].length * 4, plumb.layers!['P-SANR'].length, 'one width per segment');
  assertEquals(plumb.layerWidths!['P-SANR'][0], 1.68);
  assert((plumb.marks || []).filter((m) => m.layer === 'M-ANNO').length >= 3, 'closed bubble boxes are marks');
});

Deno.test('the reader can interpret only a batch of pages, keeping page indexes (drawing_redact, one sheet per call)', async () => {
  // 22 Sep 2026: drawing_redact parsed the whole set on every call and, with the pixel work, 4-page calls
  // died on production with 546. It now asks for its own pages only; the others are empty stubs in place.
  const part = await pdfPages(layeredSetPdf(), [1, 2]);
  assertEquals(part.length, 2);
  assertEquals(part[0].runs.length, 0, 'page 0 is a stub');
  assertEquals(part[0].width, pages[0].width, 'a stub keeps its size, so boxes still map');
  assertEquals(part[1].runs.length, pages[1].runs.length, 'page 1 is read in full');
});

Deno.test('pipe: dashed runs keep their gaps, each run takes the size of its own system', () => {
  const m = measurePipes(plumb, null, scaleLabels(plumb, null));
  const ft = (k: string) => { const g = m.find((x) => x.key === k); return g ? feet(g.realIn) : null; };
  assertEquals(ft('3" SS'), 19.8, 'a dashed run exported dash by dash keeps its gaps: 19.75 ft, not 15');
  assertEquals(ft('2" SS'), 5);
  assertEquals(ft('2" V'), 5);
  assert(!m.some((x) => /4"/.test(x.key)), 'the existing 4" SS layer is not measured');
});

Deno.test('duct: walls pair into a centreline, the liner never pairs, a single-line branch counts, a box does not', () => {
  const m = measureDucts(mech, null, scaleLabels(mech, null));
  const ft = (k: string) => { const g = m.find((x) => x.key === k); return g ? feet(g.realIn) : null; };
  assertEquals(ft('26x18'), 50);
  assertEquals(ft('8" round'), 20);
  assert(!m.some((x) => /^4"|round/.test(x.key) && x.key !== '8" round'), `no phantom liner duct: ${m.map((x) => x.key)}`);
  assertEquals(m.length, 2, `only the two real runs: ${m.map((x) => `${x.key}=${feet(x.realIn)}`)}`);
});

Deno.test('a dense sheet cannot exhaust the CPU cap: an indexed measure up to the ceiling, an honest skip past it', () => {
  // Short parallel wall pairs in a grid, 11 pt apart so they are never joined as dashes. Measured 22 Sep
  // 2026: 20,000 such lines took 1.2-2.4 s even indexed, and every line against every line is 400M tests.
  const sheet = (rows: number) => {
    const segs: number[] = [];
    for (let i = 0; i < rows; i++) for (let j = 0; j < 100; j++) {
      const x = 0.02 + j * 0.0095, y = 0.05 + i * 0.008;
      segs.push(x, y, x + 0.005, y, x, y + 0.004, x + 0.005, y + 0.004);
    }
    return { width: 2592, height: 1728, rotate: 0, runs: [{ text: 'SCALE: 1/8" = 1\'-0"', x: 0.5, y: 0.95, w: 0.1, h: 0.01 }], layers: { 'M-HVAC-DUCT': segs } };
  };
  const at = sheet(MAX_MEASURED_LINES / 200);                                   // exactly the ceiling
  // The MEDIAN of three timed runs, against the same 1000 ms budget. Measured 6 Oct 2026: one run alone failed 1 in
  // 3 on this laptop (769 ms, ~900 ms, 1242 ms) -- a wall clock on a shared machine, not the measure growing. A
  // median still fails when the measure itself is slow, because then two of three runs are.
  let t0 = 0;
  const times: number[] = [];
  for (let k = 0; k < 3; k++) {
    t0 = performance.now();
    assert(measureDucts(at, null, scaleLabels(at, null)).length > 0, 'measured at the ceiling');
    times.push(performance.now() - t0);
  }
  const ms = times.sort((a, b) => a - b)[1];
  assert(ms < 1000, `the ceiling itself took ${Math.round(ms)} ms`);
  const over = sheet(100);                                                      // 20,000 lines
  assert(tooDense(over, null));
  t0 = performance.now();
  assertEquals(measureDucts(over, null, scaleLabels(over, null)).length, 0, 'past the ceiling nothing is measured');
  assert(performance.now() - t0 < 300, 'and the skip is cheap');
  const { lines } = takeoff([{ ...over, runs: [...over.runs, { text: 'MAIN FLOOR PLAN - MECHANICAL', x: 0.3, y: 0.9, w: 0.2, h: 0.015 }, { text: '12x10', x: 0.3, y: 0.3, w: 0.02, h: 0.006 }] }]);
  assert(!lines.some((l) => l.type.startsWith('duct:') && l.qty !== null), 'no length is invented for a sheet that was not measured');
});

Deno.test('the lengths are a second call: the first read carries no layers, the merge replaces what it measured, a failure keeps every line', async () => {
  const bytes = layeredSetPdf();
  const cheap = await pdfPages(bytes, undefined, { layers: false });
  assert(cheap.every((p) => !p.layers), 'the first call reads no layer geometry');
  const first = boqFromDrawingSet(cheap)!;
  assert(first.boq.some((l) => l.type === 'duct:rectangular' && l.qty === null), 'without layers the duct line asks for its length');
  assert(first.boq.some((l) => l.type === 'pipe:3" SS' && l.qty === null));
  const merged = mergeLengths(first, lengthsForSet(await pdfPages(bytes)));
  assertEquals(merged.boq.find((l) => l.type === 'duct:26x18')?.qty, 15.2);
  assertEquals(merged.boq.find((l) => l.type === 'pipe:3" SS')?.qty, 6);
  assert(!merged.boq.some((l) => /^(duct|pipe):/.test(l.type) && l.qty === null), 'every measured size replaced its "to be measured" line');
  assert(merged.boq.find((l) => l.type === 'duct:26x18')?.description_ar?.includes('مجاري هواء'), 'the measured line carries Arabic');
  assert(merged.missing_info[0].startsWith('Duct and pipe lengths are measured in plan'));
  assert(merged.boq.some((l) => l.section === 'Keyed notes'), 'the counted lines are kept');
  const failed = mergeLengths(first, null);
  assertEquals(failed.boq.length, first.boq.length, 'a killed lengths call loses nothing');
  assert(failed.missing_info[0].includes('could not be measured on this upload'), 'and says so');
});

Deno.test('take-off: lengths become lines; bubbles count only inside an outline; different notes stay apart', () => {
  const { lines } = takeoff(pages);
  const q = (type: string) => lines.find((l) => l.type === type);
  assertEquals(q('pipe:3" SS')?.qty, 6); assertEquals(q('pipe:3" SS')?.qty_status, 'read'); assertEquals(q('pipe:3" SS')?.unit, 'm');
  assertEquals(q('pipe:2" V')?.qty, 1.5);
  assertEquals(q('duct:26x18')?.qty, 15.2); assertEquals(q('duct:26x18')?.qty_status, 'read');
  assertEquals(q('duct:8" round')?.qty, 6.1); assertEquals(q('duct:8" round')?.qty_status, 'to_confirm', 'a single-line run is sized from the nearest label');
  const notes = lines.filter((l) => l.section === 'Keyed notes');
  const n = (k: number) => notes.find((l) => l.type === `note:P-1.01:${k}`);
  assertEquals(n(1)?.qty, 2, 'two boxed "1" bubbles; the stray "1" is not one');
  assertEquals(n(1)?.qty_status, 'read');
  assertEquals(n(2)?.qty, 1, 'a box drawn as four separate lines is an outline too');
  assertEquals(n(3)?.qty, 1);
  assertEquals(notes.length, 3, 'notes 1 and 2 share a first sentence on the same sheet and are two items');
});

// -- single-line sizes: the label nearest ALONG the run (22 Sep 2026) -----------------------------------
// Synthetic sheets at 1/8" = 1'-0" (1.333 real in per pt, 9 pt = 1 ft), built from paper-point geometry.
// Measured on the real M1.0 before this: a run took the label nearest ANY of its points, so a branch whose
// end stopped beside a trunk's label took the trunk's size, a roof-curb outline took a "4"Ø" 18 ft away,
// and a single-line branch beside a double-line wall paired with it into a phantom 25" duct.
const W8 = 2592, H8 = 1728;
const sheet8 = (segs: number[][], labels: [string, number, number][]) => ({
  width: W8, height: H8, rotate: 0,
  runs: [{ text: 'SCALE: 1/8" = 1\'-0"', x: 0.5, y: 0.95, w: 0.1, h: 0.01 },
    ...labels.map(([text, x, y]) => ({ text, x: x / W8 - 0.003, y: y / H8 - 0.002, w: 0.006, h: 0.004 }))],
  layers: { 'M-HVAC-DUCT': segs.flatMap(([ax, ay, bx, by]) => [ax / W8, ay / H8, bx / W8, by / H8]) },
});
const ductFt = (p: ReturnType<typeof sheet8>) => {
  const m = measureDucts(p, null, scaleLabels(p, null));
  return Object.fromEntries(m.map((g) => [g.key, feet(g.realIn)]));
};

Deno.test('single-line: a label beside the middle of a long run sizes it, though another run ends nearer the label', () => {
  // A: 600 pt run, "12x8" 12 pt above its middle. B: a branch whose END stops 12.5 pt from that label, with
  // its own "6" DIA" 14 pt beside its middle. Nearest-point association gave B the 12x8.
  const ft = ductFt(sheet8([[400, 500, 1000, 500], [700, 300, 700, 475.5]], [['12x8', 700, 488], ['6" DIA', 714, 390]]));
  assertEquals(ft['12x8'], 66.7, 'A alone is the 12x8');
  assertEquals(ft['6" round'], 19.5, 'B takes the label beside it, not the one past its end');
});

Deno.test('single-line: two branches side by side, each with its own label, are two runs, not one double-line duct', () => {
  // 15 pt (20") apart, no printed 20" size anywhere: an 8" above, a 10" below.
  const ft = ductFt(sheet8([[400, 800, 900, 800], [400, 815, 900, 815]], [['8" DIA', 650, 790], ['10" DIA', 650, 825]]));
  assertEquals(ft['8" round'], 55.6);
  assertEquals(ft['10" round'], 55.6);
  assert(!Object.keys(ft).some((k) => /wide/.test(k)), `no phantom double-line duct: ${Object.keys(ft)}`);
});

Deno.test('single-line: a label used by one run does not size a farther parallel run; too far or too close to call is never guessed', () => {
  // two parallel runs 50 pt (67") apart, one "8" DIA" 15 pt from the upper and 35 pt from the lower.
  let ft = ductFt(sheet8([[400, 800, 900, 800], [400, 850, 900, 850]], [['8" DIA', 650, 815]]));
  assertEquals(ft['8" round'], 55.6, 'the nearer run takes it');
  assertEquals(ft['single-line duct (size not labelled)'], 55.6, 'the farther parallel run stays unlabelled');
  // a label 9 ft (81 pt) from the run: past SINGLE_LABEL_FT, not this run's size.
  ft = ductFt(sheet8([[400, 800, 900, 800]], [['4" DIA', 650, 719]]));
  assertEquals(Object.keys(ft), ['single-line duct (size not labelled)']);
  // two different sizes beside it at 10 and 11 pt: ambiguous.
  ft = ductFt(sheet8([[400, 800, 900, 800]], [['8" DIA', 650, 790], ['10" DIA', 700, 811]]));
  assertEquals(Object.keys(ft), ['single-line duct (size not labelled)']);
});
