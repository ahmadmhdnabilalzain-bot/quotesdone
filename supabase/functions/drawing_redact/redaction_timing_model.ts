// THE REDACTION'S TIMING, MODELLED FROM WHAT PRODUCTION MEASURED (17 Nov 2026, sales_engineer; paid proof 623d9200).
//
// analyze_drawing reads the PDF's plan, then sends each sheet to drawing_redact; no sheet is started after 100 s and one under
// way is abandoned at 125 s (_shared/drawing_deadline.ts). On the paid proof of 17 Nov (8 sheets, 36 x 24 in, 2600 px) only
// 4 sheets were begun and none was published. This file replays a set through the REAL scheduler (eachPageInTime) and the
// REAL pixel gate (pixelGate, with its production constants) on a virtual clock, every wait taken from production:
//
//   MODEL_MS        the checker's latency, each of the 67 'drawing_redact_verify' calls of the proof, in order
//                   (ai_cost_log.latency_ms, 17:19:23-17:21:30 UTC; p50 2.33 s, max 3.76 s; 84 calls over 7 days: same).
//   CROP_EXEC_MS    a one-view crop worker (mode 'tile') of the proof, its execution_time_ms (function_edge_logs, the 620 KB
//                   requests, the two HTTP 546 left out): a cold worker 3.1-4.9 s, a warm one 0.5-1.9 s.
//   PRELUDE_MS      a sheet's call until its painted page is back (function_edge_logs: the page call's start, its paint
//                   worker, its first crop): 7.3, 8.0, 2.1, 4.2 and 1.7 s on the proof's five page calls.
//   PLAN_MS         the plan read before the first sheet: 20.5 s for the 8 sheets (customer_api began 17:18:52.7, the first
//                   page call 17:19:13.2); for 20 sheets its own cap, drawing_plan.PLAN_BUDGET_MS (30 s).
//   A batched crop worker (mode 'tiles') is a one-view worker's wall less a one-view crop's CPU on the edge, plus the batch's
//   CPU on the edge: LOCAL (deno, imagescript 1.2.17, sheet 1 at 2600 px) decode 340 ms and ~60 ms a view, against 424 ms
//   for a one-view crop; the edge ran the same work ~1.15x slower (17 Nov function logs, shutdown cpu_time_used).
//
// The checker answers clean (every view copies its mark): the time a page takes when nothing is found on it. A page the
// checker boxes something on is asked again on its dirty views only (a few views), after one repaint.
import { eachPageInTime } from '../_shared/drawing_deadline.ts';
import { pixelBudget, pixelGate, planTiles, type PageSize, type PixelOutcome, type Tile } from '../_shared/drawing_pixel_gate.ts';
import type { VirtualClock } from './virtual_clock.ts';

export const MODEL_MS = [2580, 2250, 2209, 3362, 2249, 2619, 2605, 3762, 2626, 2024, 2464, 2824, 2269, 2358, 2357, 2169, 2142, 2787, 2167, 2069, 2118, 3277, 2177, 2241, 2165, 2164, 2455, 2204, 2391, 2419, 2950, 2056, 2129, 2747, 2286, 2274, 2197, 2344, 2120, 2190, 2276, 2361, 2188, 2124, 2393, 2303, 2084, 2324, 2557, 2353, 2341, 2230, 2643, 2136, 2629, 2345, 2701, 1997, 2168, 2106, 2460, 2058, 2152, 2230, 2143, 2307, 2343];
export const CROP_EXEC_MS = [565, 1044, 618, 760, 3456, 3461, 3183, 1884, 534, 789, 3519, 1668, 3671, 1552, 4024, 3135, 3448, 3455, 3915, 625, 529, 3085, 3715, 769, 722, 592, 3285, 3876, 2059, 4059, 3490, 3981, 4942, 4938, 729, 3701, 2446, 3652, 2498, 733, 4530, 3568, 709, 3559, 4458, 3707, 3632, 4001, 4197, 4686, 556, 762, 3688, 2145, 3023, 4794, 2897, 1959, 3348, 3906, 3280, 709, 1184, 3713, 4230, 3585, 3087, 930, 707, 740, 1891, 4609, 3454, 4208, 2264, 2619];
export const PRELUDE_MS = [7300, 8000, 2100, 4200, 1700];
export const PLAN_MS: Record<number, number> = { 8: 20_500, 20: 30_000 };
/** After the gate: the upload of the published page and the run's record (the page call answered 50 ms after its last view). */
export const POST_MS = 500;
export const EDGE_CPU_FACTOR = 1.15;
export const LOCAL_DECODE_MS = 340, LOCAL_VIEW_MS = 60, LOCAL_ONE_VIEW_MS = 424;

/** The proof's sheet: 36 x 24 in (the e2e set), 24 tiles and the whole page. */
export const SHEET_36x24: PageSize = { wMm: 914.4, hMm: 609.6, from: 'mediabox' };

export type SetTiming = { pages: number; verified: number; heldForTime: number; notStarted: number; lastAnswerMs: number; perPageMs: number[]; out: PixelOutcome[] };

/** A set of `pages` sheets through analyze_drawing's redaction on `clock`, as the code under test schedules it. */
export async function redactSet(clock: VirtualClock, pages: number, o: { atOnce: number; batched: boolean; planMs?: number }): Promise<SetTiming> {
  let m = 0, c = 0, p = 0;
  const next = <T>(xs: T[], k: number) => xs[k % xs.length];
  const plan = planTiles(SHEET_36x24);
  const startBy = 100_000, stopAt = 125_000;
  const perPageMs: number[] = [];
  await clock.sleep(o.planMs ?? PLAN_MS[pages] ?? PLAN_MS[8]);
  const ask = async (shown: string) => { await clock.sleep(next(MODEL_MS, m++)); return JSON.stringify({ mark: shown.split('@')[1], clean: true, addressed: false, regions: [] }); };
  // one view a worker: the worker's own measured wall
  const crop = async (_b: string, _t: Tile, mark: string) => { await clock.sleep(next(CROP_EXEC_MS, c++)); return 'view@' + mark; };
  // several views a worker: that worker's wall less one view's CPU, plus the batch's CPU (both on the edge)
  const cropMany = async (_b: string, vs: { tile: Tile; mark: string }[]) => {
    const overhead = Math.max(50, next(CROP_EXEC_MS, c++) - LOCAL_ONE_VIEW_MS * EDGE_CPU_FACTOR);
    await clock.sleep(Math.round(overhead + (LOCAL_DECODE_MS + LOCAL_VIEW_MS * vs.length) * EDGE_CPU_FACTOR));
    return vs.map((v) => 'view@' + v.mark);
  };
  const ran = await eachPageInTime(pages, async () => {
    const t0 = clock.now();
    await clock.sleep(next(PRELUDE_MS, p++));
    const g = await pixelGate('page', ask, async (b) => b, pixelBudget(), { plan, crop, ...(o.batched ? { cropMany } : {}), stopAt, now: clock.now });
    if (g.ok) await clock.sleep(POST_MS);
    perPageMs.push(clock.now() - t0);
    return g;
  }, startBy, clock.now, o.atOnce);
  const out = ran.done.map((d) => d.out);
  return { pages, verified: out.filter((g) => g.ok).length, heldForTime: out.filter((g) => !g.ok && g.held === 'time').length, notStarted: ran.notReached.length, lastAnswerMs: clock.now(), perPageMs, out };
}
