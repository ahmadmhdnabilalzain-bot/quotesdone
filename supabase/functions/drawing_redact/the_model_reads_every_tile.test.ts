// THE MODEL READS WHAT IT IS SHOWN, AND THE SERVER SHOWS IT THE FILE'S OWN PAGES (second review of the anonymity fix,
// 13 Nov 2026, sales_engineer). A page went to the model whole at 2600 px and the model downscales to about 1568 px: a
// 6-7 pt title-block line on an A1 sheet arrived at 3-5 px and a lazy or blind answer passed it. And verify_file released
// a vector PDF on whatever JPEGs the browser sent: one image of a 5-page file released pages 2-5 unseen.
// Offline; the model, the tile cutter and the painter are stubs.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_redact/the_model_reads_every_tile.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { PIXEL_COST, SHEETS_MM, TILING, callUsd, fileMayBeShared, jpegSize, pageSizeFromCad, pageSizeFromMediaBox, pageSizeFromPixels, pixelBudget, pixelGate, planTiles, toPage, type PixelOutcome, type Tile } from '../_shared/drawing_pixel_gate.ts';
import { aspectMatches, expectedInk, imageDenseEnough, inkAgrees, pageCountHolds, pxNeeded } from '../_shared/released_file_pages.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';

const PT_MM = 25.4 / 72;
const sheet = (k: string) => ({ wMm: SHEETS_MM[k][0], hMm: SHEETS_MM[k][1], from: 'mediabox' as const });

Deno.test('the tiling: each sheet size to its tiles, 6 pt text is 12 px in every tile, no tile a provider would scale down', () => {
  const grid: Record<string, string> = {};
  for (const k of Object.keys(SHEETS_MM)) {
    const p = planTiles(sheet(k));
    grid[k] = `${p.cols}x${p.rows}`;
    assert(p.textPx >= TILING.minTextPx - 1e-9, `${k}: 6 pt reaches the model at ${p.textPx} px`);
    for (const t of p.tiles) {
      assert(t.outW <= TILING.modelMaxEdge && t.outH <= TILING.modelMaxEdge, `${k}: a tile of ${t.outW}x${t.outH} would be downscaled`);
      // round 3: the primary route (openai) scales a short side past 768 px down, anthropic an image past ~1.15 MP
      assert(Math.min(t.outW, t.outH) <= TILING.modelShortEdge, `${k}: a tile of ${t.outW}x${t.outH} would be scaled to a 768 px short side`);
      assert(t.outW * t.outH <= TILING.modelMaxPixels, `${k}: a tile of ${t.outW}x${t.outH} is past ${TILING.modelMaxPixels} px`);
      // round 3: the view the model receives is the tile WITH the reading mark's band under it; that must fit as well.
      const H = t.outH + TILING.markPx;
      assert(Math.max(t.outW, H) <= TILING.modelMaxEdge && Math.min(t.outW, H) <= TILING.modelShortEdge && t.outW * H <= TILING.modelMaxPixels, `${k}: ${t.outW}x${H} with its band`);
      // the text height in what the model receives, from the tile's own size
      const pxPerMm = t.outW / (t.w * p.page.wMm);
      assert(TILING.textPt * PT_MM * pxPerMm >= TILING.minTextPx - 0.05, `${k}: ${TILING.textPt * PT_MM * pxPerMm} px`);
    }
    assertEquals(p.calls, p.tiles.length + (p.whole ? 1 : 0));
  }
  // A0 was 5x7 before the reading mark's 24 px band (round 3); its tiles no longer fit the 768 px short side with it.
  assertEquals(grid, { A0: '10x4', A1: '4x5', A2: '5x2', A3: '2x3', A4: '3x1' });
  // The round-2 A1 tile (1256x1180) reached the openai model at 817x768: 6 pt at 7.8 px. A mutant that drops the short
  // edge limit gets that grid back and fails here.
  assert(planTiles(sheet('A1')).tiles.every((t) => t.outH <= 768 && t.outW <= 1568));
  // A page that fits one tile is read whole once; any larger page also gets ONE reduced whole-page call.
  assertEquals(planTiles({ wMm: 130, hMm: 100, from: 'mediabox' }).calls, 1);      // 737 x 567 px: one view
  assertEquals(planTiles({ wMm: 200, hMm: 150, from: 'mediabox' }).calls, 3);      // 1134 x 850 px: two tiles and the whole
  assertEquals(planTiles(sheet('A1')).whole?.outW, TILING.wholeEdge);
});

