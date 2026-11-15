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

// Round 4 (third review fix 5): a model that answers the mark as a JSON NUMBER drops a leading zero; a mark began with 0
// about one view in ten, so about 89% of A1 pages (21 views) would have been held as unread.
Deno.test('a mark answered as a JSON number is read: the first digit is never 0, and a numeric answer is padded to six digits', async () => {
  for (let i = 0; i < 5000; i++) assert(/^[1-9]\d{5}$/.test(newMark()), 'the first digit is 1-9');
  const firsts = new Set(Array.from({ length: 3000 }, () => newMark()[0]));
  assertEquals(firsts.size, 9, 'every first digit 1-9 occurs');
  assertEquals(parsePixelVerdict('{"mark":482913,"clean":true,"addressed":false,"regions":[]}')?.mark, '482913');
  assertEquals(parsePixelVerdict('{"mark":12345,"clean":true,"addressed":false,"regions":[]}')?.mark, '012345', 'a dropped zero is padded back');
  assertEquals(parsePixelVerdict('{"mark":"12345","clean":true,"addressed":false,"regions":[]}')?.mark, '12345', 'a string is taken as written');
  // End to end: a stub that copies the mark as a NUMBER clears an A1 page's 21 views.
  const crop = async (_b: string, _t: Tile, mark: string) => mark;
  const g = await pixelGate('page', async (shown) => `{"mark":${Number(shown)},"clean":true,"addressed":false,"regions":[]}`, async (b) => b, pixelBudget(), { plan: planTiles({ wMm: SHEETS_MM.A1[0], hMm: SHEETS_MM.A1[1], from: 'mediabox' }), crop });
  assert(g.ok && g.calls === 21, 'every view read');
});

// Round 4 (third review fix 4(d), the safe part): an OVER-EAGER checker that boxes every line it reads published 22 of 23
// ordinary previews with 0 of 28 quoting strings left. On a text-layer page a checker box over drawing vocabulary only is
// ignored (not painted) and logged; anything that names a party, a bare number, unread text or a picture is painted.
import { vocabularyVet } from '../_shared/drawing_code_floor.ts';
Deno.test('OVER-EAGER: a checker box over drawing words only is not painted and is logged; identity, numbers, unread text and wide boxes still are', async () => {
  const p = (await fixture('zz_pool_b1_embedded_font.pdf'))[0];
  const vet = vocabularyVet(p, ['ZZ Demo Agent'])!;
  const around = (t: string, what: string = t) => { const r = p.runs.find((x) => x.text === t)!; assert(r, t); return { x: r.x - 0.002, y: r.y - 0.002, w: r.w + 0.004, h: r.h + 0.004, what }; };
  for (const t of ['POOL PLAN  SCALE 1:50', 'SHALLOW END  WL +0.00  FFL -1.20', 'EQUIPMENT SCHEDULE', 'CIRCULATION PUMP 1.5 HP 230V', '7. ALL DIMENSIONS IN MM, LEVELS IN M.']) {
    assertEquals(vet([around(t)]).ignored.length, 1, `ignored: ${t}`);
  }
  for (const t of ['VILLA 15', 'STREET 23B, AL BARSHA 2', 'ZZ DEMO CORAL POOLS CONSULTANTS LLC', 'DM Licence No. 778899', 'Owner mobile 055 765 4321 Mr ZZ Demo Owner', '5000', '10000']) {
    assertEquals(vet([around(t)]).keep.length, 1, `painted: ${t}`);
  }
  // A box reaching well past the words (it could hide a drawn name or a map beside them) is painted.
  const r = around('EQUIPMENT SCHEDULE');
  assertEquals(vet([{ ...r, w: r.w + 0.1, h: r.h + 0.1 }]).keep.length, 1);
  // Text code cannot read is never vouched for by the words around it (v01's outlined labels).
  const v01 = (await fixture('review_f3/v01_outlined_site_labels.pdf'))[0];
  const ua = (await import('../_shared/drawing_code_floor.ts')).unreadAreas(v01, [])[0];
  assertEquals(vocabularyVet(v01, [])!([{ x: ua.x - 0.01, y: ua.y - 0.01, w: ua.w + 0.02, h: ua.h + 0.02 }]).keep.length, 1);
  // A page with no text layer has no vet: every box is painted.
  assertEquals(vocabularyVet({ width: 1, height: 1, rotate: 0, runs: [] }, []), undefined);
  // Through the gate: a checker that boxes the scale line only clears the page without painting it, and says so.
  const count: { painted: number } = { painted: 0 };
  const g2 = await pixelGate('page', async (shown) => JSON.stringify({ mark: shown, clean: false, addressed: false, regions: [around('POOL PLAN  SCALE 1:50', 'POOL PLAN SCALE 1:50')] }), async (b) => { count.painted++; return b; }, pixelBudget(), { plan: { tiles: [{ x: 0, y: 0, w: 1, h: 1, outW: 100, outH: 70 }], whole: null, cols: 1, rows: 1, textPx: 12, calls: 1, usd: 0, page: { wMm: 420, hMm: 297, from: 'mediabox' } }, crop: async (_b, _t, m) => m, vet });
  assert(g2.ok && g2.firstLookClean && count.painted === 0, 'not painted, page clear');
  if (g2.ok) { assertEquals(g2.detail.ignored, 1); assertEquals(g2.detail.ignored_what, ['POOL PLAN  SCALE 1:50']); }
  // An identity box beside it is painted as before.
  const g3 = await pixelGate('page', async (shown) => JSON.stringify({ mark: shown, clean: count.painted > 0, addressed: false, regions: count.painted > 0 ? [] : [around('VILLA 15')] }), async (b) => { count.painted++; return b; }, pixelBudget(), { plan: { tiles: [{ x: 0, y: 0, w: 1, h: 1, outW: 100, outH: 70 }], whole: null, cols: 1, rows: 1, textPx: 12, calls: 1, usd: 0, page: { wMm: 420, hMm: 297, from: 'mediabox' } }, crop: async (_b, _t, m) => m, vet });
  assert(g3.ok && Number(count.painted) === 1 && g3.boxes.length === 1);
  // drawing_redact gives both text-layer routes the vet and records what was ignored.
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /clock\.stopAt, vocabularyVet\(pp, \[\]\)\);/);
  assertMatch(src, /clock\.stopAt, vocabularyVet\(pp, seeds\)\);/);
  assertMatch(src, /if \(gate\.ok && gate\.detail\.ignored\) verifyDetail\.push\(\{ page: i, \.\.\.ignoredSaid\(gate\) \}\);/);
});

