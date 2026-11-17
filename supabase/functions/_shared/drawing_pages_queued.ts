// drawing_pages_queued — THE SHEETS OF A SET NOT CHECKED IN TIME ARE CHECKED OFF THE REQUEST, NEVER RELEASED UNCHECKED
// (17 Nov 2026, sales_engineer; paid proof 623d9200, founder ledger 580).
//
// analyze_drawing starts no sheet after 100 s (drawing_deadline.ts). With views cut a few to a worker and four sheets side by
// side, the local timing model (drawing_redact/every_page_is_verified_in_time.test.ts) checks 8 sheets in about 60 s and 19
// of 20 in about 119 s; a sheet never begun, or abandoned at the stop, used to hold the WHOLE drawing for good, with the
// customer told to upload it again a few sheets at a time. Now, when every other sheet of a PDF set was verified, the sheets
// left are queued in public.cad_read_jobs (why 'pages_need_time') with what the edge already proved about each: its raster
// as the portal drew it (stored privately, like a scan page), the server's own boxes for it (from the plan read, never the
// customer's) and the set's seeds. The CAD read routine (scripts/cad_read_worker.ts) sends each through the SAME
// drawing_redact manual path, one sheet a call with the whole edge clock to itself, and publishes the set only when every
// sheet came back verified: all of the set or none, as on the edge (customer_api/drawing_hold.ts). The portal adopts the
// pages from cad_read_status the way it adopts a scan's.
//
// EVERY SHEET NOT VERIFIED IN THE REQUEST, NOT ONLY ONE HELD FOR TIME (17 Nov 2026 evening, sales_engineer; paid proof
// 6244a525, founder ledger 580). MEASURED (Supabase function logs 19:12-19:16 UTC): of 8 sheets, 7 were LOST to HTTP 546
// "CPU Time exceeded" and 1 came back unverified; only sheets held for TIME were queued, so cad_read_jobs got 0 rows and the
// supplier received "7 lines, 0 pages", no drawing, no notice. Now every sheet the request did not verify is sorted by what
// drawing_redact said about it (sheetVerdict): LOST (a 546, a 5xx, a timeout, no answer), held for TIME, or a transient
// hold (a view the checker did not answer, a paint worker that died, an upload) is queued and RETRIED off the request; a
// sheet the checker REFUSED (identity it found and could not cover, text it could not read, the set's budget, a reader that
// disagrees with the PDF) is a real finding: the set is held and nothing is retried blindly. The worker retries a sheet at
// most SHEET_TRIES times a run, keeps each verified sheet on the job as it goes (never paid for twice), and hands a sheet
// still not checked back to the queue for the next run (three runs at most, then the sales_engineer's finding).
// What happens when the set is published (the requests already sent, their suppliers, the customer): ./drawing_pages_follow.ts.
import type { Box } from './drawing_redact_page.ts';

export const PAGES_NEED_TIME = 'pages_need_time' as const;

/** One sheet already verified on the edge: its page number, the paths it was published at and the run that recorded them. */
export type DonePage = { page: number; paths: string[]; job: string };
/** One sheet left: its page number, its stored raster, the server's boxes for it, and why the request left it (sheetVerdict). */
export type LeftPage = { page: number; path: string; boxes: Box[]; why?: string };
export type QueuedPages = { pages_in: number; seed_terms: string[]; done: DonePage[]; left: LeftPage[] };

/** What one sheet's drawing_redact manual-path call carries (the caller adds its credential, owner and source path). */
export type SheetBody = { images: { mime: string; data: string }[]; page_offset: number; manual_boxes: Box[][]; seed_terms: string[]; original_b64: string; prefix: string };

// ── WHAT drawing_redact SAID ABOUT ONE SHEET ─────────────────────────────────────────────────────────────────────────────
/** The checker found what identifies the customer and could not cover it, or text it could not read lies uncovered: a real
 *  leak finding. Never retried blindly (a retry of the same sheet with the same boxes meets the same finding). */
export const REFUSED_FOR_IDENTITY: readonly string[] = ['pixels_not_clean', 'identity_found_no_regions', 'unread_text_unclaimed'];
/** Holds that say nothing about the sheet itself: the worker died or was cut, the checker did not answer a view, the clock
 *  ran out, a store failed. The same sheet asked again, with the whole edge clock to itself, can pass. */
