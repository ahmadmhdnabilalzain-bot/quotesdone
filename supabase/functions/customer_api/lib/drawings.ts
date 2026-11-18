// customer_api — the customer's drawing: the browser OCR it arrives with, the CAD read queue, the
// redaction for suppliers, the stored original, and the server-side resolution of redacted pages.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { safeFilename, SAFE_UPLOAD, SAFE_CAD } from '../../_shared/attachment.ts';
import { heldRun } from '../drawing_hold.ts';
import { PAGES_NEED_TIME } from '../../_shared/drawing_pages_queued.ts';
import { pdfIdentityTerms } from '../../_shared/drawing_identity_gate.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A customer drawing is stored AND handed to a
// supplier to quote from, so a malicious file here would be forwarded by us, under our name.
import { sanitizeAndScan } from '../../_shared/malware.ts';
import { storedAt } from '../../_shared/stored_at.ts';
import { SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { PLAN_BUDGET_MS, planBodies } from '../../_shared/drawing_plan.ts';

// The keyword map (./keywords.ts, KW + detect()) is DELETED (23 Sep 2026, founder_instruction 886-903): a trade is
// reasoned among the real options (_shared/reasoned_trades.ts), never read off words.
// The portal's drawing OCR (ocrPlan lines with page boxes, the sheet width, the symbol counts),
// passed through to drawing_boq, which validates every field. Bounded here only by size.
export function drawingOcr(body: any): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (Array.isArray(body?.ocr_lines)) out.ocr_lines = body.ocr_lines.slice(0, 4000);
  if (Number.isFinite(Number(body?.ocr_width))) out.ocr_width = Number(body.ocr_width);
  if (body?.symbol_counts && typeof body.symbol_counts === 'object') out.symbol_counts = body.symbol_counts;
  return out;
}
// The portal's SCHEDULE READ (ocrClient.ocrSchedules, 21 Sep 2026, founder instruction 580): the ruled
// tables found on each page (_shared/table_grid.ts) with every cell OCR'd on its own, row/column
// structure kept. Untrusted browser output, so it is rebuilt here to the exact shape and caps the
// portal produces — 40 tables x 80 rows x 24 columns, 120 characters a cell, strings and numbers only —
// and anything else is dropped rather than passed on. Page numbers are bounded by MAX_DRAWING_PAGES.
export const MAX_DRAWING_PAGES = 20; // = src/components/me/pdfRaster.ts PDF_MAX_PAGES
export function scheduleTables(body: any): Record<string, unknown> {
  if (!Array.isArray(body?.schedule_tables)) return {};
  const num = (v: unknown, lo: number, hi: number) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : lo; };
  const out: unknown[] = [];
  for (const t of body.schedule_tables.slice(0, 40)) {
    if (!t || typeof t !== 'object' || !Array.isArray(t.rows)) continue;
    const page = Math.round(Number(t.page));
    if (!Number.isInteger(page) || page < 1 || page > MAX_DRAWING_PAGES) continue;
    const b = t.bbox || {};
    const rows = t.rows.slice(0, 80).filter(Array.isArray).map((r: unknown[]) => r.slice(0, 24).map((s) => (typeof s === 'string' ? s.slice(0, 120) : '')));
    if (!rows.length) continue;
    const conf = rows.map((r: string[], i: number) => r.map((_, j) => num(Array.isArray(t.conf) && Array.isArray(t.conf[i]) ? t.conf[i][j] : 0, 0, 100)));
    out.push({ page, bbox: { x: num(b.x, 0, 1), y: num(b.y, 0, 1), w: num(b.w, 0, 1), h: num(b.h, 0, 1) }, rows, conf });
  }
  return out.length ? { schedule_tables: out } : {};
}

