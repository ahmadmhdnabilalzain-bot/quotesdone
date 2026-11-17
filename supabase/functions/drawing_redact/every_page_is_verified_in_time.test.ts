// EVERY PAGE OF A DRAWING SET IS VERIFIED IN TIME (17 Nov 2026, sales_engineer; paid proof 623d9200, founder ledger 580: the
// drawing reaches the suppliers, redacted).
//
// MEASURED on that proof (function logs and ai_cost_log, SELECT): an 8-sheet set; the plan read took 20.5 s; each sheet
// then took 20.5-27.5 s in drawing_redact, one after another; no sheet is started after 100 s, so 4 were begun and none was
// published. A sheet's time was its 25 views, four at a time, each a crop worker of its own (0.5-4.9 s) then the model
// (2.0-3.8 s). The change: a crop worker cuts several views from one decode (mode 'tiles'), a page asks its views eight at a
// time, and analyze_drawing runs REDACT_PAGES_AT_ONCE sheets side by side. WHAT is checked does not change: every view is
// still asked with its own reading mark, and a view with no answer still holds the page.
//
// The timing below is the REAL scheduler and the REAL gate on a virtual clock, every wait one production measured
// (./redaction_timing_model.ts says which). Offline, no model, no network.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/drawing_redact/every_page_is_verified_in_time.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { DRAWING_DEADLINE, REDACT_PAGES_AT_ONCE } from '../_shared/drawing_deadline.ts';
import { ASKS_AT_ONCE, CROPS_AT_ONCE, PIXEL_PAGE_RESERVE_USD, VIEWS_PER_CROP, pixelBudget, pixelGate, planTiles, type Tile } from '../_shared/drawing_pixel_gate.ts';
import { virtualClock } from './virtual_clock.ts';
import { SHEET_36x24, redactSet } from './redaction_timing_model.ts';

const VIEWS = planTiles(SHEET_36x24).calls;

Deno.test('the 8-sheet set of the proof: one sheet at a time with a worker per view, most sheets are never begun (the defect, modelled)', async () => {
  const clock = virtualClock();
  const r = await clock.run(redactSet(clock, 8, { atOnce: 1, batched: false }));
  assertEquals(VIEWS, 25);
  assert(r.verified < 8 && r.notStarted > 0, `the old schedule verified ${r.verified} of 8`);
  assert(Math.min(...r.perPageMs) > 30_000, `a sheet took ${Math.min(...r.perPageMs)} ms with every view asked`);
});

Deno.test('the 8-sheet set as the code runs it now: every sheet verified, the last answer well before the 100 s start-by', async () => {
  const clock = virtualClock();
  const r = await clock.run(redactSet(clock, 8, { atOnce: REDACT_PAGES_AT_ONCE, batched: true }));
  assertEquals(r.verified, 8, JSON.stringify({ time: r.heldForTime, notStarted: r.notStarted }));
  assert(r.lastAnswerMs < DRAWING_DEADLINE.startByMs, `the set ended at ${r.lastAnswerMs} ms`);
  assert(Math.max(...r.perPageMs) < 25_000, `a sheet took ${Math.max(...r.perPageMs)} ms`);
  console.log(`8 sheets: verified ${r.verified}, last answer ${(r.lastAnswerMs / 1000).toFixed(1)} s, a sheet ${(Math.min(...r.perPageMs) / 1000).toFixed(1)}-${(Math.max(...r.perPageMs) / 1000).toFixed(1)} s`);
});

Deno.test('a 20-sheet set: nearly every sheet verified inside the request; none is lost or abandoned, and the few never begun are counted to be queued', async () => {
  const clock = virtualClock();
  const r = await clock.run(redactSet(clock, 20, { atOnce: REDACT_PAGES_AT_ONCE, batched: true }));
  assert(r.verified >= 18, `verified ${r.verified} of 20`);
  assertEquals(r.heldForTime, 0, 'no sheet under way is abandoned at the stop');
  assertEquals(r.verified + r.notStarted, 20, 'every sheet is either verified or never begun (customer_api queues those)');
  assert(r.lastAnswerMs <= DRAWING_DEADLINE.stopAtMs, `the last sheet answered at ${r.lastAnswerMs} ms`);
  console.log(`20 sheets: verified ${r.verified}, not begun ${r.notStarted}, last answer ${(r.lastAnswerMs / 1000).toFixed(1)} s`);
});

/** A gate on one 36 x 24 in sheet with the batched crop, recording what each worker and the model were given. */
async function batchedGate(o: { cropFails?: (call: number) => boolean; wrongMark?: (view: number) => boolean; clean?: (view: number, round: number) => boolean } = {}) {
  const clock = virtualClock();
  const plan = planTiles(SHEET_36x24);
  const cropCalls: number[] = []; const marks: string[] = []; let cropsNow = 0, cropsPeak = 0, asksNow = 0, asksPeak = 0, asked = 0, painted = 0, round = 0;
  const shownView = new Map<string, number>();
  const cropMany = async (_b: string, vs: { tile: Tile; mark: string }[]) => {
    const call = cropCalls.push(vs.length); cropsNow++; cropsPeak = Math.max(cropsPeak, cropsNow);
    await clock.sleep(800); cropsNow--;
    if (o.cropFails?.(call)) throw new Error('tiles_failed');
    return vs.map((v) => { marks.push(v.mark); const id = `view${shownView.size}@${v.mark}`; shownView.set(id, plan.tiles.concat(plan.whole ? [plan.whole] : []).indexOf(v.tile)); return id; });
  };
  const ask = async (shown: string) => {
    const n = asked++; asksNow++; asksPeak = Math.max(asksPeak, asksNow);
    await clock.sleep(2_330); asksNow--;
    const view = shownView.get(shown) ?? -1, mark = o.wrongMark?.(n) ? '000000' : shown.split('@')[1];
    const clean = o.clean ? o.clean(view, round) : true;
    return JSON.stringify({ mark, clean, addressed: false, regions: clean ? [] : [{ x: 0.1, y: 0.1, w: 0.2, h: 0.1, what: 'consultant name' }] });
  };
  const crop = async () => { throw new Error('the one-view crop is not used when the batched crop is given'); };
  const g = await clock.run(pixelGate('page', ask, async (b) => { painted++; round++; return b; }, pixelBudget(), { plan, crop, cropMany, stopAt: 125_000, now: clock.now }));
  return { g, cropCalls, marks, cropsPeak, asksPeak, asked, painted, ms: clock.now() };
}