export const RETRIED: readonly string[] = ['lost', 'time', 'unrecorded', 'pixels_unverified', 'paint_failed', 'decode_failed', 'upload_failed', 'exception', 'sheet_not_sent'];
export type SheetVerdict =
  | { state: 'verified'; paths: string[]; job: string }
  | { state: 'retry'; why: string }
  | { state: 'refused'; why: string; identity: boolean };

/** One sheet's drawing_redact answer (one page a call), sorted. `rj` null = no answer at all (a throw, a timeout, no JSON).
 *  A reason this does not know is REFUSED (fail closed: held and said, not retried). */
// deno-lint-ignore no-explicit-any
export function sheetVerdict(rj: any): SheetVerdict {
  // A 546 answers JSON too ({ code: 'WORKER_RESOURCE_LIMIT' }, no pages_in): an isolate death, the sheet LOST, not refused.
  if (!rj || typeof rj !== 'object' || (rj.ok !== true && !(Number(rj.pages_in) > 0))) return { state: 'retry', why: 'lost' };
  if (rj.ok === true && rj.recorded === true && Number(rj.pages_out) === 1 && Array.isArray(rj.paths) && rj.paths.length === 1 && typeof rj.job_id === 'string' && rj.job_id) {
    return { state: 'verified', paths: rj.paths.map(String), job: String(rj.job_id) };
  }
  const d = Array.isArray(rj.verify_detail) ? rj.verify_detail[0] : null;
  // A HOLD AFTER THE CHECKER SAW SOMETHING IS NOT TRANSIENT (review 17 Nov 2026). The gate returns 'pixels_unverified' or
  // 'time' for a round in which one view went unanswered BEFORE it judges the views that did answer, so a sheet whose checker
  // had already named identity (boxes painted, or a view still dirty) came back looking transient; asked again from the
  // unpainted raster, the same checker saying "clean" once by chance would publish it. Held as the leak finding it is.
  if (d && (Number(d.boxes_added) > 0 || Number(d.dirty) > 0)) return { state: 'refused', why: 'checker_found_then_' + String(d.skipped || 'held'), identity: true };
  if (Number(rj.time_held) > 0) return { state: 'retry', why: 'time' };
  if (rj.ok === true && rj.recorded !== true && Number(rj.pages_out) === 1) return { state: 'retry', why: 'unrecorded' };
  const why = String(d?.skipped || (Array.isArray(d?.found) && d.found.length ? 'pixels_not_clean' : '') || rj.held_reason || (rj.customer_message ? 'pixels_budget' : '') || rj.error || 'not_verified');
  if (REFUSED_FOR_IDENTITY.includes(why)) return { state: 'refused', why, identity: true };
  if (RETRIED.includes(why)) return { state: 'retry', why };
  return { state: 'refused', why, identity: false };
}

/** The request's sheets, sorted (analyze_drawing, one verdict a sheet in page order; a sheet with no verdict was never answered
 *  and is LOST): `left` is what goes to the queue, `refused` holds the set (and then nothing is queued: `left` is empty). */
export function sheetsToCheckOff(verdicts: (SheetVerdict | undefined)[], pages: number): { verified: number[]; left: { page: number; why: string }[]; refused: { page: number; why: string; identity: boolean }[] } {
  const verified: number[] = [], left: { page: number; why: string }[] = [], refused: { page: number; why: string; identity: boolean }[] = [];
  for (let page = 0; page < pages; page++) {
    const v = verdicts[page] ?? { state: 'retry' as const, why: 'lost' };
    if (v.state === 'verified') verified.push(page);
    else if (v.state === 'refused') refused.push({ page, why: v.why, identity: v.identity });
    else left.push({ page, why: v.why });
  }
  return { verified, left: refused.length ? [] : left, refused };
}

/** The queue's input, or null when the set may not be finished off the request: a sheet left has no server boxes or was
 *  not stored, the count does not add up, or nothing is left. A REFUSED sheet is never in `left` (the caller holds the set). */
