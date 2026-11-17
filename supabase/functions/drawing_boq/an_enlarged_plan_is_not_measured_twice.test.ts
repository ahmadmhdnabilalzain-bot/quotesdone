// AN ENLARGED PLAN IS NOT MEASURED TWICE (17 Nov 2026, sales_engineer; found by the duct-fix review, pre-existing on main).
// The length take-off summed every new-work plan by size, so an enlarged plan of an area the main plan already shows was
// counted again: the reviewer's built set (main plan, "ENLARGED MECHANICAL PLAN", a second-floor plan, one 15.2 m 26x18
// run each) gave 45.7 m for 30.5 m drawn. The rule is drawing_set/enlarged.ts: a sheet that calls itself an enlargement
// (title, drawing index, a part plan at a larger scale, or another sheet naming it) AND whose every run is also on the
// discipline's ordinary plans is not counted again; anything less certain is counted and the line says "may include an
// enlarged plan — please confirm". Each set is proved both ways it is read: whole (the CAD worker, takeoff) and a sheet
// per call (lengthsPart + lengthsOfParts, what customer_api does) - they must agree.
// Run: deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//   supabase/functions/drawing_boq/an_enlarged_plan_is_not_measured_twice.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { lineKey, settleLines } from '../_shared/boq_open_lines.ts';
import { planRoles } from './drawing_set/enlarged.ts';
import { lengthsForSet, lengthsOfParts, lengthsPart, takeoff, type TakeoffLine } from './drawing_set.ts';
import { LENGTH_MAY_INCLUDE_ENLARGED, LENGTH_MAY_INCLUDE_ENLARGED_AR } from './length_notes.ts';

