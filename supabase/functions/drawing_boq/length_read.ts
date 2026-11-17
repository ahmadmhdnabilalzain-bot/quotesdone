// length_read — customer_api's side of the duct and pipe lengths, read SHEET BY SHEET (17 Nov 2026, sales_engineer; paid
// proof 14173f94). drawing_set/lengths.ts says what was measured and why the one whole-set call is gone. No parser and no
// measuring here: customer_api bundles this file, and it only asks drawing_boq and checks the answers' shape.
//
// THE DEAD WORKER (the same proof): the whole-set call answered HTTP 500 on a worker the platform was shutting down
// (EarlyDrop), and customer_api read only a 546 or no answer as a dead worker, so a 500 left the line blank. Here ANY
// answer that is not ok - 500, 546, a refusal, a throw, a timeout - is asked ONCE more, on a fresh request, and a part
// that fails twice gives the read up (null): the caller then queues the CAD worker, and only when that cannot be queued
// says on the line itself that the length is to be confirmed (length_notes.ts lengthsToConfirm).
import type { LengthsPart } from './drawing_set/lengths.ts';

/** Sheets per drawing_boq 'lengths' call, how many such calls run at once, and the most one call reads whatever it is
 *  asked. LOCAL, cold process, the 8-sheet e2e set: one sheet per call 413-462 ms of CPU against 2,030-2,106 ms for the
 *  whole set in one call (the edge's cap is 2 s). */
export const LENGTHS_PAGES_PER_CALL = 1;
export const LENGTHS_PARALLEL = 4;
export const LENGTHS_MAX_PAGES_PER_CALL = 4;

/** One drawing_boq request (mode 'lengths' is added by the caller's transport); null or a throw = no answer. */
export type LengthsCall = (body: Record<string, unknown>) => Promise<unknown>;

const partOk = (j: any, from: number, to: number): j is LengthsPart & { ok: true } =>
  !!j && j.ok === true && Number.isInteger(j.pages) && j.pages >= 0 && j.from === from && Array.isArray(j.sheets)
  && j.sheets.length === Math.max(0, Math.min(to, j.pages) - from);

async function pool<T, R>(items: T[], width: number, job: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length); let next = 0;
  await Promise.all(Array.from({ length: Math.min(width, items.length) }, async () => { while (next < items.length) { const i = next++; out[i] = await job(items[i]); } }));
  return out;
}

/**
 * The set's lengths measured part by part and merged into `boq` by drawing_boq: the merged BOQ, or null when any call
 * failed twice (the caller queues the CAD worker or says the lengths are to be confirmed).
 */
// deno-lint-ignore no-explicit-any
export async function readLengths(call: LengthsCall, boq: Record<string, any>, per = LENGTHS_PAGES_PER_CALL, width = LENGTHS_PARALLEL): Promise<Record<string, any> | null> {
  const ask = async (b: Record<string, unknown>, ok: (j: any) => boolean) => {
    for (let k = 0; k < 2; k++) { try { const j: any = await call({ mode: 'lengths', ...b }); if (ok(j)) return j; } catch (_e) { /* asked again once */ } }
    return null;
  };
  const first = await ask({ from: 0, to: per }, (j) => partOk(j, 0, per));
  if (!first) return null;
  const n: number = first.pages;
  const ranges: [number, number][] = [];
  for (let f = per; f < n; f += per) ranges.push([f, Math.min(n, f + per)]);
  const rest = await pool(ranges, width, ([f, t]) => ask({ from: f, to: t }, (j) => partOk(j, f, t) && j.pages === n));
  if (rest.some((x) => !x)) return null;
  const parts = [first, ...rest].map(({ pages, from, sheets }) => ({ pages, from, sheets }));
  const merged = await ask({ boq, parts }, (j) => !!j && j.ok === true && !!j.boq && Array.isArray(j.boq.boq));
  return merged ? merged.boq : null;
}