Deno.test('the seams overlap: every mark up to the overlap in size is whole inside one tile, and the tiles cover the page', () => {
  for (const k of ['A0', 'A1', 'A3']) {
    const p = planTiles(sheet(k));
    const W = p.page.wMm, H = p.page.hMm, ov = TILING.overlapMm - 0.5;
    let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    for (let i = 0; i < 3000; i++) {
      const w = ov * rnd(), h = ov * rnd(), x = (W - w) * rnd(), y = (H - h) * rnd();
      const inside = p.tiles.some((t) => x >= t.x * W - 1e-6 && y >= t.y * H - 1e-6 && x + w <= (t.x + t.w) * W + 1e-6 && y + h <= (t.y + t.h) * H + 1e-6);
      assert(inside, `${k}: a ${w.toFixed(1)}x${h.toFixed(1)} mm mark at ${x.toFixed(0)},${y.toFixed(0)} is cut by every tile`);
    }
  }
});

Deno.test('the size of a page: MediaBox, a scan as the larger of A1 and its pixels, a CAD drawing by its own text', () => {
  const ansiD = pageSizeFromMediaBox(36 * 72, 24 * 72);
  assert(Math.abs(ansiD.wMm - 914.4) < 0.1);
  const photo = pageSizeFromPixels(4000, 3000);                 // 677 x 508 mm at 150 dpi: A1 is larger
  assertEquals([Math.round(photo.wMm), Math.round(photo.hMm)], [841, 594]);
  const bigScan = pageSizeFromPixels(9000, 6000);               // 1524 x 1016 mm at 150 dpi: larger than A1
  assert(bigScan.wMm > 1500 && planTiles(bigScan).tiles.length > 12);
  const cad = pageSizeFromCad(2600, 1838, 6.5);                 // 6.5 px text on a 2600 px drawing = an A1-sized sheet
  assert(Math.abs(Math.max(cad.wMm, cad.hMm) - 2600 * 6 * PT_MM / 6.5) < 1);
  assertEquals(Math.round(pageSizeFromCad(2600, 1838, 0.2).wMm), SHEETS_MM.A0[0], 'a stray tiny text cannot ask for more than A0');
  assertEquals(Math.round(pageSizeFromCad(2600, 1838, null).wMm), SHEETS_MM.A1[0], 'a drawing with no text is checked as A1');
});

Deno.test('the cost is data: one look at an A3 and an A1 page, a 20-page A1 set, and what the cap does with it', async () => {
  const a1 = planTiles(sheet('A1')), a3 = planTiles(sheet('A3'));
  // Round 3, 13 Nov 2026: A3 7 calls USD 0.0245; A1 21 calls USD 0.0828; 20 A1 pages USD 1.66 a look. The founder
  // accepted about USD 0.06 for an A1 look (PIXEL_COST.pageUsdAccepted); the A1 figure is above it and is reported, not
  // forced under it: the pixels alone of an A1 sheet at 12 px for 6 pt are about USD 0.044.
  // With the reading mark's band (round 3): A3 USD 0.0250, A1 USD 0.0844 (was 0.0245 / 0.0828).
  assertEquals([a3.calls, Number(a3.usd.toFixed(4))], [7, 0.025]);
  assertEquals([a1.calls, Number(a1.usd.toFixed(4))], [21, 0.0844]);
  assertEquals(PIXEL_COST.pageUsdAccepted, 0.06);
  const pixelsOnly = (841 * 594) * (TILING.minTextPx / (TILING.textPt * PT_MM)) ** 2 / PIXEL_COST.pixelsPerToken * PIXEL_COST.usdPerToken;
  assert(pixelsOnly > 0.04, `the pixels of an A1 sheet at 12 px for 6 pt alone cost USD ${pixelsOnly.toFixed(4)}`);
  assert(20 * a1.usd <= PIXEL_COST.setUsd, 'a 20-page A1 set\'s previews fit the cap');
  assert(40 * a1.usd > PIXEL_COST.setUsd, 'its released file as well does not: the file is held past the cap (said to the customer)');
  assertEquals(callUsd(0, 0), PIXEL_COST.promptTokens * PIXEL_COST.usdPerToken);
  // A set past its cap is HELD before any call, never partly asked.
  let asked = 0;
  const g = await pixelGate('p', async () => { asked++; return '{"clean":true,"addressed":false,"regions":[]}'; }, async (b) => b, pixelBudget(a1.usd - 0.001), { plan: a1, crop: async (b) => b });
  assertEquals([g.ok, g.ok ? '' : g.held, asked], [false, 'pixels_budget', 0]);
});