// ── SYNTHETIC ZZ DEMO sheets, the reviewer's builder: 36 x 24 in, the duct on layer M-HVAC-DUCT, walls drawn double ──────────
const W = 2592, H = 1728;
const esc = (s: string) => s.replace(/([()\\])/g, '\\$1');
const t = (x: number, y: number, size: number, s: string) => `BT /F1 ${size} Tf ${x} ${y} Td (${esc(s)}) Tj ET\n`;
const seg = (x1: number, y1: number, x2: number, y2: number) => `${x1} ${y1} m ${x2} ${y2} l S\n`;
const layer = (body: string) => `/OC /L1 BDC q 1.44 w\n${body}Q EMC\n`;
/** A `w`x`d` duct `ft` feet long at 1/`den`" = 1'-0" (pt per real inch = 72 / den / 12), its size printed on it. */
const duct = (x0: number, y: number, ft: number, w: number, d: number, den = 8) => {
  const k = 72 / den / 12, L = ft * 12 * k, g = w * k;
  return layer(seg(x0, y, x0 + L, y) + seg(x0, y + g, x0 + L, y + g) + seg(x0, y, x0, y + g) + seg(x0 + L, y, x0 + L, y + g)) + t(x0 + L / 2, y + g / 3, 8, `${w}x${d}`);
};
const sheet = (title: string, no: string, body: string, den = 8, extra = '') => t(900, 200, 22, title) + t(900, 175, 9, `SCALE: 1/${den}" = 1'-0"`) + t(2300, 120, 30, no) + body + extra;
const idx = (y: number, no: string, title: string) => t(100, y, 10, no) + t(150, y, 10, title);
function setPdf(contents: string[]): Uint8Array {
  const objs: string[] = []; const add = (s: string) => { objs.push(s); return objs.length; };
  const n = contents.length;
  add('<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [3 0 R] >> >>');
  add(`<< /Type /Pages /Kids [${contents.map((_, i) => `${5 + i} 0 R`).join(' ')}] /Count ${n} >>`);
  add('<< /Type /OCG /Name (M-HVAC-DUCT) >>');
  add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  const res = '/Resources << /Font << /F1 4 0 R >> /Properties << /L1 3 0 R >> >>';
  for (let i = 0; i < n; i++) add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] ${res} /Contents ${5 + n + i} 0 R >>`);
  for (const c of contents) add(`<< /Length ${c.length} >>\nstream\n${c}\nendstream`);
  let out = '%PDF-1.5\n'; objs.forEach((o, i) => { out += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  return new TextEncoder().encode(out + 'trailer\n<< /Root 1 0 R >>\n%%EOF\n');
}

const json = <T>(x: T): T => JSON.parse(JSON.stringify(x));
/** The length lines read a sheet per call (customer_api's way), checked equal to the whole-set read and to takeoff's own. */
async function lengths(bytes: Uint8Array): Promise<TakeoffLine[]> {
  const whole = lengthsForSet(await pdfPages(bytes));
  const n = (await pdfPages(bytes, undefined, { layers: false })).length;
  const parts = [];
  for (let i = 0; i < n; i++) parts.push(json(lengthsPart(await pdfPages(bytes, [i, i + 1]), i, i + 1)));
  const got = lengthsOfParts(parts.reverse());
  assert(got, 'the parts merged');
  assertEquals(got, json(whole), 'a sheet per call == the whole set');
  const tk = takeoff(await pdfPages(bytes)).lines.filter((l) => /^(duct|pipe):/.test(l.type));
  assertEquals(tk.map((l) => [l.type, l.qty, l.qty_status, l.sheets]), whole.lines.map((l) => [l.type, l.qty, l.qty_status, l.sheets]), 'takeoff reads it the same way');
  return whole.lines;
}
const line = (ls: TakeoffLine[], type: string) => { const l = ls.filter((x) => x.type === type); assertEquals(l.length, 1, type); return l[0]; };
const flagged = (l: TakeoffLine) => l.description.includes(LENGTH_MAY_INCLUDE_ENLARGED);

Deno.test("the reviewer's set: an enlarged plan of the main plan's area is not counted again (45.7 m -> 30.5 m)", async () => {
  const ls = await lengths(setPdf([
    sheet('FIRST FLOOR PLAN - MECHANICAL', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('ENLARGED MECHANICAL PLAN', 'M1.1', duct(200, 600, 50, 26, 18)),
    sheet('MECHANICAL SECTION', 'M3.0', duct(200, 600, 50, 26, 18)),
    sheet('ROOF PLAN', 'M1.2', duct(200, 600, 50, 26, 18)),
    sheet('CONTINUATION PLAN', 'M1.3', duct(0, 600, 50, 26, 18)),
    sheet('DRAWING INDEX', 'M0.0', '', 8, idx(1500, 'M1.0', 'FIRST FLOOR PLAN') + idx(1480, 'M1.2', 'DUCT DETAILS') + idx(1460, 'M1.3', 'SECOND FLOOR PLAN')),
  ]));
  const d = line(ls, 'duct:26x18');
  assertEquals([d.qty, d.qty_status, d.sheets], [30.5, 'to_confirm', ['M1.0', 'M1.3']], 'the first and second floors; the enlargement is the first floor again');
  assert(flagged(d), 'not counted again, and open: by size alone it cannot be told from a room the main plan leaves empty');
  assert(/M1\.1 is an enlarged plan .* not counted again/.test(d.basis), d.basis);
});

Deno.test('an enlarged plan the drawing index names, or another sheet calls enlarged, is not counted again', async () => {
  // The index retitles M4.1; its own title is plain.
  let d = line(await lengths(setPdf([
    sheet('MECHANICAL PLAN', 'M1.0', duct(200, 600, 50, 26, 18), 8, idx(1500, 'M4.1', 'ENLARGED PLAN - PLANT ROOM')),
    sheet('PLANT ROOM PLAN', 'M4.1', duct(200, 600, 50, 26, 18)),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.sheets, flagged(d)], [15.2, ['M1.0'], true], 'the drawing index');
  // The main plan says "SEE ENLARGED PLAN M4.1"; M4.1 draws the same 50 ft run at 1/4".
  d = line(await lengths(setPdf([
    sheet('MECHANICAL PLAN', 'M1.0', duct(200, 600, 50, 26, 18), 8, t(400, 700, 8, 'SEE ENLARGED PLAN M4.1')),
    sheet('MECHANICAL ROOM PLAN', 'M4.1', duct(200, 600, 50, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.sheets, flagged(d)], [15.2, ['M1.0'], true], 'named on the main plan');
  // A PART PLAN drawn at a larger scale than the plans, carrying only what the main plan carries.
  d = line(await lengths(setPdf([
    sheet('GROUND FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('PART PLAN - PLANT ROOM', 'M1.1', duct(200, 600, 50, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, d.sheets, flagged(d)], [30.5, 'to_confirm', ['M1.0', 'M1.1'], true], 'a part plan at a larger scale may be another zone: counted, open');
});

Deno.test('a sheet that may be an enlargement is still counted, and its line says so - never a silent guess', async () => {
  // Titled ENLARGED, but it carries a 12x10 run the main plan leaves out (the room is only on the enlarged plan).
  let ls = await lengths(setPdf([
    sheet('MECHANICAL PLAN', 'M1.0', duct(200, 600, 50, 26, 18), 8, t(400, 700, 8, 'SEE ENLARGED PLAN M4.1')),
    sheet('ENLARGED PLANT ROOM PLAN', 'M4.1', duct(200, 900, 20, 12, 10, 4), 4),
  ]));
  const small = line(ls, 'duct:12x10');
  assertEquals([small.qty, small.qty_status, small.estimate, small.sheets], [6.1, 'to_confirm', 6.1, ['M4.1']], 'counted, open');
  assert(flagged(small) && small.description_ar!.endsWith(LENGTH_MAY_INCLUDE_ENLARGED_AR), `${small.description} | ${small.description_ar}`);
  assert(/M4\.1 looks like an enlarged plan .* counted/.test(small.basis), small.basis);
  assert(!flagged(line(ls, 'duct:26x18')), 'the main plan\'s size is not touched');
  // An ordinary title, but at twice the scale of the other plans and nothing on it they do not carry.
  ls = await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 50, 26, 18)),
    sheet('MECHANICAL PLAN', 'M1.2', duct(200, 600, 50, 26, 18, 4), 4),
  ]));
  const d = line(ls, 'duct:26x18');
  assertEquals([d.qty, d.qty_status, d.sheets], [45.7, 'to_confirm', ['M1.0', 'M1.1', 'M1.2']], 'counted, open');
  assert(flagged(d) && /M1\.2 is drawn at a larger scale/.test(d.basis), d.basis);
  // The customer states the length: the line stops asking.
  const [settled] = settleLines([d as never], { status: 'adjusted', lines: [], adjustments: { [lineKey(d)]: 30.5 } }) as unknown as TakeoffLine[];
  assertEquals([settled.qty, settled.qty_status], [30.5, 'customer_stated']);
  assert(!flagged(settled) && !settled.description_ar!.includes(LENGTH_MAY_INCLUDE_ENLARGED_AR), settled.description);
});

Deno.test('different areas stay counted, unflagged: other floors, partial plans at one scale, an enlarged plan alone', async () => {
  let d = line(await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 50, 26, 18)),
    sheet('PARTIAL PLAN 3 - MECHANICAL', 'M1.2', duct(200, 600, 50, 26, 18)),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, d.sheets, flagged(d)], [45.7, 'read', ['M1.0', 'M1.1', 'M1.2'], false]);
  // Only one measured plan: there is nothing it could repeat.
  d = line(await lengths(setPdf([sheet('ENLARGED MECHANICAL PLAN', 'M4.1', duct(200, 600, 50, 26, 18, 4), 4)])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, flagged(d)], [15.2, 'read', false]);
  // Plumbing at 1/4" beside mechanical at 1/8" is two disciplines, not an enlargement.
  d = line(await lengths(setPdf([
    sheet('MECHANICAL PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('PLUMBING PLAN', 'P1.0', duct(200, 600, 25, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, flagged(d)], [22.9, false], 'a P sheet is compared with P sheets');
});

Deno.test("the e2e 8-sheet set (eight PARTIAL PLANs of eight areas) keeps the key's 16,432.9 m, read, every sheet", async () => {
  const SET8 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
  const d = line(lengthsForSet(await pdfPages(SET8)).lines, 'duct:26x18');
  // 16,433.2 m measured before this change too (lengths.ts); the e2e's key is 16,432.9 m within its 0.5%.
  assertEquals([d.qty, d.qty_status, d.sheets.length, flagged(d)], [16433.2, 'read', 8, false]);
  assert(Math.abs(d.qty! - 16432.9) / 16432.9 < 0.005);
  assert(!/enlarged/.test(d.basis), d.basis);
});

Deno.test('an enlarged plan is dropped only when ONE plan - the one that names it - carries it all (review 17 Nov)', async () => {
  // The main plan leaves the plant room to M4.1; the second floor's own 12x10 is another room, not this one.
  let ls = await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18), 8, t(400, 700, 8, 'SEE ENLARGED PLAN M4.1')),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 50, 26, 18) + duct(200, 900, 40, 12, 10)),
    sheet('ENLARGED PLANT ROOM PLAN', 'M4.1', duct(200, 900, 30, 12, 10, 4), 4),
  ]));
  let d = line(ls, 'duct:12x10');
  assertEquals([d.qty, d.qty_status, d.sheets, flagged(d)], [21.3, 'to_confirm', ['M1.1', 'M4.1'], true], 'the plant room is counted, open');
  // PART PLAN - ZONE B at 1/4" is another zone with the floors' size.
  d = line(await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 50, 26, 18)),
    sheet('PART PLAN - ZONE B', 'M1.2', duct(200, 600, 40, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, flagged(d)], [42.7, 'to_confirm', true]);
  // The enlarged sheet's own note pointing back at its main plan does not make the main plan an enlargement.
  d = line(await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18)),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 50, 26, 18)),
    sheet('ENLARGED PLANT ROOM PLAN', 'M4.1', duct(200, 600, 20, 26, 18, 4), 4, t(400, 300, 8, 'ENLARGED PLAN OF AREA SHOWN ON M1.0')),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.sheets, flagged(d)], [30.5, ['M1.0', 'M1.1'], true], 'both floors counted, the enlargement once, open');
  // More run than any one plan carries is not a repeat of one area.
  d = line(await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 20, 26, 18)),
    sheet('SECOND FLOOR PLAN', 'M1.1', duct(200, 600, 20, 26, 18)),
    sheet('ENLARGED PLAN - CORE', 'M4.1', duct(200, 600, 30, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, flagged(d)], [21.3, 'to_confirm', true]);
});

Deno.test('second review (17 Nov): a dropped enlargement keeps its line open; a floor plan that also carries enlargements is a floor', async () => {
  // M1.0 leaves the plant room to M4.1 but runs 26x18 elsewhere: by size M4.1 looks repeated. 15.2 m is sent, never as 'read'.
  let d = line(await lengths(setPdf([
    sheet('FIRST FLOOR PLAN', 'M1.0', duct(200, 600, 50, 26, 18), 8, t(400, 700, 8, 'SEE ENLARGED PLAN M4.1')),
    sheet('ENLARGED PLANT ROOM PLAN', 'M4.1', duct(200, 600, 20, 26, 18, 4), 4),
  ])), 'duct:26x18');
  assertEquals([d.qty, d.qty_status, flagged(d)], [15.2, 'to_confirm', true]);
  // Three identical typical floors; the third's title also names its toilet enlargements. Was 30.5 m 'read' (a floor lost).
  for (const extra of ['', idx(1500, 'M1.3', 'THIRD FLOOR PLAN AND ENLARGED PLANS')]) {
    d = line(await lengths(setPdf([
      sheet('FIRST FLOOR HVAC PLAN', 'M1.1', duct(200, 600, 50, 26, 18), 8, extra),
      sheet('SECOND FLOOR HVAC PLAN', 'M1.2', duct(200, 600, 50, 26, 18)),
      sheet(extra ? 'THIRD FLOOR HVAC PLAN' : 'THIRD FLOOR HVAC PLAN & ENLARGED TOILET PLANS', 'M1.3', duct(200, 600, 50, 26, 18)),
    ])), 'duct:26x18');
    assertEquals([d.qty, d.qty_status, d.sheets.length, flagged(d)], [45.7, 'read', 3, false], extra ? 'the index' : 'its own title');
  }
});

Deno.test('an Arabic title says enlarged too (مخطط مكبّر)', () => {
  const m = (page: number, number: string, title: string, scale: string) => ({ sheet: { page, number, title, scale: '', kind: 'plan' as const },
    m: { key: '26x18', svc: '', kind: 'duct' as const, pt: 100, realIn: 600, labelled: true, scale, layers: new Set<string>(), runs: 1 } });
  const r = planRoles([m(1, 'M1.0', 'MECHANICAL PLAN', '1/8" = 1\'-0"'), m(2, 'M4.1', 'مخطط مكبّر - غرفة المعدات', '1/8" = 1\'-0"')], new Map());
  assertEquals(r.get(2)?.counted, false, JSON.stringify([...r]));
});
