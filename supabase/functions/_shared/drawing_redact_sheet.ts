// drawing_redact_sheet — ONE SHEET'S REDACTION, THE SAME CODE ON THE EDGE AND IN THE CAD WORKER (18 Nov 2026, sales_engineer;
// founder ledger 580: the drawing reaches the suppliers, redacted).
//
// MEASURED, production 18 Nov 10:10 UTC: the 8-sheet set's sheets the request could not verify were queued (why
// 'pages_need_time', _shared/drawing_pages_queued.ts) and scripts/cad_read_worker.ts, which has no CPU cap, sent each one
// BACK to the edge's drawing_redact, which has (about 2 s an isolate). They died the same way: "sheet 1 not checked yet
// (pages_need_time_pixels_unverified)" and "(pages_need_time_lost)", and no page reached a supplier.
//
// So the manual path's per-sheet core lives here, and both call it:
//   drawing_redact/index.ts   its pixel work in workers of its own (modes 'paint', 'repaint', 'tile', 'tiles': HTTP to
//                             itself, each inside the edge's CPU cap), its storage and its run row through supabase-js;
//   scripts/cad_read_worker.ts the pixel work IN PROCESS (inProcessWorkers below: the very functions those modes run, on the
//                             very inputs those modes receive after their JSON), storage and the run row over REST with the
//                             service key, and the model through the SAME ai_gateway call (askPixelsVia below: fn
//                             'drawing_redact_verify', the same counterpart, the same timeout, so ai_cost_log, the
//                             rehearsal cap and the hold see the same call).
// The steps, their order, the thresholds, the verdicts, the upload path and the answer's shape are this file's, once. A sheet
// therefore never depends on the edge's CPU cap again, and redactQueuedPages / sheetVerdict read the same answer either way
// (drawing_redact/a_queued_sheet_is_checked_in_the_worker_as_on_the_edge.check.ts proves it on sheet 1 of the set).
import { pdfPages, type PdfPage } from './pdf_text_positions.ts';
import { readerAgrees } from './pdf_vector_redact.ts';
import { MAX_BOXES, SERVER_MARGIN, b64ToBytes, bytesToB64, cleanBoxes, paintedJpeg, repaintJpeg, serverBoxPlan, stripB64, supplierPagePrefix, tileJpeg, tilesJpeg, type Box, type PaintGroup } from './drawing_redact_page.ts';
import { PIXEL_BUDGET_MESSAGE, PIXEL_CALL_USD, PIXEL_VERIFY_SYS, VIEWS_PER_CROP, jpegSize, pageSizeFromMediaBox, pageSizeFromPixels, pixelGate, planTiles, type PageSize, type PixelBudget, type PixelOutcome, type Tile } from './drawing_pixel_gate.ts';
import { padded, unreadTextHold, vocabularyVet, type Vet } from './drawing_code_floor.ts';
import { TIME_HELD, callTimeoutMs, deadlinesFrom, type Deadlines } from './drawing_deadline.ts';

/** The margin mode 'repaint' (verify:false) paints the checker's boxes at, and the unread-text rule pads them by. */
export const REPAINT_MARGIN = 0.01;
/** The paint worker's ceiling on groups (each at most MAX_BOXES): 64 x 1,200 boxes is past any page measured. */
export const MAX_PAINT_GROUPS = 64;

// ── WHAT A PIXEL WORKER RECEIVES ─────────────────────────────────────────────────────────────────────────────────────────
// The edge sends these over JSON to a worker of its own and the worker normalises them; in process the same two steps run
// back to back, so the pixels painted or cut are the same either way.
/** A page's paint as it is sent: a group longer than MAX_BOXES split in order at the same margin (no box dropped), each
 *  value clamped to 0..1 (a model's 1e999 is the page edge, not a null the worker reads as 0). */
export function paintGroupsToSend(groups: PaintGroup[]): PaintGroup[] {
  const c = (v: number) => Math.max(0, Math.min(1, Number.isNaN(v) ? 0 : v));
  return groups.flatMap((g) => { const bs = g.boxes.map((b) => ({ x: c(b.x), y: c(b.y), w: c(b.w), h: c(b.h) })); const out: PaintGroup[] = []; for (let k = 0; k < bs.length; k += MAX_BOXES) out.push({ boxes: bs.slice(k, k + MAX_BOXES), pad: g.pad }); return out; });
}
/** A paint as the worker takes it, or null: never paint fewer boxes than were sent (fail closed), so a group over MAX_BOXES or
 *  too many groups is refused and the caller holds the page. A margin is at most 0.1 of the page (boxes only add black). */
