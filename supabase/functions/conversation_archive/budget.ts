// How many PDFs one conversation_archive worker draws (it_engineer, 2 Nov 2026).
//
// Measured on production (function_edge_logs + function_logs, 1 Nov 21:16-21:47Z): 3 sweeps of `limit` 4 died
// "CPU Time exceeded" (HTTP 546) after 10.6-15.1 s, archiving nothing, while 366 calls of the same shape answered 200
// (p50 4.1 s wall, mostly waiting on storage and the database). A count does not bound CPU - one long email costs what
// ten short ones do (the renderer's font
// subsetting and line breaking scale with the text). So the sweep measures each render and starts the next one only
// while the time spent plus the slowest render so far stays inside RENDER_BUDGET_MS, well under the edge's 2 s CPU cap
// with room for boot, the database calls and the upload. Rows it does not reach stay pending, oldest first, for the
// next sweep 15 minutes later; the first row of a sweep is always drawn, so the list always moves.
// prevented by: conversation_archive/budget.test.ts
export const RENDER_BUDGET_MS = 1200;

/** One render's drawing time: its wall time less the time it spent waiting on asset fetches (never below 0). */
export function drawingMs(wallMs: number, waitedMs: number): number {
  return Math.max(0, wallMs - Math.max(0, waitedMs));
}

/** May one more render start, given the render time spent so far and the slowest render seen in this worker? */
export function mayRenderNext(spentMs: number, slowestMs: number, budgetMs = RENDER_BUDGET_MS): boolean {
  return spentMs === 0 || spentMs + slowestMs <= budgetMs;
}
