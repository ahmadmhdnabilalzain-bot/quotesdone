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
// What this does NOT do: a request the customer sends before the job is done goes out with the drawing held, and no
// supplier is told later that it arrived (that needs the request to take pages after it was sent).
import type { Box } from './drawing_redact_page.ts';

export const PAGES_NEED_TIME = 'pages_need_time' as const;

/** One sheet already verified on the edge: its page number, the paths it was published at and the run that recorded them. */
export type DonePage = { page: number; paths: string[]; job: string };
/** One sheet left: its page number, its stored raster and the server's boxes for it. */
export type LeftPage = { page: number; path: string; boxes: Box[] };
export type QueuedPages = { pages_in: number; seed_terms: string[]; done: DonePage[]; left: LeftPage[] };

/** What one sheet's drawing_redact manual-path call carries (the caller adds its credential, owner and source path). */
export type SheetBody = { images: { mime: string; data: string }[]; page_offset: number; manual_boxes: Box[][]; seed_terms: string[]; original_b64: string; prefix: string };

/** The queue's input, or null when the set may not be finished off the request: a sheet was refused or lost (not time), a
 *  sheet left has no server boxes, or nothing is left. */
export function queuedPagesOf(o: { pagesIn: number; seeds: string[]; done: DonePage[]; left: number[]; boxes: Box[][] | null; storedAt: (page: number) => string | null }): QueuedPages | null {
  if (!o.left.length || !o.boxes) return null;
  if (o.done.length + o.left.length !== o.pagesIn) return null;
  const left: LeftPage[] = [];
  for (const page of [...o.left].sort((a, b) => a - b)) {
    const path = o.storedAt(page), boxes = o.boxes[page];
    if (!path || !Array.isArray(boxes)) return null;
    left.push({ page, path, boxes });
  }
  return { pages_in: o.pagesIn, seed_terms: o.seeds, done: [...o.done].sort((a, b) => a.page - b.page), left };
}

/**
 * Every sheet left through `redact` (drawing_redact's manual path, one sheet a call, in page order). The result is what
 * cad_read_status hands the portal: every page of the set in page order when each sheet left came back verified and
 * recorded, else held with the first reason. `raster(path)` is the stored sheet as base64; a throw is a held sheet.
 */
export async function redactQueuedPages(q: QueuedPages, deps: { originalB64: string; raster: (path: string) => Promise<string>; redact: (body: SheetBody) => Promise<any> }): Promise<Record<string, unknown>> {
  const got: DonePage[] = [];
  for (const s of q.left) {
    let rj: any = null;
    try {
      const data = await deps.raster(s.path);
      rj = await deps.redact({ images: [{ mime: 'image/jpeg', data }], page_offset: s.page, manual_boxes: [s.boxes], seed_terms: q.seed_terms, original_b64: deps.originalB64, prefix: 'redacted' });
    } catch (e) { return held(s.page, 'sheet_not_sent: ' + String((e as Error)?.message || e).slice(0, 120)); }
    const ok = rj?.ok === true && rj?.recorded === true && Number(rj?.pages_out) === 1 && Array.isArray(rj?.paths) && rj.paths.length === 1 && typeof rj?.job_id === 'string';
    if (!ok) return held(s.page, String(rj?.verify_detail?.[0]?.skipped || rj?.error || 'not_verified'));
    got.push({ page: s.page, paths: rj.paths.map(String), job: rj.job_id });
  }
  const all = [...q.done, ...got].sort((a, b) => a.page - b.page);
  if (all.length !== q.pages_in) return held(-1, 'pages_missing');
  return { redaction_complete: true, drawing_redacted_paths: all.flatMap((d) => d.paths), redaction_job_id: all[0]?.job ?? null, redaction_job_ids: all.map((d) => d.job), pages_checked_off_request: got.length };

  function held(page: number, why: string) {
    return { redaction_complete: false, held_reason: 'pages_need_time_' + why.replace(/[^a-z0-9_:. -]/gi, '').slice(0, 120), held_page: page };
  }
}
