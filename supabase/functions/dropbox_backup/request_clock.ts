// THE WORKER'S CLOCK BELONGS TO THE REQUEST, NOT TO THE ISOLATE (agent: it_engineer, 13 Nov 2026).
//
// index.ts kept `const T0 = Date.now(); const DEADLINE = T0 + 110_000;` at module level. A module is evaluated once, when the
// edge isolate starts, and the isolate then serves later requests too. So every request that reached an isolate older than
// 110 seconds was already past its deadline before it began: the sandbox loop never ran, and the daily path claimed up to 8
// rows and released them all at once. MEASURED 13 Nov 2026 (independent review of #1998): the isolate that served a sandbox
// run at 06:09:10 UTC answered the next request at 06:11:43 with done 0 and no results although one row was pending; a fresh
// isolate moved that row at 06:13:57. agent_runs of 11 Nov show the same shape (started_at, which is T0, two to three minutes
// before finished_at). Nothing was lost (a released row is claimed again) but a drain stalled until an isolate was replaced.
//
// The clock is carried by AsyncLocalStorage, as _shared/turn_cache.ts carries its per-turn cache, so two requests that
// overlap in one isolate each keep their own start and their own deadline, and no helper needs a new parameter.
import { AsyncLocalStorage } from 'node:async_hooks';

/** Room left under the 150 s edge limit to record the result. */
export const BUDGET_MS = 110_000;

const clock = new AsyncLocalStorage<{ t0: number }>();

/** Runs one request with its own clock. `now` is a parameter for the test only. */
export const inRequest = <T>(fn: () => Promise<T>, now: number = Date.now()): Promise<T> => clock.run({ t0: now }, fn);

/** When THIS request started. Outside a request (never, in the worker) it is "now", so work is never refused as late. */
export const t0 = (): number => clock.getStore()?.t0 ?? Date.now();

/** When THIS request must stop claiming and uploading. */
export const deadline = (): number => t0() + BUDGET_MS;