// deno-lint-ignore no-explicit-any
export function paintGroupsReceived(groups: any[]): PaintGroup[] | null {
  if (groups.length > MAX_PAINT_GROUPS || groups.some((g) => !Array.isArray(g?.boxes) || g.boxes.length > MAX_BOXES)) return null;
  return groups.map((g) => ({ boxes: cleanBoxes(g?.boxes) ?? [], pad: Math.max(0, Math.min(0.1, Number(g?.pad) || 0)) }));
}
/** A view's tile as a crop worker takes it: each fraction clamped to 0..1 (a zero width or height is the whole page), each
 *  output edge to 1..2000 px. */
// deno-lint-ignore no-explicit-any
export function tileReceived(t: any): Tile {
  const n = (v: unknown) => Math.max(0, Math.min(1, Number(v) || 0)), px = (v: unknown) => Math.min(2000, Math.max(1, Number(v) || 0));
  return { x: n(t.x), y: n(t.y), w: n(t.w) || 1, h: n(t.h) || 1, outW: px(t.outW), outH: px(t.outH) };
}
/** The reading mark a view must carry (drawing_pixel_gate.newMark): a view without one could only be an unread answer. */
export const markOk = (m: unknown) => /^\d{6}$/.test(String(m ?? ''));

// ── THE MODEL, THROUGH THE GATEWAY ───────────────────────────────────────────────────────────────────────────────────────
/** One view to the pixel checker through ai_gateway (drawing_pixel_gate's PixelAsk). Cut at the stop plus a grace (round 5;
 *  drawing_deadline.callTimeoutMs), and the gateway is told how long we wait. `signal` (the CAD worker's job budget) cuts it
 *  sooner, and `headers` carries its sandbox run tag and the proof (cad_read_worker.sheetRedactorHere; on the edge observe()
 *  adds them to every call back to the project). null: no usable answer (refused, truncated, not JSON, cut), and the gate
 *  holds the page. */