export function queuedPagesOf(o: { pagesIn: number; seeds: string[]; done: DonePage[]; left: number[]; boxes: Box[][] | null; storedAt: (page: number) => string | null; why?: (page: number) => string | undefined }): QueuedPages | null {
  if (!o.left.length || !o.boxes) return null;
  if (new Set(o.left).size !== o.left.length) return null;
  if (o.done.length + o.left.length !== o.pagesIn) return null;
  const left: LeftPage[] = [];
  for (const page of [...o.left].sort((a, b) => a - b)) {
    const path = o.storedAt(page), boxes = o.boxes[page], why = o.why?.(page);
    if (!path || !Array.isArray(boxes)) return null;
    left.push({ page, path, boxes, ...(why ? { why } : {}) });
  }
  return { pages_in: o.pagesIn, seed_terms: o.seeds, done: [...o.done].sort((a, b) => a.page - b.page), left };
}

/** How often one sheet is asked in one worker run before it goes back to the queue, and the wait between askings (a fresh
 *  isolate, not the one that just died). */
export const SHEET_TRIES = 3;
export const SHEET_RETRY_WAIT_MS = 5_000;

/**
 * Every sheet left through `redact` (drawing_redact's manual path, one sheet a call, in page order). The result is what
 * cad_read_status hands the portal: every page of the set in page order when each sheet left came back verified and
 * recorded; held with the reason when a sheet was REFUSED (held_identity: the checker's leak finding); or `retry_later`
 * when a sheet was still lost or held after SHEET_TRIES askings, so the worker puts the job back in the queue.
 * `raster(path)` is the stored sheet as base64 (a throw is a sheet not sent, asked again). `progress(q)` is told the queue
 * after each verified sheet (that sheet moved from left to done), so a later run never asks a verified sheet again.
 */
export async function redactQueuedPages(q: QueuedPages, deps: { originalB64: string; raster: (path: string) => Promise<string>; redact: (body: SheetBody) => Promise<any>; progress?: (q: QueuedPages) => Promise<void>; wait?: (ms: number) => Promise<void>; tries?: number; signal?: AbortSignal }): Promise<Record<string, unknown>> {
  // THE JOB'S BUDGET STOPS THE ASKING (review 17 Nov 2026): once `signal` is aborted no sheet is sent again (no paid call after
  // the budget); the job goes back to the queue with what it kept.
  const spent = () => deps.signal?.aborted === true;
  const tries = Math.max(1, deps.tries ?? SHEET_TRIES);
  const wait = deps.wait ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const done: DonePage[] = [...q.done];
  let left: LeftPage[] = [...q.left];
  for (const s of q.left) {
    let v: SheetVerdict = { state: 'retry', why: 'sheet_not_sent' };
    for (let k = 0; k < tries; k++) {
      if (spent()) return { ...held(s.page, 'job_budget'), retry_later: true };
      if (k) await wait(SHEET_RETRY_WAIT_MS * k);
      if (spent()) return { ...held(s.page, 'job_budget'), retry_later: true };
      try {
        const data = await deps.raster(s.path);
        v = sheetVerdict(await deps.redact({ images: [{ mime: 'image/jpeg', data }], page_offset: s.page, manual_boxes: [s.boxes], seed_terms: q.seed_terms, original_b64: deps.originalB64, prefix: 'redacted' }).catch(() => null));
      } catch (_e) { v = { state: 'retry', why: 'sheet_not_sent' }; }
      if (v.state !== 'retry') break;
    }
    if (v.state === 'refused') return { ...held(s.page, v.why), held_identity: v.identity };
    if (v.state === 'retry') return { ...held(s.page, v.why), retry_later: true };
    done.push({ page: s.page, paths: v.paths, job: v.job });
    left = left.filter((x) => x.page !== s.page);
    // A progress write that fails costs a sheet asked again on the next run, never a sheet published unverified.
    try { await deps.progress?.({ ...q, done: [...done].sort((a, b) => a.page - b.page), left }); } catch (_e) { /* asked again next run */ }
  }
  const all = done.sort((a, b) => a.page - b.page);
  if (all.length !== q.pages_in || new Set(all.map((d) => d.page)).size !== q.pages_in) return held(-1, 'pages_missing');
  return { redaction_complete: true, drawing_redacted_paths: all.flatMap((d) => d.paths), redaction_job_id: all[0]?.job ?? null, redaction_job_ids: all.map((d) => d.job), pages_checked_off_request: q.left.length };

  function held(page: number, why: string) {
    return { redaction_complete: false, held_reason: 'pages_need_time_' + why.replace(/[^a-z0-9_:. -]/gi, '').slice(0, 120), held_page: page };
  }
}