Deno.test('batched crops: every view is cut once and asked once with a mark of its own; workers and asks stay within their limits', async () => {
  const r = await batchedGate();
  assert(r.g.ok && r.g.firstLookClean);
  assertEquals(r.cropCalls.reduce((s, n) => s + n, 0), VIEWS, 'every view is cut');
  assert(r.cropCalls.every((n) => n <= VIEWS_PER_CROP), `a worker was given ${Math.max(...r.cropCalls)} views`);
  assertEquals(r.cropCalls.length, Math.ceil(VIEWS / VIEWS_PER_CROP));
  assertEquals(r.asked, VIEWS, 'every view is asked');
  assertEquals(new Set(r.marks).size, VIEWS, 'every view carries a mark of its own');
  assert(r.cropsPeak <= CROPS_AT_ONCE && r.asksPeak <= ASKS_AT_ONCE, `peaks: ${r.cropsPeak} crop workers, ${r.asksPeak} asks`);
  assert(r.ms < 15_000, `the views took ${r.ms} ms`);
});

Deno.test('batched crops fail closed: a crop worker that does not answer, or a view answered without its mark, HOLDS the page', async () => {
  const dead = await batchedGate({ cropFails: (call) => call === 3 });
  assert(!dead.g.ok && dead.g.held === 'pixels_unverified', 'a group of views never cut is no answer');
  assertEquals(dead.asked, VIEWS - VIEWS_PER_CROP, 'the views of the dead worker were never asked');
  const unread = await batchedGate({ wrongMark: (n) => n === 7 });
  assert(!unread.g.ok && unread.g.held === 'pixels_unverified' && unread.g.detail.unread === 1, 'an answer without the view\'s mark did not read it');
});

Deno.test('batched crops: what the checker finds is painted and only the views that were not clean are cut and asked again', async () => {
  const r = await batchedGate({ clean: (view, round) => !(view === 3 && round === 0) });
  assert(r.g.ok && !r.g.firstLookClean);
  assertEquals(r.painted, 1);
  assertEquals(r.asked, VIEWS + 1, 'the dirty view alone is asked again');
  assertEquals(r.cropCalls.at(-1), 1);
});

Deno.test('drawing_redact cuts views in its own worker (mode tiles), refuses a view without a mark, and takes what the other pages in flight may spend', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const a = src.indexOf("if (body.mode === 'tiles')"), branch = src.slice(a, src.indexOf('\n    }\n', a));
  assert(a > 0, 'mode tiles exists');
  assertMatch(branch, /vs\.length > VIEWS_PER_CROP \|\| vs\.some\(\(v\) => !v\?\.tile \|\| !\/\^\\d\{6\}\$\/\.test\(String\(v\?\.mark/);
  assertMatch(branch, /tilesJpeg\(/);
  assert(!/publish\(|storage\.from\(/.test(branch), 'the crop worker records and uploads nothing');
  assertMatch(src, /cropMany: \(b, vs\) => cropsElsewhere\(secret, b, vs, stopAt\)/);
  assertMatch(src, /const r = await workerAnswer\(ask, 'tiles', stopAt\);/);
  assertMatch(src, /j\.jpgs\.length !== views\.length[^\n]*throw new Error\('tiles_failed'\)/);
  assertEquals((src.match(/await budgetInFlight\(body\.source_path, body\.spent_usd\)/g) ?? []).length, 4, "mode gate, read_strings, the manual and the model path");
});

Deno.test('customer_api runs REDACT_PAGES_AT_ONCE sheets side by side, reserves the others\' spend, and hands the pages back in page order', () => {
  const api = Deno.readTextFileSync(new URL('../customer_api/actions/documents.ts', import.meta.url));
  assertMatch(api, /\}, redStartBy, Date\.now, REDACT_PAGES_AT_ONCE\);/);
  assertMatch(api, /const othersUsd = Math\.max\(0, inFlight - 1\) \* PIXEL_PAGE_RESERVE_USD;/);
  assertMatch(api, /spent_usd: othersUsd/);
  assertMatch(api, /for \(let b = 0; b < batches; b\+\+\) \{ redacted = redacted\.concat\(pathsOf\[b\] \?\? \[\]\); redJobs\.push\(\.\.\.\(jobsOf\[b\] \?\? \[\]\)\); \}/);
  assert(REDACT_PAGES_AT_ONCE >= 2 && REDACT_PAGES_AT_ONCE <= 4);
  // One A1 look: what a set's 20-page budget figure is made of (drawing_pixel_gate PIXEL_COST).
  assert(PIXEL_PAGE_RESERVE_USD > 0.05 && PIXEL_PAGE_RESERVE_USD < 0.15, String(PIXEL_PAGE_RESERVE_USD));
});