// A CAD DRAWING THE EDGE CANNOT READ IS READ OFF THE REQUEST PATH (22 Sep 2026, sales_engineer; founder:
// "customer will share cad files or pdf mainly"). MEASURED on production that day: every DWG sent to
// drawing_boq died 546 "Memory limit exceeded" (fixed in doc_read/dwg.ts), and even fixed, a DWG's cost is
// not its size (a 562 KB drawing took 1.9 s of CPU against the 2 s cap). drawing_boq is a SEPARATE worker,
// so its death reaches this function as a 546 answer, not a silent kill. On that answer, or when dwg.ts
// says the drawing is past its edge ceiling, the stored original is queued in public.cad_read_jobs and the
// CAD worker (scripts/cad_read_worker.ts on a GitHub runner, dispatched by startCadWorker; no CPU cap) reads it;
// 'cad_read_status' hands the take-off to the customer's screen. Prevented from regressing by
// scripts/checks/a_cad_upload_reaches_the_cad_reader.test.mjs.
export function cadQueueReason(status: number, jd: any): 'over_edge_ceiling' | 'edge_worker_died' | 'edge_reader_failed' | null {
  if (jd?.ok) return jd.kind === 'dwg' && jd.needs === 'cad_conversion' ? 'over_edge_ceiling' : null;
  if (status === 546 || jd?.code === 'WORKER_RESOURCE_LIMIT') return 'edge_worker_died';
  // A refusal the reader gave for the file itself (not a DWG, damaged) would fail the same way off the
  // edge, so only a transport failure or a server error is worth a second reading.
  return status === 0 || status >= 500 ? 'edge_reader_failed' : null;
}
export async function queueCadRead(o: { customerId: string; email: string; path: string; name: string; mime: string; b64Len: number; why: string; boqIn?: unknown }): Promise<string | null> {
  const { data, error } = await admin.from('cad_read_jobs').insert({ customer_id: o.customerId, owner_email: o.email, source_path: o.path,
    file_name: o.name, mime: o.mime, bytes: Math.floor(o.b64Len * 3 / 4), why: o.why, boq_in: o.boqIn ?? null }).select('id').maybeSingle();
  if (error || !data?.id) { console.warn(`[cad] could not queue ${o.path}: ${error?.message || 'no id'}`); return null; }
  await startCadWorker(String(data.id), o.why);
  return String(data.id);
}
// A DRAWING'S SHEETS ARE QUEUED ONCE (17 Nov 2026 evening, sales_engineer; _shared/drawing_pages_queued.ts). One open
// 'pages_need_time' job per stored drawing: an open job of this customer for the same stored original is answered back instead
// of a second one, so the worker never checks (and pays for) a sheet twice. The database says the same (the partial unique
// index of scripts/sql/a_drawing_sheet_is_queued_once.sql refuses a second open job); a refused insert reads the job back.
export async function queuePagesOnce(o: { customerId: string; email: string; path: string; name: string; mime: string; b64Len: number; queued: unknown }): Promise<string | null> {
  const open = async () => {
    const { data } = await admin.from('cad_read_jobs').select('id').eq('customer_id', o.customerId).eq('source_path', o.path)
      .eq('why', PAGES_NEED_TIME).in('status', ['queued', 'running']).limit(1);
    return Array.isArray(data) && data[0]?.id ? String(data[0].id) : null;
  };
  const had = await open();
  if (had) return had;
  return (await queueCadRead({ customerId: o.customerId, email: o.email, path: o.path, name: o.name, mime: o.mime, b64Len: o.b64Len, why: PAGES_NEED_TIME, boqIn: { queued_pages: o.queued } })) ?? await open();
}

// THE QUEUE IS READ BY THE CAD READ ROUTINE, NOT BY GITHUB ACTIONS (it_engineer, 10 Nov 2026; channels audit R3).
// History: 3 Nov this dispatched .github/workflows/cad-read-worker.yml the moment a job was queued (Actions on, ledger 1410).
// Actions is OFF again (ledger 1564, budget spent), so every dispatch reached nothing: the channels audit's 2.1 MB DWG was
// still queued after 264 s, 6 dispatches each failing in 2 s. The worker now runs as the Claude routine the founder switched
// on that day ("QuotesDone — CAD read worker (every 2 h)", ledger: "Yes switch cad reader"): it runs scripts/cad_read_worker.ts,
// which claims every queued job itself (fn_cad_read_claim, SKIP LOCKED) with the same LibreDWG reader the edge uses. Chosen
// over the alternatives because it costs nothing extra (the subscription, no Actions minutes) and needs no new account or
// token: pg_cron cannot run it (no Deno, no LibreDWG), the edge cannot (2 s CPU), a Hugging Face Space would need a
// founder-held token and a Space kept awake. The price is the wait: a job is read at the routine's next run, at most
// CAD_READER_EVERY_MS + its run time. So nothing is dispatched here, nothing reaches api.github.com, and a job the routine has
// not taken by then raises the sales_engineer's held finding (cad_dispatch.ts). Prevented by cad_dispatch.test.ts and
// scripts/checks/a_cad_upload_reaches_the_cad_reader.test.mjs.
export const CAD_READER_ROUTINE = 'QuotesDone — CAD read worker (every 2 h)';
export async function startCadWorker(jobId: string, why: string): Promise<void> {
  console.log(`[cad] job ${jobId} (${why}) is queued for the ${CAD_READER_ROUTINE} routine; it is read at its next run`);
}
// THE HELD FINDING (27 Oct 2026, it_engineer; since 10 Nov 2026 it runs when a polled job was not taken by the CAD read
// routine within its interval and run time, cad_dispatch.ts). Written when this used to dispatch .github/workflows/cad-read-worker.yml
// and re-dispatch it while the customer's screen polled. GitHub Actions is off, so every dispatch reached nothing and a
// queued drawing waited for a runner that never came while the customer was told "a few minutes". The reader cannot run
// on the edge (2 s CPU cap; a scanned drawing is OCR'd for up to 30 minutes) nor in pg_cron (no Deno, no LibreDWG), so a
// queued job is HELD FOR THE SALES ENGINEER: one finding per hour (the worker reads every queued job in one run, and a
// run of scans must not flood the queue), raised the moment a job is queued, naming the latest job and why. The sales_engineer reads it with scripts/cad_read_worker.ts (fn_cad_read_claim still takes it), and the
// customer's screen says an engineer is reading it (cad_read_status answers held_for). Never silent: a finding that
// cannot be written is logged as an error, and the job stays queued for the worker either way.
export async function cadReadHeld(jobId: string, why: string): Promise<void> {
  try {
    const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: 'sales_engineer:cad_read_held:' + new Date().toISOString().slice(0, 13),
      p_title: 'A customer CAD drawing is queued and the CAD worker could not be dispatched: read it with scripts/cad_read_worker.ts',
      p_where: 'customer_api queueCadRead -> public.cad_read_jobs', p_blast: 'customer_facing', p_affected: 1,
      p_evidence: { job_id: jobId, why, run: 'SUPABASE_ACCESS_TOKEN=... deno run --no-lock --node-modules-dir=auto --allow-net --allow-env --allow-read scripts/cad_read_worker.ts', at: new Date().toISOString() },
      p_raised_by: 'sales_engineer',
    });
    if (error) console.error(`[cad] job ${jobId} is queued but its sales_engineer finding was not written: ${error.message}`);
  } catch (e) { console.error(`[cad] job ${jobId} is queued but its sales_engineer finding was not written: ${String((e as Error)?.message || e)}`); }
}

