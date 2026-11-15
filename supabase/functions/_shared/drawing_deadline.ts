// drawing_deadline — A DRAWING'S PAGES ARE CHECKED INSIDE THE REQUEST THAT CARRIES THEM, OR SAID TO BE HELD FOR TIME
// (round 4 of the drawings fix, 15 Nov 2026, sales_engineer; third review ANONYMITY F3 DRAWINGS 3, fix 2).
//
// MEASURED (READ, the third review): the redaction loop runs page by page inside analyze_drawing's 150 s edge wall, and
// an A1 page is now about 21 model calls (planTiles: 20 tiles + the whole page, 4 at a time) plus a crop worker per call;
// it was 2-4. A 3-4 page A1 set passes the wall, the worker is killed, no held row is written and nothing is shared.
// So: no new page is STARTED after `startBy` (default 100 s into the request), and a page under way is abandoned at
// `stopAt` (default 125 s: one model call of up to about 8 s still lands inside analyze_drawing's 140 s answer budget,
// customer_api ANALYZE_DRAWING_BUDGET_MS). A page cut either way is HELD with reason 'time' - counted, recorded and said,
// never lost. LOCAL, slow stub (every model call 8 s) on a 4-page A1 set: SP/f3fix4 slow_stub log in the hand-back.
//
// A caller may only bring the deadlines EARLIER (customer_api passes its own request's clock, which started before this
// function's); a later value than the default is ignored.

export const DRAWING_DEADLINE = { startByMs: 100_000, stopAtMs: 125_000, callGraceMs: 10_000 } as const;

/**
 * THE CALLS UNDER WAY ARE CUT TOO (round 5, fourth review fix 3). The stop kept new views from starting, but a model call
 * started at 124 s had no signal (the gateway's own 55 s applied), a crop worker 60 s and a repaint 90 s twice: such a call
 * outlived customer_api's 140 s abort and the page was recorded as redactor_died, with the generic message. Every model,
 * crop and repaint call now waits at most until stopAt + callGraceMs (and never less than 1 s, never more than its own
 * cap); one cut there is held for time (pixelGate: an answer missing past the stop is 'time').
 */
export function callTimeoutMs(stopAt: number | undefined, capMs: number, now: () => number = Date.now): number {
  if (stopAt === undefined || !Number.isFinite(stopAt)) return capMs;
  return Math.min(capMs, Math.max(1_000, stopAt + DRAWING_DEADLINE.callGraceMs - now()));
}

/** The hold reason for a page not checked in time. */
export const TIME_HELD = 'time' as const;

export type Deadlines = { startBy: number; stopAt: number };

/** The deadlines of a request that began at `startedAt` (epoch ms), brought earlier by the caller's `deadline_at` and
 *  `stop_at` (epoch ms) when it sends them. */
export function deadlinesFrom(body: { deadline_at?: unknown; stop_at?: unknown } | null | undefined, startedAt: number): Deadlines {
  const own = { startBy: startedAt + DRAWING_DEADLINE.startByMs, stopAt: startedAt + DRAWING_DEADLINE.stopAtMs };
  const early = (v: unknown, d: number) => { const n = Number(v); return Number.isFinite(n) && n > 0 ? Math.min(n, d) : d; };
  const stopAt = early(body?.stop_at, own.stopAt);
  return { startBy: Math.min(early(body?.deadline_at, own.startBy), stopAt), stopAt };
}

/**
 * Run `run(i)` for each page in order, starting none after `startBy`. Returns what ran and the pages never started.
 * Sequential on purpose: two pages of one set never spend its budget at once (customer_api REDACT_BATCH).
 */
export async function eachPageInTime<T>(pages: number, run: (i: number) => Promise<T>, startBy: number, now: () => number = Date.now): Promise<{ done: { i: number; out: T }[]; notReached: number[] }> {
  const done: { i: number; out: T }[] = [], notReached: number[] = [];
  for (let i = 0; i < pages; i++) {
    if (now() >= startBy) { notReached.push(i); continue; }
    done.push({ i, out: await run(i) });
  }
  return { done, notReached };
}
