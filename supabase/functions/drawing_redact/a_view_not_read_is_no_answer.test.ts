// A VIEW THE MODEL DID NOT READ IS NO ANSWER (round 3 of the drawings fix, 13 Nov 2026, sales_engineer; brief
// f3_finish). MEASURED before this: a stub that answers {"clean": true} to every view without looking at it published
// the reviewer's v01 (outlined "AL BARSHA 2 / VILLA 15") and v12 (a Type3 "AL BARSHA 2 VILLA 15") previews, because
// nothing in an answer showed the tile had been read. Every view now carries a random number drawn in a band under
// the drawing (drawing_redact_page.withMarkBand), 14 px tall; an answer without that number HOLDS the page.
// Offline; the model is a stub.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_redact/a_view_not_read_is_no_answer.test.ts
import { assert, assertEquals, assertMatch, assertNotEquals } from 'jsr:@std/assert@1';
import { MARK_DIGITS, MARK_FONT, MARK_SCALE, PIXEL_VERIFY_SYS, SHEETS_MM, TILING, markCells, newMark, parsePixelVerdict, pixelBudget, pixelGate, planTiles, type Tile } from '../_shared/drawing_pixel_gate.ts';

/** Read the mark back from its ink cells with the font it was drawn in (what a model that reads the band sees). */
function readMark(cells: { x: number; y: number }[], drawingH: number): string {
  const ink = new Set(cells.map((c) => `${c.x},${c.y}`)), s = MARK_SCALE, top = drawingH + Math.floor((TILING.markPx - 7 * s) / 2);
  let left = 6, out = '';
  for (let i = 0; i < MARK_DIGITS; i++) {
    const rows = Array.from({ length: 7 }, (_, r) => Array.from({ length: 5 }, (_, c) => ink.has(`${left + c * s},${top + r * s}`) ? '1' : '0').join(''));
    out += Object.entries(MARK_FONT).find(([, g]) => g.join() === rows.join())?.[0] ?? '?';
    left += 6 * s + 2;
  }
  return out;
}

Deno.test('the mark is drawn UNDER the tile, 14 px tall, inside its band, and nothing of it falls on the drawing', () => {
  // (withMarkBand draws exactly these cells; the JPEG codec needs a network fetch these test flags forbid, so the mark's
  // legibility after JPEG is proved by the round-3 driver, which reads every view's mark back from the JPEG it was sent.)
  assert(7 * MARK_SCALE >= TILING.minTextPx, 'the digits are at least as tall as the 6 pt text the tiling promises');
  for (const mark of ['012345', '678901', newMark()]) {
    const cells = markCells(mark, 742);
    assertEquals(readMark(cells, 742), mark);
    assert(cells.every((c) => c.y >= 742 && c.y + c.h <= 742 + TILING.markPx), 'all ink is in the band, under the drawing');
    assertEquals(Math.max(...cells.map((c) => c.y + c.h)) - Math.min(...cells.map((c) => c.y)), 7 * MARK_SCALE);
    assert(Math.max(...cells.map((c) => c.x + c.w)) < 618, 'the number fits the narrowest tile (A3/A4 views are 618 px wide)');
  }
  const src = Deno.readTextFileSync(new URL('../_shared/drawing_redact_page.ts', import.meta.url));
  assertMatch(src, /if \(mark\) img = withMarkBand\(img, mark\);\n  return await img\.encodeJPEG\(quality\);/);
  assertMatch(src, /new Image\(img\.width, img\.height \+ TILING\.markPx\)\.fill\(0xffffffff\);\n  out\.composite\(img, 0, 0\);\n  for \(const c of markCells\(mark, img\.height\)\)/);
});