// A CAD DRAWING IS DRAWN FOR SUPPLIERS FROM ITS OWN ENTITIES (24 Sep 2026, sales_engineer; founder
// instructions 32, 580, 703). Until today a .dwg / .dxf reached drawing_redact only as cad_convert's paid
// CloudConvert raster, which has no text layer: the server could not box its title block, the model is held,
// and every CAD drawing a customer sent was held (production, 24 Sep: 6 redaction runs, none complete).
// drawing_redact mode 'cad' draws the drawing itself with its identity left out (_shared/cad_render.ts) and
// records the run; the answer is shaped like the pictured path's, so drawingHandoff decides the same way.
export async function redactCad(o: { secret: string | undefined; b64: string; custId: string; email: string; path: string | null; seeds: string[] }) {
  let rj: any = null;
  try {
    const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` },
      body: JSON.stringify({ __secret: o.secret, mode: 'cad', original_b64: o.b64, seed_terms: o.seeds, prefix: 'redacted', owner_customer_id: o.custId, owner_email: o.email, source_path: o.path }),
      // A drawing that takes longer than this to draw is HELD (the CAD worker draws past the edge's limits).
      signal: AbortSignal.timeout(60_000) });
    rj = await r.json().catch(() => null);
  } catch (_e) { rj = null; }
  const ok = !!(rj?.ok && rj?.recorded && rj?.job_id && Array.isArray(rj.paths) && rj.paths.length);
  const redacted: string[] = ok ? rj.paths.map((x: unknown) => String(x)) : [];
  const meta = { redaction_job_id: ok ? String(rj.job_id) : null, redaction_job_ids: ok ? [String(rj.job_id)] : [], redaction_pages_in: 1, redaction_pages_out: redacted.length, redaction_pages_lost: rj ? 0 : 1, redaction_complete: ok && redacted.length === 1, needs_manual_boxes: false };
  // The anonymised CAD FILE rides with the preview it was drawn beside (never instead of it): its own run, its own
  // verifier; a file that is not proved is simply not attached, and the preview decides the hold as before.
  if (meta.redaction_complete) {
    // The strings were read once, for the preview; the reading rides to the file (drawing_redact takes it only for the
    // same file, by its SHA-256), so a CAD drawing costs one reading, not two (second review, item 8).
    const f = await redactFile({ ...o, stringsReading: rj?.strings_reading ?? null });
    if (f && 'path' in f) { redacted.push(f.path); meta.redaction_job_ids.push(f.job); }
  }
  return { meta, redacted, reason: ok ? null : String(rj?.held_reason || rj?.error || 'cad_redactor_unreachable') };
}

// PAGES OF THE PDF'S TEXT LAYER, READ BY drawing_redact (mode 'plan', 17 Nov 2026; _shared/drawing_plan.ts says why they
// are not read here). Each call waits at most 30 s and never past the analysis's answer budget (`until`, epoch ms); a
// refusal, a 546 or a timeout is no answer (null), and readPdfPlan then gives the whole read up.
export function pdfPlanCall(secret: string | undefined, b64: string, until: number): (b: Record<string, unknown>) => Promise<unknown> {
  // The original is serialised ONCE for the whole read (planBodies): each of the ~2N calls sends its small head and the same
  // shared bytes, the wire body byte for byte what JSON.stringify({ __secret, ...b, original_b64 }) gave.
  const bodyOf = planBodies(secret, b64.replace(/^data:[^;]+;base64,/, ''));
  // No call starts, and none waits, past the read's own budget (PLAN_BUDGET_MS) or the answer budget, whichever is first.
  const stop = Math.min(until, Date.now() + PLAN_BUDGET_MS);
  return async (b) => {
    const left = stop - Date.now();
    if (left < 1_000) return null;
    const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` },
      body: bodyOf(b), signal: AbortSignal.timeout(Math.min(30_000, left)) });
    if (!r.ok) { await r.body?.cancel(); return null; }
    return await r.json().catch(() => null);
  };
}