/** A page whose identity sits in ONE tile, too small for the whole-page view: a stub that reads a tile only. */
function stubbedPage(dirtyTile: number, opts: { lazyAfterPaint?: boolean } = {}) {
  const plan = planTiles(sheet('A1'));
  const asked: string[] = [];
  // The view carries its reading mark after '@' (in production: drawn in a band under the tile); this stub reads it.
  const crop = async (page: string, t: Tile, mark: string) => `${page}#${t.whole ? 'whole' : plan.tiles.indexOf(t)}@${mark}`;
  const ask = async (img: string) => {
    const [shown, mark] = img.split('@');
    asked.push(shown);
    const [page, view] = shown.split('#');
    const painted = page.includes('+painted');
    if (view === String(dirtyTile) && !(painted && !opts.lazyAfterPaint)) return JSON.stringify({ mark, clean: false, addressed: false, regions: [{ x: 0.5, y: 0.5, w: 0.2, h: 0.1, what: 'consultant name in 6 pt' }] });
    return JSON.stringify({ mark, clean: true, addressed: false, regions: [] });
  };
  const painted: unknown[] = [];
  const paint = async (b: string, r: unknown[]) => { painted.push(...r); return b + '+painted'; };
  return { plan, asked, crop, ask, paint, painted };
}

Deno.test('one call per tile and one whole-page call; a box found in a tile is mapped back to the page; clean only when EVERY view is', async () => {
  const s = stubbedPage(5);
  const g = await pixelGate('page', s.ask, s.paint, pixelBudget(), { plan: s.plan, crop: s.crop });
  assert(g.ok, 'painted then clean is published (a preview)');
  if (!g.ok) return;
  assertEquals(g.firstLookClean, false, 'a tile was not clean on the first look');
  assertEquals(fileMayBeShared(g), false, 'so no FILE is released from it');
  assertEquals(s.asked.filter((x) => !x.includes('+painted')).length, s.plan.calls, 'the first look asks every tile and the whole page');
  assertEquals(s.asked.filter((x) => x.includes('+painted')), ['page+painted#5'], 'only the view that was not clean is asked again');
  const t = s.plan.tiles[5];
  assertEquals(s.painted, [toPage(t, { x: 0.5, y: 0.5, w: 0.2, h: 0.1 })]);
  const b = s.painted[0] as { x: number; y: number; w: number; h: number };
  assert(b.x >= t.x && b.x + b.w <= t.x + t.w && b.y >= t.y && b.y + b.h <= t.y + t.h, 'the box lands inside its tile, in page fractions');
  assertEquals(g.usd, s.plan.usd + callUsd(t.outW, t.outH + TILING.markPx));
});

Deno.test('a LAZY whole-page answer does not clear the page while a tile still sees identity; a tile still dirty after the re-checks HOLDS', async () => {
  const s = stubbedPage(2, { lazyAfterPaint: true });
  const g = await pixelGate('page', s.ask, s.paint, pixelBudget(), { plan: s.plan, crop: s.crop });
  assertEquals(g.ok ? 'published' : g.held, 'pixels_not_clean');
  const cut = await pixelGate('page', s.ask, s.paint, pixelBudget(), { plan: s.plan, crop: async () => { throw new Error('tile_failed'); } });
  assertEquals(cut.ok ? 'published' : cut.held, 'pixels_unverified', 'a tile that cannot be cut is no answer');
  const poor = await pixelGate('page', s.ask, s.paint, pixelBudget(s.plan.usd - 0.001), { plan: s.plan, crop: s.crop });
  assertEquals(poor.ok ? 'published' : poor.held, 'pixels_budget', 'a look the budget cannot pay for is held, never half-asked');
  assertEquals(poor.calls, 0);
});