Deno.test('ALWAYS-CLEAN (answers without reading) HOLDS every page; a replayed or wrong mark too; a reader that copies it passes', async () => {
  const plan = planTiles({ wMm: SHEETS_MM.A3[0], hMm: SHEETS_MM.A3[1], from: 'mediabox' });
  const crop = async (b: string, t: Tile, mark: string) => `${b}#${t.whole ? 'w' : plan.tiles.indexOf(t)}@${mark}`;
  const paint = async (b: string) => b + '+painted';
  const always = await pixelGate('page', async () => JSON.stringify({ clean: true, addressed: false, regions: [] }), paint, pixelBudget(), { plan, crop });
  assertEquals(always.ok ? 'published' : always.held, 'pixels_unverified');
  assertEquals(always.ok ? 0 : always.detail.unread, plan.calls, 'every view is counted unread');
  let last = '';
  const replay = await pixelGate('page', async (img) => { const m = last; last = img.split('@')[1]; return JSON.stringify({ mark: m || '000000', clean: true, addressed: false, regions: [] }); }, paint, pixelBudget(), { plan, crop });
  assert(!replay.ok, 'a mark from another view is not this view\'s');
  const oneLazy = await pixelGate('page', async (img) => { const [v, m] = img.split('@'); return JSON.stringify({ mark: v.endsWith('#3') ? '' : m, clean: true, addressed: false, regions: [] }); }, paint, pixelBudget(), { plan, crop });
  assert(!oneLazy.ok, 'one view unread is enough to hold the page');
  const reader = await pixelGate('page', async (img) => JSON.stringify({ mark: img.split('@')[1], clean: true, addressed: false, regions: [] }), paint, pixelBudget(), { plan, crop });
  assert(reader.ok && reader.firstLookClean, 'a view read and clean passes');
  // Marks are fresh per call: the views of one look never share one.
  const marks: string[] = [];
  await pixelGate('page', async (img) => { marks.push(img.split('@')[1]); return JSON.stringify({ mark: img.split('@')[1], clean: true, addressed: false, regions: [] }); }, paint, pixelBudget(), { plan, crop });
  assertEquals(new Set(marks).size, marks.length);
  assert(marks.every((m) => new RegExp(`^\\d{${MARK_DIGITS}}$`).test(m)));
  assertNotEquals(newMark(), newMark() + 'x');
});