// THE DUCT AND PIPE LENGTHS, READ BY drawing_boq SHEET BY SHEET (mode 'lengths', 17 Nov 2026; drawing_boq/length_read.ts).
// A part's request carries the original (serialised once, planBodies); the last request, which puts the parts together,
// carries only the parts and the BOQ. Any answer that is not ok (a 500 as much as a 546) is no answer (null).
export function lengthsCall(secret: string | undefined, b64: string, until: number): (b: Record<string, unknown>) => Promise<unknown> {
  const bodyOf = planBodies(secret, b64.replace(/^data:[^;]+;base64,/, ''));
  return async (b) => {
    const left = until - Date.now();
    if (left < 1_000) return null;
    const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` },
      body: b.parts ? JSON.stringify({ __secret: secret, ...b }) : bodyOf(b), signal: AbortSignal.timeout(Math.min(30_000, left)) });
    if (!r.ok) { await r.body?.cancel(); return null; }
    return await r.json().catch(() => null);
  };
}

// THE DRAWING FILE ITSELF (28 Sep 2026, sales_engineer; founder ledger 30, 31, 32, 580, 703): drawing_redact mode
// 'file' returns the customer's PDF / DWG / DXF anonymised as a PDF or DXF a supplier opens and measures, released
// only when _shared/drawing_file_redact.ts's verifier proved geometry, counts and zero identifiers. null = not
// attached (held, refused or unreachable); the reason is on the run row drawing_redact recorded.
export async function redactFile(o: { secret: string | undefined; b64: string; custId: string; email: string; path: string | null; seeds: string[]; stringsReading?: unknown }): Promise<{ path: string; job: string } | { held: string; run?: string; pending_path?: string } | null> {
  try {
    const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` },
      body: JSON.stringify({ __secret: o.secret, mode: 'file', original_b64: o.b64, seed_terms: o.seeds, prefix: 'redacted', owner_customer_id: o.custId, owner_email: o.email, source_path: o.path, ...(o.stringsReading ? { strings_reading: o.stringsReading } : {}) }),
      signal: AbortSignal.timeout(60_000) });
    const j = await r.json().catch(() => null);
    if (j?.ok && j?.recorded && j?.job_id && Array.isArray(j.paths) && j.paths.length === 1) return { path: String(j.paths[0]), job: String(j.job_id) };
    // A released VECTOR PDF waits for its own pixels to be checked (13 Nov 2026, design change A): the portal renders the
    // released file and sends its pages to verifyReleasedFile below; until then it is held, and said to be.
    if (j?.ok && j?.recorded && j?.status === 'awaiting_pixels' && j?.pending_path) return { held: 'awaiting_pixels', run: String(j.job_id), pending_path: String(j.pending_path) };
    // A hold is said, not swallowed (review of #1838): drawing_redact recorded it on drawing_redaction_runs; the reason
    // goes back to analyze_drawing, which tells the customer (drawing_hold.fileHeldNote).
    if (j?.ok && j?.held_reason) { console.warn(`[drawing] the anonymised file of ${o.path} was held: ${j.held_reason}`); return { held: String(j.held_reason) }; }
    return null;
  } catch (_e) { return null; }
}
// THE HOLD IS WRITTEN OR IT IS SAID (24 Sep 2026, audit finding 5). The insert answers { error } rather than
// throwing, so the old try/catch swallowed every failure and a held drawing could have no ledger row at all.
export async function recordHeld(row: ReturnType<typeof heldRun>): Promise<void> {
  try {
    const { error } = await admin.from('drawing_redaction_runs').insert(row);
    if (error) console.error(`[drawing] the hold of ${row.source_path} was not recorded: ${error.message}`);
  } catch (e) { console.error(`[drawing] the hold of ${row.source_path} was not recorded: ${String((e as Error)?.message || e)}`); }
  await drawingIdentityFinding('drawing_held', { source_path: row.source_path, reason: (row.verify_detail as { reason?: string })?.reason ?? null, pages_in: row.pages_in, pages_out: row.pages_out });
}