Deno.test('a FILE is released only when it was clean on the first look (index.ts asks fileMayBeShared on both file routes)', () => {
  const ok = (first: boolean): PixelOutcome => ({ ok: true, jpgB64: 'x', calls: 13, usd: 0.07, painted: first ? 0 : 1, firstLookClean: first, boxes: [], detail: { calls: 13, usd: 0.07, boxes_added: first ? 0 : 1, tiles: 12 } });
  assertEquals([fileMayBeShared(ok(true)), fileMayBeShared(ok(false)), fileMayBeShared({ ok: false, held: 'pixels_not_clean', calls: 3, usd: 0, detail: {} })], [true, false, false]);
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const branch = (mode: string) => { const a = src.indexOf(`if (body.mode === '${mode}')`); return src.slice(a, src.indexOf('\n    }\n', a)); };
  assertMatch(branch('file'), /if \(!fileMayBeShared\(g\)\) \{ await admin\.storage\.from\('drawing-files'\)\.remove\(\[path\]\)/);
  assertMatch(branch('verify_file'), /if \(!fileMayBeShared\(g\)\) return await refuse\(/);
  assert(!/g\.calls > 1/.test(src), 'the first-look rule is fileMayBeShared, not a count of calls (a tiled look is many calls)');
});

Deno.test('jpegSize reads a JPEG\'s pixel size from its header, without decoding it', async () => {
  const jpg = await Deno.readFile(new URL('../_shared/testdata/licence_near_blank.jpg', import.meta.url));
  const s = jpegSize(jpg);
  assert(s && s.w > 100 && s.h > 100, JSON.stringify(s));
  const sof = new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 17, 8, 0x07, 0x2E, 0x0A, 0x28, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  assertEquals(jpegSize(sof), { w: 2600, h: 1838 });
  assertEquals(jpegSize(new Uint8Array([0x89, 0x50, 0x4E, 0x47])), null);
});

Deno.test('verify_file: the server counts the pending file\'s pages and checks each image\'s shape and ink against its own reading', async () => {
  // COUNT: one image per page, never a trimmed list (one image of a 5-page file released pages 2-5 unseen).
  assertEquals(pageCountHolds(5, 1, 20), 'image_count_is_not_page_count');
  assertEquals(pageCountHolds(25, 25, 20), 'file_over_page_cap');
  assertEquals(pageCountHolds(5, 5, 20), null);
  // SHAPE: the page's MediaBox, quarter turns applied.
  const a1 = { width: 2384, height: 1684, rotate: 0 };
  assert(aspectMatches(a1, 2600, 1836) && !aspectMatches(a1, 1836, 2600) && aspectMatches({ ...a1, rotate: 90 }, 1836, 2600));
  // DENSITY (round 3): a released file can be zoomed, so its image carries 12 px for 6 pt; a coarse image of the right
  // shape and ink (the tiles would only blur it up) is refused. A1 needs 4,768 px on its long side, A3 2,381.
  assertEquals(pxNeeded(a1), 4768);
  assertEquals(pxNeeded({ width: 1190.55, height: 841.89 }), 2382);
  assert(!imageDenseEnough(a1, 2600, 1836) && !imageDenseEnough(a1, 600, 424) && imageDenseEnough(a1, 4768, 3368));
  assert(imageDenseEnough({ width: 1190, height: 842 }, 2600, 1840), 'the 2600 px render of an A3 page is dense enough');
  // INK: a page's own ink agrees; a blank image and another sheet's ink do not.
  const read = async (f: string) => (await pdfPages(await Deno.readFile(new URL(`../_shared/testdata/${f}`, import.meta.url))))[0];
  const pool = expectedInk(await read('review_f3/v00_control.pdf'));
  const other = expectedInk(await read('zz_pool_b1_embedded_font.pdf'));
  assert(pool.filter(Boolean).length > 20, 'the fixture draws across the sheet');
  assert(inkAgrees(pool, pool).ok, 'the same page agrees');
  assert(!inkAgrees(pool, pool.map(() => false)).ok, 'a blank image is not this page');
  assert(!inkAgrees(pool, pool.map(() => true)).ok, 'an image inked everywhere is not this page');
  const shifted = pool.map((_, i) => pool[(i + 9 * 32 + 11) % pool.length]);
  assert(!inkAgrees(pool, shifted).ok, 'another arrangement of ink is not this page');
  assert(!inkAgrees(other, pool).ok || !inkAgrees(pool, other).ok, 'another sheet is not this page');
  // And the route asks all three before any model call, over every image it was sent.
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const a = src.indexOf("if (body.mode === 'verify_file')"), v = src.slice(a, src.indexOf('\n    }\n', a));
  assert(!/images\.slice\(/.test(v), 'images are never trimmed to the cap');
  const order = ['pageCountHolds(', 'aspectMatches(', 'imageDenseEnough(', 'inkAgrees(', 'gatePage('].map((k) => v.indexOf(k));
  assert(order.every((x, i) => x > 0 && (i === 0 || x > order[i - 1])), `count, shape, density and ink come before the gate: ${order}`);
});