Deno.test('the prompt asks for the mark, the parser keeps only its digits, and the tile worker refuses a view without one', () => {
  assertMatch(PIXEL_VERIFY_SYS, /copy it into "mark"/);
  assertEquals(parsePixelVerdict('{"mark":" 12-34 56","clean":true,"addressed":false,"regions":[]}')?.mark, '123456');
  assertEquals(parsePixelVerdict('{"clean":true,"addressed":false,"regions":[]}')?.mark, '');
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const a = src.indexOf("if (body.mode === 'tile')"), tile = src.slice(a, src.indexOf('\n    }\n', a));
  assertMatch(tile, /!\/\^\\d\{6\}\$\/\.test\(String\(body\.mark/);
  assertMatch(tile, /tileJpeg\([^\n]*, 85, String\(body\.mark\)\)/);
  assertMatch(src, /crop: \(b, t, m\) => cropElsewhere\(secret, b, t, m\)/);
});

// LAZY (reads every view, copies its mark, reports nothing): the code floor holds what it covers; what code cannot read
// it now KNOWS is there, and a page with such text that no painted box covers is HELD (drawing_code_floor.ts).
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { padded, unreadAreas, unreadTextHold } from '../_shared/drawing_code_floor.ts';
const fixture = async (f: string) => await pdfPages(await Deno.readFile(new URL(`../_shared/testdata/${f}`, import.meta.url)), undefined, { layers: false });

Deno.test('LAZY and TITLE-ONLY: text code cannot read (outlines v01, a Type3 font v12, an inset n06) under no painted box HOLDS; the ordinary sheets have none', async () => {
  const v01 = (await fixture('review_f3/v01_outlined_site_labels.pdf'))[0], v12 = (await fixture('review_f3/v12_type3_obfuscated.pdf'))[0];
  const n06 = (await fixture('review_f3/n06_location_inset.pdf'))[0];
  assertEquals(unreadAreas(v01, []).length, 7, 'v01: the outlined AL BARSHA 2 / VILLA 15 / owner rows outside the title-block boxes');
  assertEquals(unreadAreas(v12, []).length, 1, 'v12: the run in a Type3 font with no ToUnicode');
  assertEquals(unreadAreas(n06, []).length, 2, 'n06: the location inset\'s outlined "AL KHAIL" rows');
  assert(v12.runs.some((r) => r.unread), 'the reader flags the run it cannot decode');
  // The third review's TITLE-ONLY find model: one box over the right-hand strip, painted at the model margin.
  const titleOnly = [padded({ x: 0.78, y: 0, w: 0.22, h: 1 }, 0.03)];
  for (const p of [v01, v12, n06]) {
    assertEquals(unreadTextHold(p, [], []), 'unread_text_unclaimed', 'both models silent: held');
    assertEquals(unreadTextHold(p, [], titleOnly), 'unread_text_unclaimed', 'a box over the title strip does not vouch for the site labels: held');
    const all = unreadAreas(p, []);
    assertEquals(unreadTextHold(p, [], all.map((b) => padded(b, 0.01))), null, 'every unread area under a painted box (a faithful model, or the checker\'s boxes): published');
    assertEquals(unreadTextHold(p, [], all.slice(1)), 'unread_text_unclaimed', 'one area left bare (the others boxed exactly): held');
  }
  // No false hold: the control sheet, the outlined title block the floor bands (v02), the pool fixtures (12 rows, all in
  // the title-block band). The reviewers' 35 ordinary sheets give 0 too (the round-4 driver, SP/f3fix4).
  for (const f of ['review_f3/v00_control.pdf', 'review_f3/v02_outlined_title_block.pdf', 'zz_pool_b1_embedded_font.pdf', 'zz_pool_b1_ascii85_flate.pdf']) {
    for (const p of await fixture(f)) { assertEquals(unreadAreas(p, []).length, 0, f); assertEquals(unreadTextHold(p, [], []), null, f); }
  }
  // Both drawing_redact routes ask it after the gate and before any upload, with every box that was painted.
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /const painted = \[\.\.\.\[\.\.\.regions, \.\.\.textBoxes\(i\)\.boxes, \.\.\.instructingRuns\([^\n]*\.\.\.floor\.map\([^\n]*gate\.boxes\.map[^\n]*\n\s*const unreadHeld = gate\.ok \? unreadTextHold\(pp, seeds, painted\) : null;\n\s*if \(unreadHeld\) \{ skipped\+\+;[^\n]*continue; \}[\s\S]{0,400}storage\.from\('drawing-files'\)\.upload\(path, jpg/);
  assertMatch(src, /const unreadHeld = unreadTextHold\(pp, \[\], \[\.\.\.\(r\.painted \?\? \[\]\), \.\.\.g\.boxes\.map\([^\n]*\);\n\s*if \(unreadHeld\) \{ skipped\+\+;[^\n]*continue; \}\n\s*const path = /);
});

Deno.test('the gate hands back every box the checker named and had painted, in page fractions (the unread rule counts them)', async () => {
  let round = 0;
  const ask = async (_b: string) => JSON.stringify(round++ === 0 ? { clean: false, addressed: false, regions: [{ x: 0.5, y: 0.4, w: 0.1, h: 0.05, what: 'outlined label' }] } : { clean: true, addressed: false, regions: [] });
  const g = await pixelGate('page', ask, async (b) => b + '+painted');
  assert(g.ok && !g.firstLookClean);
  if (g.ok) { assertEquals(g.boxes.length, 1); assertEquals(g.boxes[0].x, 0.5); assertEquals(g.boxes[0].w, 0.1); }
  const clean = await pixelGate('page', async () => JSON.stringify({ clean: true, addressed: false, regions: [] }), async (b) => b);
  assert(clean.ok && clean.boxes.length === 0);
});