// A DRAWING, OR WHAT WAS READ FROM IT, HELD FROM SUPPLIERS IS THE SALES ENGINEER'S FINDING (10 Nov 2026, evidence run
// ea40c830, ruling 1608 audit). The hold was a row on drawing_redaction_runs that no seat reads, and the request went to
// suppliers without its drawing while nobody was told but the customer. One finding per kind per hour (the cadReadHeld
// pattern above: a run of uploads must not flood the queue), naming the latest case. The evidence carries ids, paths and
// counts only - never a term the gate matched, which is the customer's own identity.
const FINDING_TITLE = {
  drawing_held: 'A customer drawing is held from suppliers: not every page could be redacted and verified, so the request goes without it',
  boq_identity_dropped: 'Lines read from a customer drawing still named a party (title block) and were dropped before suppliers saw the request',
  boq_held: 'The take-off read from a customer drawing could not be proved free of identity and was held from suppliers',
  sent_without_drawing: 'A request went to suppliers without its drawing: the drawing was not redacted and verified at Send',
  priced_pages_refused: 'Drawing pages were offered for a request whose source document the server judged priced (a quotation or a priced BOQ): none were attached',
} as const;

// THE SERVER'S OWN VERDICT THAT A DOCUMENT IS PRICED (18 Nov 2026, sales_engineer; re-review of c1a934280, item 2). analyze_drawing
// may already have redacted and recorded pages of a document it then judged priced (a quotation or a priced BOQ only the model
// recognised), and the runs stay the customer's own: a modified client could name them at create_inquiry. So the verdict is
// recorded against the stored original, as a 'held' row (no pages, reason PRICED_VERDICT), and create_inquiry refuses every
// page whose run's source, or whose request's stored drawing, carries it (sourcesJudgedPriced).
export const PRICED_VERDICT = 'priced_document' as const;
export async function recordPricedVerdict(o: { customerId: string; email: string; sourcePath: string; kind: string }): Promise<void> {
  try {
    const { error } = await admin.from('drawing_redaction_runs').insert({ customer_id: o.customerId, owner_email: o.email, source_path: o.sourcePath, output_paths: [], pages_in: 0, pages_out: 0, skipped: 0, status: 'held', pages_verified: 0, verify_failed: 0, verify_detail: { reason: PRICED_VERDICT, kind: o.kind } });
    if (error) console.error(`[drawing] the priced verdict on ${o.sourcePath} was not recorded: ${error.message}`);
  } catch (e) { console.error(`[drawing] the priced verdict on ${o.sourcePath} was not recorded: ${String((e as Error)?.message || e)}`); }
}
/** create_inquiry's decision: are the drawing pages offered for this request (resolved from the customer's runs, or a pages
 *  job's) refused? Yes for a brief that is not a drawing's (a quotation, a priced BOQ) and for any page whose source, or whose
 *  request's stored document, the server judged priced; whatever the client sent. */
export async function drawingPagesRefused(o: { custId: string; briefSource: string | null; offered: boolean; follows: boolean; sources: string[] }): Promise<boolean> {
  if (!o.offered && !o.follows) return false;
  if (o.briefSource !== 'drawing') return true;
  return await sourcesJudgedPriced(o.custId, o.sources);
}
/** Whether the server judged any of these stored documents of this customer priced. A read that fails is answered true: no
 *  page is attached on a verdict nobody could read (fail closed). */
export async function sourcesJudgedPriced(custId: string, sourcePaths: string[]): Promise<boolean> {
  const paths = [...new Set(sourcePaths.filter((p) => typeof p === 'string' && p))].slice(0, 30);
  if (!paths.length) return false;
  try {
    const { data, error } = await admin.from('drawing_redaction_runs').select('id').eq('customer_id', custId).eq('status', 'held')
      .eq('verify_detail->>reason', PRICED_VERDICT).in('source_path', paths).limit(1);
    if (error || !Array.isArray(data)) return true;
    return data.length > 0;
  } catch (_e) { return true; }
}
export async function drawingIdentityFinding(kind: keyof typeof FINDING_TITLE, evidence: Record<string, unknown>): Promise<void> {
  try {
    const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: `sales_engineer:${kind}:` + new Date().toISOString().slice(0, 13),
      p_title: FINDING_TITLE[kind],
      p_where: 'customer_api analyze_drawing / create_inquiry -> drawing_redaction_runs, inquiries.boq', p_blast: 'customer_facing', p_affected: 1,
      p_evidence: { ...evidence, at: new Date().toISOString() },
      p_raised_by: 'sales_engineer',
    });
    if (error) console.error(`[drawing] the ${kind} finding was not written: ${error.message}`);
  } catch (e) { console.error(`[drawing] the ${kind} finding was not written: ${String((e as Error)?.message || e)}`); }
}

/**
 * The identity terms of a request's stored drawing, read again AT SEND from the file itself (never from the browser).
 * Not a PDF -> { pdf: false, terms: [] }; a file that cannot be read back, or a PDF whose text layer cannot be read ->
 * terms null (the caller holds what was read from it).
 */
