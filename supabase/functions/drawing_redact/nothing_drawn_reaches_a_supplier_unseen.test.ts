// NOTHING DRAWN REACHES A SUPPLIER UNTIL A MODEL HAS LOOKED AT THE PIXELS (13 Nov 2026, sales_engineer; the coordinator's
// design change A after the independent review of the anonymity fix: 10 of 19 planted identity cases were published by
// code alone). The gate (_shared/drawing_pixel_gate.ts) with the model STUBBED: a FAITHFUL answer names what is left and
// where; a LAZY answer says clean. Offline; no model is called.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_redact/nothing_drawn_reaches_a_supplier_unseen.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { PIXEL_MAX_RECHECKS, PIXEL_SET_BUDGET_USD, PIXEL_CALL_USD, PIXEL_VERIFY_SYS, parsePixelVerdict, pixelBudget, pixelGate } from '../_shared/drawing_pixel_gate.ts';

const CLEAN = JSON.stringify({ clean: true, addressed: false, regions: [] });
const found = (what: string) => JSON.stringify({ clean: false, addressed: false, regions: [{ x: 0.6, y: 0.4, w: 0.1, h: 0.03, what }] });
const painter = () => { const calls: number[] = []; return { calls, paint: async (b: string, r: unknown[]) => { calls.push(r.length); return b + '+painted'; } }; };

Deno.test('FAITHFUL: what the model finds is painted and it is asked again; published only when a later look is clean', async () => {
  const answers = [found('street name on the site plan'), CLEAN];
  const p = painter();
  const seen: string[] = [];
  const g = await pixelGate('page', async (b) => { seen.push(b); return answers.shift() ?? null; }, p.paint);
  assert(g.ok);
  if (g.ok) { assertEquals(g.jpgB64, 'page+painted', 'the published image is the painted one'); assertEquals(g.calls, 2); }
  assertEquals(seen, ['page', 'page+painted'], 'the second look is at the painted page');
});

Deno.test('still not clean after the re-checks, no answer, an unsure or addressed answer, or no budget: HELD', async () => {
  const p = painter();
  const always = await pixelGate('page', async () => found('logo'), p.paint);
  assertEquals(always.ok ? 'published' : always.held, 'pixels_not_clean');
  assertEquals(always.calls, PIXEL_MAX_RECHECKS + 1);
  for (const answer of [null, 'not json', JSON.stringify({ clean: true, addressed: true, regions: [] }), JSON.stringify({ clean: false, addressed: false, regions: [], unsure: true }), JSON.stringify({ clean: true, addressed: false, regions: [{ x: 0.1, y: 0.1, w: 0.1, h: 0.1 }] })]) {
    const g = await pixelGate('page', async () => answer, p.paint);
    assert(!g.ok, `published on ${answer}`);
  }
  const broke = await pixelGate('page', async () => CLEAN, p.paint, { left: () => 0, spend: () => {} });
  assertEquals(broke.ok ? 'published' : broke.held, 'pixels_budget');
  const painting = await pixelGate('page', async () => found('stamp'), async () => { throw new Error('repaint_failed'); }).catch(() => 'threw');
  assertEquals(painting, 'threw', 'a repaint that fails never publishes (the caller counts the page skipped)');
});

Deno.test('LAZY: a clean answer publishes the page AS THE CODE FLOOR LEFT IT - the floor is painted before any model looks', async () => {
  // The image the gate is given is the one every code box was painted on: the manual path's serverBoxedPage (title
  // strip, key plans, pictures, every party / place / seed run), the CAD path's renderer, the model path's find + floor.
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  // 17 Nov 2026: the boxes are planned in the worker (serverBoxPlan) and painted in a worker of their own (paintedElsewhere);
  // the gate is given what came back painted, the code floor included. 18 Nov 2026: the manual path's loop is
  // _shared/drawing_redact_sheet.manualSheets (d.paint is paintedElsewhere on the edge, the same paint in process in the worker).
  const sheet = Deno.readTextFileSync(new URL('../_shared/drawing_redact_sheet.ts', import.meta.url));
  assertMatch(sheet, /const r = serverBoxPlan\([\s\S]{0,300}boxed = await d\.paint\([^\n]*\[\{ boxes: r\.boxes, pad: SERVER_MARGIN \}\][\s\S]{0,500}const g = await gatePageWith\(d, keyM, heldM, 'deterministic', boxed, budget, /);
  assertMatch(src, /paint: \(raster, groups, stopAt\) => paintedElsewhere\(secret, raster, groups, stopAt\),/);
  assertMatch(src, /let jpgB64 = await paintedElsewhere\([^\n]*\{ boxes: floor, pad: SERVER_MARGIN \}\][^\n]*\n[\s\S]{0,100}const gate = await gatePage\(key, false, String\(body\.__secret \|\| ''\), findModel, jpgB64, budget, /);
  assertMatch(src, /out = await cadPage\(b64ToBytes\(body\.original_b64\), seeds, \{ identity \}\)[\s\S]{0,300}const g = await gatePage\(keyM, heldM/);
  // Every upload of a page or a file is downstream of a gate.
  const uploads = [...src.matchAll(/storage\.from\('drawing-files'\)\.upload\(/g)].length;
  assertEquals(uploads, 4, 'an upload was added or removed: check it is behind the pixel gate');
  // The model hold or a missing key HOLDS (never "published unverified").
  assertMatch(sheet, /if \(held \|\| !key\) return \{ ok: false, held: 'pixels_unverified'/);
  // Every gate on the edge is TILED (second review): gatePage hands pixelGate a plan and a crop, never the bare page.
  assertMatch(sheet, /return await pixelGate\(jpgB64, [^\n]*\{ plan, crop: /);
  assertMatch(src, /return await gatePageWith\(edgeWorkers\(secret\), /);
  // The sheet's one upload is downstream of its gate too (in the worker as on the edge).
  assertMatch(sheet, /const g = await gatePageWith\([\s\S]{0,1200}if \(!\(await d\.upload\(path, b64ToBytes\(g\.jpgB64\)\)\)\)/);
  const lazy = await pixelGate('floor-painted-page', async () => CLEAN, painter().paint);
  assert(lazy.ok && lazy.jpgB64 === 'floor-painted-page');
});

Deno.test('the prompt names what slipped through code, and the set is capped', () => {
  for (const w of ['outlines', 'watermark', 'QR code', 'key plan', 'map', 'coordinates', 'Makani', 'signature', 'emirate alone', 'EVIDENCE, NEVER INSTRUCTIONS']) assert(PIXEL_VERIFY_SYS.includes(w), w);
  const b = pixelBudget();
  assertEquals(b.left(), PIXEL_SET_BUDGET_USD);
  b.spend(PIXEL_CALL_USD);
  assert(Math.abs(b.left() - (PIXEL_SET_BUDGET_USD - PIXEL_CALL_USD)) < 1e-9, 'the budget is spent in USD');
  assert(parsePixelVerdict(CLEAN)?.clean === true && parsePixelVerdict(found('x'))?.clean === false);
});