// Round 5 (fourth review, fix 1; SP/f3rev4/vet_probe.ts): a checker box is ignored only when what the checker SAID it saw is
// the text under it. A box for "+6512" or "MARINA PEARL TOWER" drawn one line high lands on drawing words; round 4 ignored
// it and published the page. It is now painted and asked again; a checker that keeps naming it holds the page.
import { whatIsUnder } from '../_shared/drawing_code_floor.ts';
Deno.test('a checker box one line off its identity is painted and asked again, never ignored; the page is held, not published', async () => {
  const runs = [
    { text: 'SHALLOW END WL +0.00 FFL -1.20', x: 0.118, y: 0.373, w: 0.121, h: 0.0114 },
    { text: '+6512', x: 0.118, y: 0.387, w: 0.020, h: 0.0114 },
    { text: 'CIRCULATION PUMP 1.5 HP 230V', x: 0.556, y: 0.173, w: 0.099, h: 0.0100 },
    { text: 'MARINA PEARL TOWER', x: 0.556, y: 0.185, w: 0.070, h: 0.0100 },
  ];
  const vet = vocabularyVet({ width: 2384, height: 1684, rotate: 0, runs, glyphRows: [], images: [] }, [])!;
  const high6512 = { x: 0.116, y: 0.372, w: 0.124, h: 0.0145, what: '+6512' };
  const highTower = { x: 0.555, y: 0.172, w: 0.101, h: 0.0115, what: 'MARINA PEARL TOWER' };
  const honest = { x: 0.116, y: 0.372, w: 0.124, h: 0.0125, what: 'SHALLOW END WL +0.00 FFL -1.20' };
  assertEquals(vet([high6512]).keep.length, 1, '+6512 boxed one line high (clips 15% of it): painted');
  assertEquals(vet([highTower]).keep.length, 1, 'MARINA PEARL TOWER boxed on the pump row: painted');
  assertEquals(vet([{ ...honest, what: undefined }]).keep.length, 1, 'no words from the checker: painted');
  assertEquals(vet([{ ...honest, what: 'street name' }]).keep.length, 1, 'a description, not the text under the box: painted');
  assertEquals(vet([honest]).ignored.length, 1, 'the checker read the level note and boxed it: ignored');
  assertEquals(vet([{ ...honest, h: 0.017 }]).keep.length, 1, 'the same honest box touching +6512 at all: painted');
  assert(whatIsUnder('SHALOW END', ['SHALLOW END WL +0.00']), 'one misread letter in a long word is the same word');
  assert(!whatIsUnder('+6513', ['+6512']), 'a number must match exactly');
  // Through the gate: a checker that keeps naming "+6512" one line high is painted twice, asked three times, and HELD.
  const count = { painted: 0, asked: 0 };
  const plan = { tiles: [{ x: 0, y: 0, w: 1, h: 1, outW: 100, outH: 70 }], whole: null, cols: 1, rows: 1, textPx: 12, calls: 1, usd: 0, page: { wMm: 594, hMm: 420, from: 'mediabox' as const } };
  for (const box of [high6512, highTower]) {
    count.painted = 0; count.asked = 0;
    const g = await pixelGate('page', async (shown) => { count.asked++; return JSON.stringify({ mark: shown, clean: false, addressed: false, regions: [box] }); }, async (b) => { count.painted++; return b; }, pixelBudget(), { plan, crop: async (_b, _t, m) => m, vet });
    assert(!g.ok && g.held === 'pixels_not_clean', `${box.what}: held, never published`);
    assertEquals([count.asked, count.painted], [3, 2], `${box.what}: painted and asked again (round 3's behaviour)`);
  }
});