export async function storedDrawingTerms(path: string | null): Promise<{ pdf: boolean; words: number; terms: string[] | null }> {
  if (!path) return { pdf: false, words: -1, terms: [] };
  try {
    const { data } = await admin.storage.from('drawing-files').download(path);
    // A file that cannot be read back is unknown, not clean: terms null, and the caller holds what was read from it.
    if (!data) return { pdf: false, words: -1, terms: null };
    return await pdfIdentityTerms(new Uint8Array(await data.arrayBuffer()));
  } catch (_e) { return { pdf: false, words: -1, terms: null }; }
}

// AUDIT 9.1 (3 Aug 2026). This is the least trusted input in the system: the customer drawing
// path. Whatever lands here is later rendered, passed to an LLM, and shown to suppliers. It
// previously took the caller's declared Content-Type and the caller's filename at face value and
// checked nothing but the byte length - so an HTML document, an SVG carrying script, or a PDF with
// an embedded /Launch action all stored cleanly as "a drawing". It also stored phone photos with
// their EXIF intact, which on an anonymous marketplace means the supplier receives the customer's
// GPS coordinates attached to the "masked" site photo.
// `allow` widens to SAFE_SHEET only on the analyze_boq path (14 Sep 2026); drawings keep PDF/image/CAD.
export async function storeOriginal(custId: string, email: string, name: string, mime: string, b64: string, allow: readonly string[] = [...SAFE_UPLOAD, ...SAFE_CAD]): Promise<string | null> {
  try {
    // 5 Aug 2026. The allow-list was SAFE_UPLOAD (PDF + jpeg/png/webp), which excludes CAD - on the
    // one path in the system that explicitly SUPPORTS CAD. analyze_drawing detects .dwg/.dxf and
    // routes it through cad_convert to get page images, so the drawing was converted, read and
    // turned into a BOQ, while storeOriginal rejected the original and returned null behind a
    // console.warn. The customer saw a successful upload; the inquiry got no drawing_file_path, so
    // the actual CAD file the supplier needs to quote from was gone and nothing reported it.
    // SAFE_CAD already exists for exactly this and was simply never wired to its only caller. The
    // sniffer validates both formats structurally (DWG by its AC10xx magic, ASCII DXF by its
    // SECTION/HEADER shape, and it prefers the dangerous reading on ambiguity), so this widens the
    // accepted set without trusting the caller's declared type.
    const sc = await sanitizeAndScan({ input: b64, declaredMime: mime, filename: name, allow, maxBytes: 25 * 1024 * 1024,
                                       scan: { source: 'customer_api.drawing', subject: String(custId || email || ''), filename: name, bucket: 'drawing-files' } });
    if (!sc.ok) {
      console.warn(`[9.1] drawing rejected: ${sc.body.error} - ${sc.body.detail} (declared ${mime})`);
      return null;
    }
    const s = sc.result;
    if (s.declaredMismatch) console.warn(`[9.1] drawing declared ${mime} but is ${s.mime}; stored as ${s.mime}`);
    const path = `drawings/${custId}/${Date.now()}_${safeFilename(name, s.mime)}`;
    const up = await admin.storage.from('drawing-files').upload(path, s.bytes, { contentType: s.mime, upsert: false });
    // The sanitizer's rejection is logged above but the STORAGE rejection was not, and the bucket
    // carries its own allowed_mime_types. A CAD upload was therefore refused twice, silently, and
    // both layers returned the same null: the caller could not tell "we would not accept this" from
    // "the bucket would not accept this" from "the network failed".
    if (up.error) { console.warn(`[9.1] drawing accepted by the sanitizer as ${s.mime} but REJECTED by storage: ${up.error.message}`); return null; }
    // 14 Sep 2026: the path is returned (and later backed up) only once storage confirms the object.
    if (!(await storedAt(admin, 'drawing-files', path))) { console.warn(`[9.1] drawing upload returned no error but storage does not hold ${path}`); return null; }
    // 5 Aug 2026. THE ORPHAN WINDOW. At this point the object exists and the ONLY record of it is
    // the path about to be returned to the client. If the customer never submits, swaps the
    // attachment, or create_inquiry refuses, no row anywhere names it — and both pdpl_erase and
    // retention_purge walk `inquiries`, so an abandoned upload is not merely litter, it is a
    // customer's drawing that cannot be found and therefore cannot be ERASED on request.
    // A ledger row makes it findable by owner. status='original_stored' distinguishes it from a
    // real redaction run; resolveRedactedPaths filters it out (see the .neq there) because it
    // carries no output_paths and would otherwise consume that query's 60-row window.
    try {
      await admin.from('drawing_redaction_runs').insert({
        customer_id: custId, owner_email: email, source_path: path,
        output_paths: [], pages_in: 0, pages_out: 0, status: 'original_stored',
      });
    } catch (_e) { /* never fail an accepted upload on its own bookkeeping */ }
    return path;
  } catch { return null; }
}

