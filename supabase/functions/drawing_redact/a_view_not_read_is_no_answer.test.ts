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