export async function askPixelsVia(gw: string, key: string, authors: string, jpgB64: string, stopAt?: number, sys: string = PIXEL_VERIFY_SYS, signal?: AbortSignal, headers: Record<string, string> = {}): Promise<string | null> {
  try {
    const ms = callTimeoutMs(stopAt, 55_000);
    const cut = signal ? AbortSignal.any([signal, AbortSignal.timeout(ms)]) : AbortSignal.timeout(ms);
    const r = await fetch(gw, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, signal: cut,
      body: JSON.stringify({ __secret: key, fn: 'drawing_redact_verify', counterpart_model: authors, client_timeout_ms: ms, response_format: { type: 'json_object' }, temperature: 0, sys,
        input: [{ role: 'user', content: [{ type: 'text', text: 'Check this page as the supplier will see it. Return the JSON.' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,' + jpgB64 } }] }] }) });
    const jd = await r.json().catch(() => null);
    if (!r.ok || !jd || jd.truncated === true || jd.finish_reason === 'length' || typeof jd.content !== 'string') return null;
    return jd.content;
  } catch (_e) { return null; }
}

// ── THE GATE FOR ONE PAGE ────────────────────────────────────────────────────────────────────────────────────────────────
/** Where a page's pixel work and its model calls are done: the edge's workers of its own, or this process (inProcessWorkers). */
export type GateWorkers = {
  ask: (key: string, authors: string, jpgB64: string, stopAt?: number, sys?: string) => Promise<string | null>;
  repaint: (jpgB64: string, regions: Box[], stopAt?: number) => Promise<string>;
  crop: (jpgB64: string, tile: Tile, mark: string, stopAt?: number) => Promise<string>;
  cropMany: (jpgB64: string, views: { tile: Tile; mark: string }[], stopAt?: number) => Promise<string[]>;
};
/** The page's physical size turned to the image's orientation (a MediaBox is unrotated; the image is as displayed). */
export function oriented(size: PageSize, jpgB64: string): PageSize {
  const px = jpegSize(b64ToBytes(jpgB64));
  if (!px) return size;
  return (px.w >= px.h) === (size.wMm >= size.hMm) ? size : { ...size, wMm: size.hMm, hMm: size.wMm };
}
/** The size a page with no better measure is checked at: the larger of A1 and what its pixels imply. */
export function sizeOfPixels(jpgB64: string): PageSize { const px = jpegSize(b64ToBytes(jpgB64)); return pageSizeFromPixels(px?.w ?? 2600, px?.h ?? 1838); }
/** One page through the gate, TILED to its physical size; the answer carries the calls and USD it spent. */
export async function gatePageWith(w: GateWorkers, key: string | undefined, held: boolean, authors: string, jpgB64: string, budget: PixelBudget, size?: PageSize, stopAt?: number, vet?: Vet, sys: string = PIXEL_VERIFY_SYS): Promise<PixelOutcome> {
  if (held || !key) return { ok: false, held: 'pixels_unverified', calls: 0, usd: 0, detail: { reason: held ? 'model_hold' : 'no_ai_key' } };
  const plan = planTiles(oriented(size ?? sizeOfPixels(jpgB64), jpgB64));
  // stopAt (drawing_deadline.ts): past it no view is asked and the page is held for time.
  return await pixelGate(jpgB64, (b) => w.ask(key, authors, b, stopAt, sys), (b, regions) => w.repaint(b, regions, stopAt), budget, { plan, crop: (b, t, m) => w.crop(b, t, m, stopAt), cropMany: (b, vs) => w.cropMany(b, vs, stopAt), stopAt, vet });
}

/** What one run recorded in drawing_redaction_runs.verify_detail spent (USD): pixel_usd, or pixel_calls at PIXEL_CALL_USD for
 *  a run recorded before tiling, plus strings_usd. The set's budget sums it over a source file's last 24 h. */
// deno-lint-ignore no-explicit-any
export function runSpentUsd(row: any): number { const d = row?.verify_detail || {}; return (Number(d.pixel_usd) || (Number(d.pixel_calls) || 0) * PIXEL_CALL_USD) + (Number(d.strings_usd) || 0); }

/** Checker boxes left unpainted because they cover drawing vocabulary only (drawing_code_floor.vocabularyVet): logged and
 *  recorded on the run, so an over-eager checker is visible rather than silent. */
export function ignoredSaid(g: PixelOutcome): Record<string, unknown> {
  if (!g.ok || !g.detail.ignored) return {};
  console.log(`drawing_redact: ${g.detail.ignored} checker box(es) over drawing vocabulary only were not painted: ${JSON.stringify(g.detail.ignored_what ?? [])}`);
  return { checker_boxes_ignored: g.detail.ignored, checker_ignored_what: g.detail.ignored_what ?? [] };
}
/** What the customer is told when the set is past its budget (plain words), or nothing. */
export const budgetSaid = (held: string | undefined) => held === 'pixels_budget' ? { customer_message: PIXEL_BUDGET_MESSAGE } : {};

// ── THE RUN'S ROW ────────────────────────────────────────────────────────────────────────────────────────────────────────
export type RunOutcome = { status: string; paths: string[]; pages_in: number; pages_out: number; skipped: number; pages_verified?: number; verify_failed?: number; verify_detail?: unknown };
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** The drawing_redaction_runs row a run records (drawing_redact recordRun; create_inquiry resolves what may be attached from
 *  that table alone, so the worker writes exactly this row too). */
// deno-lint-ignore no-explicit-any
export function redactionRunRow(id: string, body: any, o: RunOutcome): Record<string, unknown> {
  const custId = typeof body?.owner_customer_id === 'string' && UUID_RE.test(body.owner_customer_id) ? body.owner_customer_id : null;
  return {
    id,
    customer_id: custId,
    owner_email: body?.owner_email ? String(body.owner_email).toLowerCase().slice(0, 320) : null,
    caller_ref: body?.prefix ? String(body.prefix).slice(0, 400) : null,
    source_path: body?.source_path ? String(body.source_path).slice(0, 400) : null,
    output_paths: o.paths,
    pages_in: o.pages_in,
    pages_out: o.pages_out,
    skipped: o.skipped,
    status: o.status,
    pages_verified: o.pages_verified ?? 0,
    verify_failed: o.verify_failed ?? 0,
    verify_detail: o.verify_detail ?? null,
  };
}

// ── THE MANUAL PATH: one call's sheets, the server's (or the customer's) boxes, the pixel gate, the upload, the run ─────────
export type SheetDeps = GateWorkers & {
  /** Paint the groups onto the raster (one decode, one encode); throws Error('decode_failed') or Error('paint_failed'). */
  paint: (rasterB64: string, groups: PaintGroup[], stopAt?: number) => Promise<string>;
  modelHeld: () => Promise<boolean>;
  aiKey: () => Promise<string | undefined>;
  /** The set's budget less what the caller's other pages in flight spent (drawing_redact budgetInFlight). */
  budget: (sourcePath: unknown, spentUsd: unknown) => Promise<PixelBudget>;
  /** Store one redacted page in drawing-files (upsert): true when stored. */
  upload: (path: string, jpg: Uint8Array) => Promise<boolean>;
  /** Record the run (and remove its uploads when the record fails): true when recorded. */
  // deno-lint-ignore no-explicit-any
  publish: (id: string, body: any, o: RunOutcome) => Promise<boolean>;
};

/**
 * drawing_redact's manual path (body.manual_boxes set): the answer it returns, for every caller. `jobId` names the run;
 * `clock` is the request's (drawing_deadline.deadlinesFrom). A (13 Nov 2026): every page passes the pixel gate before it is
 * shared; review item 4: the reader must agree with pdf-lib on what the page draws, or its boxes are not trusted.
 */
// deno-lint-ignore no-explicit-any
export async function manualSheets(body: any, run: { jobId: string; clock: Deadlines }, d: SheetDeps): Promise<Record<string, unknown>> {
  const job_id = run.jobId, clock = run.clock;
  const prefix = supplierPagePrefix(body.prefix);
  // deno-lint-ignore no-explicit-any
  const imgs: any[] = Array.isArray(body.images) ? body.images.slice(0, 8) : [];
  if (!imgs.length) { const recorded = await d.publish(job_id, body, { status: 'empty', paths: [], pages_in: 0, pages_out: 0, skipped: 0 }); return { ok: true, job_id, recorded, paths: [], pages_in: 0, pages_out: 0 }; }
  // Text layer of the source PDF, if the caller sent it; page_offset maps this call's images onto PDF pages. Only THIS
  // call's pages are interpreted (22 Sep 2026: parsing the whole set on every call put each call past the edge CPU cap).
  const pageOffset = Math.max(0, Number(body.page_offset) || 0);
  let pdf: PdfPage[] = [];
  if (body.original_b64 && typeof body.original_b64 === 'string') {
    try { pdf = await pdfPages(b64ToBytes(body.original_b64), [pageOffset, pageOffset + imgs.length], { layers: false }); } catch (_e) { pdf = []; }
  }
  // deno-lint-ignore no-explicit-any
  const paths: string[] = []; let skipped = 0; let textHits = 0; const detail: any[] = [];
  const heldM = await d.modelHeld(); const keyM = heldM ? undefined : await d.aiKey();
  // spent_usd: what the caller's other pages in flight may spend (customer_api runs pages side by side, 17 Nov 2026).
  const budget = await d.budget(body.source_path, body.spent_usd);
  const agrees = body.original_b64 ? await readerAgrees(b64ToBytes(body.original_b64), [pageOffset, pageOffset + imgs.length]) : false;
  let pixelCalls = 0, pixelUsd = 0;
  const timePages: number[] = [];
  for (let i = 0; i < imgs.length; i++) {
    if (Date.now() >= clock.startBy) { skipped++; timePages.push(i); detail.push({ page: i, skipped: TIME_HELD }); continue; }
    if (!agrees) { skipped++; detail.push({ page: i, skipped: 'reader_disagrees_with_pdf' }); continue; }
    // FAIL CLOSED (founder, 14 Sep 2026: nothing that identifies the customer may reach a supplier). A page the server cannot
    // read (a scan, a photo) is HELD whatever boxes came with it (serverBoxPlan); a readable one is painted with the boxes
    // plus the text layer's own identity boxes and re-encoded from pixels (d.paint: one decode, one encode).
    try {
      const b = (imgs[i] && (imgs[i].b64 || imgs[i].data)) || imgs[i];
      const r = serverBoxPlan(pdf, pageOffset + i, cleanBoxes(body.manual_boxes[i]));
      if (!r.ok) { skipped++; detail.push({ page: i, skipped: r.skipped }); continue; }
      let boxed: string;
      try { boxed = await d.paint(stripB64(String(b)), [{ boxes: r.boxes, pad: SERVER_MARGIN }], clock.stopAt); }
      catch (e) { skipped++; detail.push({ page: i, skipped: (e as Error)?.message === 'decode_failed' ? 'decode_failed' : 'paint_failed' }); continue; }
      textHits += Number(r.detail.text_layer_boxes) || 0;
      const pp = pdf[pageOffset + i];
      const g = await gatePageWith(d, keyM, heldM, 'deterministic', boxed, budget, pp && pp.width > 0 ? pageSizeFromMediaBox(pp.width, pp.height) : undefined, clock.stopAt, vocabularyVet(pp, []));
      pixelCalls += g.calls; pixelUsd += g.usd;
      if (!g.ok) { skipped++; if (g.held === TIME_HELD) timePages.push(i); detail.push({ page: i, skipped: g.held, ...g.detail }); continue; }
      // The same rule as the model path (drawing_code_floor.unreadTextHold, round 4): every area of text code cannot read
      // must lie under a painted box - the boxes that came with the page, the text layer's, or the checker's - or HELD.
      const unreadHeld = unreadTextHold(pp, [], [...(r.painted ?? []), ...g.boxes.map((b) => padded(b, REPAINT_MARGIN))]);
      if (unreadHeld) { skipped++; detail.push({ page: i, skipped: unreadHeld }); continue; }
      const path = `${prefix}_p${i}.jpg`;
      if (!(await d.upload(path, b64ToBytes(g.jpgB64)))) { skipped++; detail.push({ page: i, skipped: 'upload_failed' }); continue; }
      paths.push(path); detail.push({ page: i, ...r.detail, ...ignoredSaid(g) });
    } catch (_e) { skipped++; detail.push({ page: i, skipped: 'decode_failed' }); }
  }
  const status = paths.length === 0 ? 'failed' : (paths.length < imgs.length ? 'partial' : 'complete');
  const recorded = await d.publish(job_id, body, { status, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: paths.length, verify_failed: 0, verify_detail: { method: 'manual', pages: detail, pixel_calls: pixelCalls, pixel_usd: pixelUsd } });
  // deno-lint-ignore no-explicit-any
  return { ok: true, job_id, recorded, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: 0, verify_failed: 0, verify_detail: detail, status, method: 'manual', text_layer_hits: textHits, time_held: timePages.length, time_held_pages: timePages, redaction_complete: recorded && paths.length === imgs.length, ...budgetSaid(detail.some((x: any) => x.skipped === 'pixels_budget') ? 'pixels_budget' : undefined) };
}

/** One call of the manual path with the request's own clock, as drawing_redact runs it: what it throws is the edge's
 *  {ok:false,error} answer, so sheetVerdict reads it the same way (no pages_in: lost, asked again). */
// deno-lint-ignore no-explicit-any
export async function manualSheetsCall(body: any, d: SheetDeps, startedAt: number = Date.now()): Promise<Record<string, unknown>> {
  try { return await manualSheets(body, { jobId: crypto.randomUUID(), clock: deadlinesFrom(body, startedAt) }, d); }
  catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// ── THE PIXEL WORK IN THIS PROCESS (the CAD worker: no CPU cap) ──────────────────────────────────────────────────────────
// Each is what drawing_redact's mode of the same name does with what it receives (the normalisers above), minus the HTTP;
// a refusal there (a 400) is a throw here, which the gate and the manual path already read as no paint / no view.
export const inProcessWorkers: Pick<SheetDeps, 'paint' | 'repaint' | 'crop' | 'cropMany'> = {
  async paint(rasterB64, groups) {
    const g = rasterB64 ? paintGroupsReceived(paintGroupsToSend(groups)) : null;
    if (!g) throw new Error('paint_failed');
    let out: Awaited<ReturnType<typeof paintedJpeg>>;
    try { out = await paintedJpeg(b64ToBytes(rasterB64), g); } catch (_e) { throw new Error('decode_failed'); }
    return bytesToB64(out.jpg);
  },
  async repaint(jpgB64, regions) {
    const r = cleanBoxes(regions) ?? [];
    if (!jpgB64 || !r.length) throw new Error('repaint_failed');
    return bytesToB64(await repaintJpeg(b64ToBytes(jpgB64), r, REPAINT_MARGIN));
  },
  async crop(jpgB64, tile, mark) {
    if (!jpgB64 || !tile || !markOk(mark)) throw new Error('tile_failed');
    return bytesToB64(await tileJpeg(b64ToBytes(jpgB64), tileReceived(tile), 85, String(mark)));
  },
  async cropMany(jpgB64, views) {
    if (!jpgB64 || !views.length || views.length > VIEWS_PER_CROP || views.some((v) => !v?.tile || !markOk(v?.mark))) throw new Error('tiles_failed');
    return (await tilesJpeg(b64ToBytes(jpgB64), views.map((v) => ({ tile: tileReceived(v.tile), mark: String(v.mark) })), 85)).map(bytesToB64);
  },
};