// REDACTION PROVENANCE 2 Aug 2026 (external security review). WHY: QuotesDone sells anonymity —
// a supplier must not learn who the buyer is until the reveal fee is paid. supplier_api hands every
// matched supplier a SIGNED URL for each entry in inquiries.drawing_redacted_paths, and it will sign
// ANY object path in the 'drawing-files' bucket. The customer's ORIGINAL, unredacted upload sits in
// that SAME bucket at drawings/<customer_id>/<ts>_<name> (see storeOriginal above); redacted pages
// sit at redacted/<uuid>/page_pN.jpg. create_inquiry used to copy drawing.drawing_redacted_paths
// verbatim out of the REQUEST BODY, so a modified or simply buggy frontend could name the original —
// title block, client name, address, contacts, project number — and every matched supplier would get
// it for free, pre-reveal, destroying both the promise and the reveal-fee revenue behind it.
// Paths are no longer trusted from the client. drawing_redact records each run in
// public.drawing_redaction_runs (owner, outputs, pages_in/pages_out, status) and this resolver will
// only ever attach paths found in a run row that belongs to the CALLING customer. Anything else is
// REJECTED with an explicit error rather than silently dropped, so the frontend can surface it
// instead of quietly shipping a half-anonymous RFQ.
const REDACT_UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** `sources`: the stored originals the attached pages were redacted from (their runs' source_path), for sourcesJudgedPriced. */
type RedactResolve = { paths: string[]; sources?: string[] } | { err: Record<string, unknown>; status: number };
export async function resolveRedactedPaths(custId: string, authUserId: string, drawing: any): Promise<RedactResolve> {
  const asked = Array.isArray(drawing?.drawing_redacted_paths) ? drawing.drawing_redacted_paths.map((s: any) => String(s)).slice(0, 24) : [];
  const jobIds = [
    ...(drawing?.redaction_job_id ? [String(drawing.redaction_job_id)] : []),
    ...(Array.isArray(drawing?.redaction_job_ids) ? drawing.redaction_job_ids.map((s: any) => String(s)) : []),
  ].filter((s) => REDACT_UUID_RE.test(s)).slice(0, 8);
  // Explicit opt-out: the buyer (or the UI, after a partial redaction) can choose to share no pages
  // at all. Sharing fewer pages never leaks anything, so this is always allowed.
  if (drawing?.share_redacted === false) return { paths: [] };
  if (!jobIds.length && !asked.length) return { paths: [] };
  // Reference photos go through attach_photos, which is authenticated as the same auth user but does
  // not know customers.id; drawing_redact stores the prefix it was called with, so those runs are
  // attributed by that instead. Both branches are server-side ownership checks — neither trusts a path.
  const photoRef = 'refphoto/' + String(authUserId || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 24) + '/';
  const { data: runs, error: rerr } = await admin.from('drawing_redaction_runs')
    .select('id,customer_id,caller_ref,source_path,output_paths,pages_in,pages_out,status')
    .or(`customer_id.eq.${custId},caller_ref.like.${photoRef}%`)
    // NOT optional. storeOriginal now writes one 'original_stored' row per upload so an abandoned
    // drawing stays erasable. Those rows carry no output_paths and contribute nothing here, but
    // this query keeps only the 60 most recent runs — so without this filter a customer who
    // uploads repeatedly would push their own REAL redaction runs out of the window, and
    // create_inquiry would answer redaction_job_not_found (403) on a perfectly good drawing.
    .neq('status', 'original_stored')
    // 'held' rows (analyze_drawing, 21 Sep 2026) are the ledger of drawings that went out unshared;
    // they carry no output_paths either and must not push real runs out of the window.
    .neq('status', 'held')
    .order('created_at', { ascending: false }).limit(60);
  if (rerr) return { err: { error: 'redaction_lookup_failed', message: 'We could not verify the redacted drawing pages just now. Please try again in a moment.' }, status: 503 };
  const mine = (runs || []).filter((r: any) => (r.customer_id && String(r.customer_id) === String(custId)) || (r.caller_ref && String(r.caller_ref).startsWith(photoRef)));
  const byId: Record<string, any> = {}; for (const r of mine) byId[String(r.id)] = r;
  const chosen: any[] = [];
  for (const jid of jobIds) {
    const r = byId[jid];
    if (!r) return { err: { error: 'redaction_job_not_found', message: 'That redaction job does not belong to your account or has expired. Please re-upload the drawing and try again.' }, status: 403 };
    chosen.push(r);
  }
  if (!jobIds.length) chosen.push(...mine);
  const allowed = new Set<string>();
  for (const r of chosen) for (const p of (r.output_paths || [])) allowed.add(String(p));
  let paths: string[];
  if (asked.length) {
    const bad = asked.filter((p: string) => !allowed.has(p));
    if (bad.length) return { err: { error: 'redacted_paths_unverified', rejected: bad.length, message: `${bad.length} of the attached drawing page(s) did not come from a redaction run on your account, so nothing was sent. Please re-run the drawing analysis and submit again.` }, status: 400 };
    paths = asked;
  } else {
    paths = Array.from(allowed);
  }
  // COMPLETENESS. A partial run (say 5 of 8 pages cleaned) must not quietly attach the 5 that
  // worked: the buyer believes the whole drawing was anonymised, and the 3 that failed are exactly
  // the pages the model was least sure about. Fail closed and name the number. A TOTAL failure still
  // behaves as before — no run outputs, no paths, and the inquiry goes out with no drawing attached.
  const used = chosen.filter((r: any) => (r.output_paths || []).some((p: any) => paths.includes(String(p))));
  let missing = 0; for (const r of used) missing += Math.max(0, Number(r.pages_in || 0) - Number(r.pages_out || 0));
  if (paths.length && missing > 0) {
    return { err: { error: 'redaction_incomplete', pages_missing: missing, message: `${missing} page(s) of your drawing could not be redacted, so no pages were shared. Please re-upload a clearer copy, or send the request without the drawing.` }, status: 409 };
  }
  return { paths, sources: [...new Set(used.map((r: any) => String(r.source_path || '')).filter(Boolean))] };
}

/**
 * THE SHEETS OF THIS DRAWING STILL BEING CHECKED OFF THE REQUEST (17 Nov 2026 evening, sales_engineer;
 * _shared/drawing_pages_follow.ts). The newest 'pages_need_time' job of this customer for this stored drawing: open = the
 * pages follow; done with every sheet verified = its pages, resolved through resolveRedactedPaths (the runs must be this
 * customer's and complete). Anything else, or a failed read: nothing follows, nothing is attached (fail closed).
 */
export async function pagesStillBeingChecked(custId: string, authUserId: string, sourcePath: string): Promise<{ paths: string[]; follows: boolean; sources?: string[] }> {
  const none = { paths: [] as string[], follows: false };
  try {
    const { data, error } = await admin.from('cad_read_jobs').select('id,status,result').eq('customer_id', custId).eq('source_path', sourcePath)
      .eq('why', PAGES_NEED_TIME).order('created_at', { ascending: false }).limit(1);
    const job = !error && Array.isArray(data) ? data[0] : null;
    if (!job) return none;
    if (job.status === 'queued' || job.status === 'running') return { paths: [], follows: true };
    const res = job.status === 'done' ? (job.result as any) : null;
    if (res?.redaction_complete !== true || !Array.isArray(res.redaction_job_ids) || !res.redaction_job_ids.length) return none;
    const rr = await resolveRedactedPaths(custId, authUserId, { redaction_job_ids: res.redaction_job_ids.map(String) });
    return 'err' in rr ? none : { paths: rr.paths, follows: false, sources: rr.sources ?? [] };
  } catch (_e) { return none; }
}

// THE RELEASED PDF'S OWN PIXELS (13 Nov 2026, sales_engineer; design change A after the independent review of the
// anonymity fix). drawing_redact cannot render a PDF on the edge, so the released vector file is rendered by the portal
// (pdfRaster.rasterisePdf, annotations off) from the pending path's own bytes, and those pages are checked here by the
// pixel gate. Only a run this returns as complete makes the file signable; anything else leaves it held. The server
// counts the pending file's pages and cross-checks each image's shape and ink against its own reading of the file.
// The caller (customer_api, the composer's confirm step) proves the customer owns the run; drawing_redact checks it too.
export async function verifyReleasedFile(o: { secret: string | undefined; run: string; custId: string; images: string[] }): Promise<{ path: string; job: string } | { held: string } | null> {
  try {
    const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` },
      body: JSON.stringify({ __secret: o.secret, mode: 'verify_file', run_id: o.run, owner_customer_id: o.custId, images: o.images, prefix: 'redacted' }),
      // Every image goes, never a trimmed list: drawing_redact requires one per page of the pending file (second review,
      // item 1: one image of a 5-page file released pages 2-5 unseen) and holds a file over its page cap. Each page is
      // checked in tiles (21 calls for an A1 sheet), so the wait is the edge's own limit, not two minutes. Each image must
      // carry 12 px for 6 pt text (an A1 page 4,769 px on its long side, drawing_redact refuses it coarser: image_too_coarse).
      signal: AbortSignal.timeout(390_000) });
    const j = await r.json().catch(() => null);
    if (j?.ok && j?.recorded && j?.job_id && Array.isArray(j.paths) && j.paths.length === 1) return { path: String(j.paths[0]), job: String(j.job_id) };
    return j?.held_reason ? { held: String(j.held_reason) } : null;
  } catch (_e) { return null; }
}
