// cad_read_worker — reads the CAD drawings the edge could not, off the request path (22 Sep 2026).
// Assigned: sales_engineer. Founder, 22 Sep 2026: "customer will share cad files or pdf mainly" - a DWG of
// ANY size is read. Instructions 31/63/64/696.
//
// WHY IT EXISTS. An edge function has a 2 s CPU cap and a memory cap, and a CPU kill ends the worker with
// no catch (memory: an-edge-function-has-a-cpu-cap-a-deadline-does-not-bound). The cost of a DWG is not
// its size (dwg.ts DWG_MAX_BYTES: 562 KB took 1.9 s, 1.4 MB took 0.45 s), so no byte ceiling makes the
// edge safe. customer_api therefore queues a CAD original in public.cad_read_jobs when it is past the
// edge ceiling OR the edge worker died reading it, and this script - on a GitHub runner, no CPU cap -
// runs the SAME reader code (doc_read: LibreDWG -> the one DXF take-off) and the SAME BOQ builder
// (drawing_boq/boq_from_document.ts), and writes the BOQ back. customer_api action 'cad_read_status'
// hands it to the customer's own screen. Nothing here is a second implementation of a reader.
//
// HOW IT IS RUN. .github/workflows/cad-read-worker.yml: dispatched by customer_api the moment a job is
// queued (app_secrets.github_token), and on a schedule as the safety net if a dispatch is lost.
//   SUPABASE_ACCESS_TOKEN=... deno run --no-lock --node-modules-dir=auto --allow-net --allow-env --allow-read scripts/cad_read_worker.ts
// It reads through the management API (SQL) and storage with the project's service key; it never
// prints a key or a customer's file name. A job is claimed with fn_cad_read_claim (SKIP LOCKED), so two
// runners never read the same drawing; a runner that dies leaves the job 'running', and the next claim
// takes it back after 30 minutes, three attempts at most, then 'failed' with the reason - never silent.
//
// BOUNDS. The file is at most the drawing-files bucket's own 25 MB (storage refuses more). Each job has a
// 5-minute wall-clock budget here; a run reads at most MAX_JOBS jobs and then exits.
import { readDocument } from '../supabase/functions/_shared/doc_read/index.ts';
import { readDwg } from '../supabase/functions/_shared/doc_read/dwg.ts';
import type { ReadResult } from '../supabase/functions/_shared/doc_read/types.ts';
import { boqFromExtracted } from '../supabase/functions/drawing_boq/boq_from_document.ts';
import { cadSupplierBoq } from '../supabase/functions/_shared/cad_identity.ts';
import { lengthsForSet, mergeLengths } from '../supabase/functions/drawing_boq/drawing_set.ts';
import { pdfPages } from '../supabase/functions/_shared/pdf_text_positions.ts';
import { seedTerms } from '../supabase/functions/_shared/anonymise.ts';
import { PAGES_NEED_TIME, redactQueuedPages, type QueuedPages, type SheetBody } from '../supabase/functions/_shared/drawing_pages_queued.ts';
import { followUpFinishedPages, pagesReachTheirRequestsSql } from '../supabase/functions/_shared/drawing_pages_follow.ts';
import { pickApiKey } from './lib/supabase_keys.mjs';   // new keys first; legacy only as a temporary fallback (27 Oct 2026)

const REF = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${REF}.supabase.co`;
const MAX_JOBS = 6;
const JOB_MS = 5 * 60_000;
// A site photo's check is cut sooner (_shared/site_photo_gate.ts PHOTO_JOB_MS, 4 minutes), inside JOB_MS.
const PHOTO_JOB_MS = 4 * 60_000;
// Sheets the request did not verify: each is one call of drawing_redact's manual path IN THIS PROCESS (sheetRedactorHere
// below) with its own 125 s clock (drawing_deadline.ts), asked at most SHEET_TRIES times. A run cut by this budget keeps the
// sheets it verified (progress) and the next run carries on, so the budget bounds one run, not the set.
const PAGES_JOB_MS = 30 * 60_000;

let token = '';   // set in main; importing this file (dwg_samples.check.ts) reads no environment

async function sql<T = Record<string, unknown>>(query: string): Promise<T[]> {
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }),
    });
    if ((r.status === 429 || r.status >= 500) && attempt < 4) { await new Promise((s) => setTimeout(s, 2000 * 2 ** attempt)); continue; }
    const t = await r.text();
    if (!r.ok) throw new Error(`sql HTTP ${r.status}: ${t.slice(0, 200)}`);
    return JSON.parse(t) as T[];
  }
}
/** A dollar-quoted literal whose tag cannot occur in the value. */
const lit = (s: string) => { let tag = 'qd'; while (s.includes(`$${tag}$`)) tag += 'x'; return `$${tag}$${s}$${tag}$`; };

async function serviceKey(): Promise<string> {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: 'Bearer ' + token } });
  const k = await r.json().catch(() => null) as { name: string; api_key: string }[] | null;
  const s = Array.isArray(k) ? pickApiKey(k, 'secret') : undefined;
  if (!s) throw new Error(`the management api did not return the service key (HTTP ${r.status})`);
  return s;
}

// deno-lint-ignore no-explicit-any
export type Job = { id: string; customer_id: string | null; owner_email: string | null; source_path: string; file_name: string; mime: string; attempts: number; boq_in: any; why: string };

// THE SUPPLIER'S DRAWING OF A CAD FILE THE EDGE COULD NOT OPEN (24 Sep 2026, sales_engineer; founder
// instructions 32, 580, 701, 703). customer_api asks drawing_redact to draw a CAD original for suppliers with
// its identity left out (_shared/cad_render.ts); a DWG past the edge's ceiling cannot be drawn there, so it was
// held. The worker reads it with no ceiling already, and now draws it too: the SAME cadPage, with no DWG size
// ceiling and a 5,000,000-segment budget (no CPU cap here). The page is uploaded under redacted/<uuid>/ and the
// run recorded in drawing_redaction_runs exactly as drawing_redact records one, so create_inquiry resolves it
// and the supplier inbox signs it; if the record fails the upload is removed (no orphan page).
export const WORKER_MAX_SEGMENTS = 5_000_000;

/** The customer's own terms (name, e-mail, phone, file name): what must never reach a supplier. */
async function seedsOf(job: Job): Promise<string[]> {
  const who = job.customer_id ? await sql<{ full_name: string | null; email: string | null; phone: string | null }>(
    `select full_name, email, phone from public.customers where id = ${lit(job.customer_id)}::uuid`) : [];
  const c = who[0] ?? { full_name: '', email: job.owner_email, phone: '' };
  return seedTerms({ name: c.full_name ?? '', email: c.email ?? job.owner_email ?? '', phone: c.phone ?? '', extra: [job.file_name || ''] });
}
const removeObjects = (key: string, paths: string[]) => fetch(`${BASE}/storage/v1/object/drawing-files`, { method: 'DELETE', headers: { Authorization: 'Bearer ' + key, apikey: key, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: paths }), signal: AbortSignal.timeout(30_000) }).catch(() => null);

/**
 * Upload redacted JPEGs under redacted/<uuid>/ and record ONE run naming them, exactly as drawing_redact records
 * one, so create_inquiry resolves it and the supplier inbox signs it. Any failure removes what was uploaded.
 */
async function publishPages(job: Job, key: string, jpgs: Uint8Array[], detail: Record<string, unknown>, as: { ext: string; mime: string } = { ext: "jpg", mime: "image/jpeg" }, carry: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
  const prefix = `redacted/${crypto.randomUUID()}/page`;
  const paths: string[] = [];
  for (let i = 0; i < jpgs.length; i++) {
    const path = as.ext === "jpg" ? `${prefix}_p${i}.jpg` : `${prefix}_drawing.${as.ext}`;
    const up = await fetch(`${BASE}/storage/v1/object/drawing-files/${path}`, { method: 'POST', headers: { Authorization: 'Bearer ' + key, apikey: key, 'Content-Type': as.mime, 'x-upsert': 'false' }, body: new Blob([jpgs[i] as Uint8Array<ArrayBuffer>], { type: as.mime }), signal: AbortSignal.timeout(60_000) });
    if (!up.ok) { await removeObjects(key, paths); return { ...carry, redaction_complete: false, held_reason: `upload_failed_http_${up.status}` }; }
    paths.push(path);
  }
  const runId = crypto.randomUUID();
  try {
    await sql(`insert into public.drawing_redaction_runs (id, customer_id, owner_email, caller_ref, source_path, output_paths, pages_in, pages_out, skipped, status, pages_verified, verify_failed, verify_detail)
      values (${lit(runId)}::uuid, ${job.customer_id ? lit(job.customer_id) + '::uuid' : 'null'}, ${job.owner_email ? lit(job.owner_email) : 'null'}, 'redacted', ${lit(job.source_path)},
              array[${paths.map(lit).join(',')}]::text[], ${paths.length}, ${paths.length}, 0, 'complete', ${paths.length}, 0, ${lit(JSON.stringify({ ...detail, worker: true, pixel_usd: takeSpent(job) }))}::jsonb)`);
  } catch (e) {
    await removeObjects(key, paths);
    return { ...carry, redaction_complete: false, held_reason: 'run_not_recorded: ' + String((e as Error)?.message || e).slice(0, 120) };
  }
  return { ...carry, redaction_complete: true, redaction_job_id: runId, drawing_redacted_paths: paths };
}

// ── NOTHING THE WORKER DRAWS IS PUBLISHED UNSEEN (13 Nov 2026, sales_engineer; design changes A and B after the
// independent review of the anonymity fix). Every page the worker draws goes through drawing_redact mode 'gate' (a
// vision model of another family than any author, asked of the final page, up to twice more after painting what it
// names) and only the page it returns is published; a CAD file's strings are read by drawing_redact mode
// 'read_strings' first. No answer = held.
// The worker calls drawing_redact as customer_api does, with customer_api's per-context credential (fn_internal_auth),
// read once from app_secrets through the worker's own database access and never printed.
let credCache: string | null = null;
async function internalSecret(_key: string): Promise<string> {
  if (credCache === null) { const r = await sql<{ value: string }>(`select value from public.app_secrets where key = 'cred_fn_customer_api'`); credCache = String(r[0]?.value || ''); }
  return credCache;
}
async function edge(key: string, body: Record<string, unknown>, stop?: AbortSignal): Promise<any> {
  // The queued sheets of a set (why 'pages_need_time') never come here: each is checked in process (sheetRedactorHere).
  try {
    const signal = stop ? AbortSignal.any([stop, AbortSignal.timeout(180_000)]) : AbortSignal.timeout(180_000);
    const r = await fetch(`${BASE}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key }, body: JSON.stringify(body), signal });
    return await r.json().catch(() => null);
  } catch (_e) { return null; }
}
const b64u = (u: Uint8Array) => { let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };
// What the model calls of a job cost (USD), recorded on the next run the job writes so the set's budget (drawing_redact
// pixelBudgetFor, by source path, 24 h) counts the worker's calls too; and sent with every call as spent_usd, so the
// calls of one job are counted before that run is written (drawing_redact budgetInFlight).
const spent = new Map<string, number>();
const addSpent = (job: Job, usd: unknown) => spent.set(job.id, (spent.get(job.id) ?? 0) + (Number(usd) || 0));
const takeSpent = (job: Job) => { const u = spent.get(job.id) ?? 0; spent.delete(job.id); return u; };
/** One drawn page through the edge's pixel gate. `pageMm`: a CAD drawing's sheet size (drawing_pixel_gate.pageSizeFromCad),
 *  so it is tiled to its own text; a scan goes without and is tiled as the larger of A1 and its pixels. */
async function gated(job: Job, key: string, jpg: Uint8Array, firstLook = false, pageMm?: { w: number; h: number }): Promise<Uint8Array | { held: string }> {
  const j = await edge(key, { __secret: await internalSecret(key), mode: 'gate', jpg_b64: b64u(jpg), source_path: job.source_path, spent_usd: spent.get(job.id) ?? 0, ...(pageMm ? { page_mm: pageMm } : {}) });
  addSpent(job, j?.pixel_usd);
  if (!j?.ok || typeof j.jpg_b64 !== 'string') return { held: String(j?.held || 'pixels_unverified') };
  if (firstLook && j.first_look_clean !== true) return { held: 'pixels_found_identity' };
  return Uint8Array.from(atob(j.jpg_b64), (c) => c.charCodeAt(0));
}
async function readStrings(job: Job, key: string, dxf: string): Promise<Set<string> | null> {
  const j = await edge(key, { __secret: await internalSecret(key), mode: 'read_strings', dxf_text: dxf, source_path: job.source_path, spent_usd: spent.get(job.id) ?? 0 });
  addSpent(job, j?.strings_usd);
  return j?.ok && Array.isArray(j.identity) ? new Set(j.identity.map(String)) : null;
}

// ── A QUEUED SHEET IS CHECKED HERE, NOT SENT BACK TO THE EDGE (18 Nov 2026, sales_engineer; founder ledger 580) ──────────
// MEASURED, production 18 Nov 10:10 UTC: the sheets a request could not verify (the edge's ~2 s CPU an isolate: 546s and dead
// tiles) were queued here, and this worker sent each one BACK to drawing_redact, where it died the same way ("sheet 1 not
// checked yet (pages_need_time_pixels_unverified)", "(pages_need_time_lost)"): no page reached a supplier. Each sheet now runs
// drawing_redact's manual path IN THIS PROCESS (_shared/drawing_redact_sheet.manualSheetsCall: the same plan, paint, pixel gate,
// model, thresholds, upload path, run row and answer), with no CPU cap:
//   the pixels   drawing_redact_sheet.inProcessWorkers, the functions drawing_redact's modes 'paint', 'repaint', 'tile' and
//                'tiles' run, on the inputs those modes receive;
//   the model    the same ai_gateway call (askPixelsVia: fn 'drawing_redact_verify', counterpart 'deterministic') with the
//                credential drawing_redact presents (app_secrets.cred_fn_ai, read once, never printed), so ai_cost_log, the
//                founder's hold (llm_hold.modelHeld, asked of the same gate) and the rehearsal cap see the same call; the job's
//                budget signal cuts a call under way, and its stop_at is the clock's stop, so no view is asked after it;
//   the record   the same drawing_redaction_runs row (redactionRunRow) and the same upload under redacted/<uuid>/, with the
//                service key over REST (what supabase-js sends); a run not recorded removes its upload (no orphan page);
//   the budget   the set's 24 h spend read from the same rows (runSpentUsd), as drawing_redact budgetInFlight reads it.
// Proved offline: supabase/functions/drawing_redact/a_queued_sheet_is_checked_in_the_worker_as_on_the_edge.check.ts.
let aiCredCache: string | null = null;
async function aiCredential(): Promise<string> {
  if (aiCredCache === null) { const r = await sql<{ value: string }>(`select value from public.app_secrets where key = 'cred_fn_ai'`); aiCredCache = String(r[0]?.value || ''); }
  return aiCredCache;
}
/** app_secrets.cred_db_internal: the proof a sandbox run tag travels with to another function (_shared/e2e_run.ts). */
let runProofCache: string | null = null;
async function runProof(): Promise<string> {
  if (runProofCache === null) { const r = await sql<{ value: string }>(`select value from public.app_secrets where key = 'cred_db_internal'`); runProofCache = String(r[0]?.value || ''); }
  return runProofCache;
}
/** The holds a cut of the job's budget can cause (an answer it aborted, a paint or an upload it stopped): when the budget was
 *  cut, a sheet held for one of them is asked again on the next run, never refused (review of a3fe7161, item 3). A hold the
 *  checker REACHED before the cut (pixels_not_clean, unread text, no regions) is a finding and stays one. */
export const BUDGET_CUT_HOLDS: readonly string[] = ['time', 'pixels_unverified', 'paint_failed', 'decode_failed', 'upload_failed', 'exception'];
// THE RUN'S TAG GOES WITH EVERY CALL (review of a3fe7161, item 1). On the edge, observe() carries a sandbox run's tag
// (x-qd-e2e-run, with its proof) on every call back to the project, so ai_gateway charges the run's window cap and its
// no-spend rules apply; the worker has no request to carry it from. A job's run is its owner's address
// (_shared/e2e_run.runTagOfEmail: qd-<tag>-...@example.invalid, the harness's own customers): such a job's calls send the tag
// with x-qd-e2e-secret (cred_db_internal, which the gateway accepts as proof) to the functions, and with the service bearer to
// PostgREST (the hold probe, the budget read, the run row) and storage. A real customer's job sends no tag. A tag the gateway
// cannot prove is refused there, never spent untagged (spend_guards.unprovenRunTag).
export async function sheetRedactorHere(job: Job, key: string, stop: AbortSignal, stopAt: number): Promise<(b: SheetBody) => Promise<Record<string, unknown>>> {
  // Imported here, not at the top: drawing_redact_page encodes with imagescript (see supplierDrawing).
  const sheet = await import('../supabase/functions/_shared/drawing_redact_sheet.ts');
  const { modelHeld } = await import('../supabase/functions/_shared/llm_hold.ts');
  const { E2E_RUN, runTagOfEmail } = await import('../supabase/functions/_shared/e2e_run.ts');
  const { PIXEL_SET_BUDGET_USD } = await import('../supabase/functions/_shared/drawing_pixel_gate.ts');
  const ai = await aiCredential();
  const tag = runTagOfEmail(job.owner_email);
  const run = tag ? { tag, secret: (await runProof()) || null } : null;
  const tagged: Record<string, string> = run ? { 'x-qd-e2e-run': run.tag, ...(run.secret ? { 'x-qd-e2e-secret': run.secret } : {}) } : {};
  const auth = { apikey: key, Authorization: 'Bearer ' + key, ...tagged };
  const rest = (path: string, init: RequestInit = {}) => fetch(`${BASE}/rest/v1/${path}`, { ...init, headers: { ...auth, 'Content-Type': 'application/json', ...(init.headers ?? {}) }, signal: AbortSignal.timeout(30_000) });
  // What supabase-js's admin.rpc answers (llm_hold.modelHeld reads { data, error }): a failure is an error, never a throw.
  const admin = { rpc: async (fn: string, args: Record<string, unknown>) => {
    try { const r = await rest(`rpc/${fn}`, { method: 'POST', body: JSON.stringify(args) }); const data = await r.json().catch(() => null); return r.ok ? { data, error: null } : { data: null, error: { message: `HTTP ${r.status}` } }; }
    catch (e) { return { data: null, error: { message: String((e as Error)?.message || e) } }; }
  } };
  const deps: import('../supabase/functions/_shared/drawing_redact_sheet.ts').SheetDeps = {
    ...sheet.inProcessWorkers,
    ask: (k, authors, jpg, s, sys) => sheet.askPixelsVia(`${BASE}/functions/v1/ai_gateway`, k, authors, jpg, s, sys, stop, tagged),
    modelHeld: () => modelHeld(admin),
    aiKey: () => Promise.resolve(ai || undefined),
    // drawing_redact pixelBudgetFor + budgetInFlight, read from the same rows. A read that FAILS (a throw, an HTTP error, no
    // rows array) is neither "nothing spent" nor "all spent" (review of a3fe7161, item 2): the sheet's call throws, its answer
    // is the edge's {ok:false} (sheetVerdict: lost), and it is asked again, on this run or the next.
    budget: async (sourcePath, spentUsd) => {
      let used = 0;
      if (typeof sourcePath === 'string' && sourcePath) {
        const r = await rest(`drawing_redaction_runs?select=verify_detail&source_path=eq.${encodeURIComponent(sourcePath)}&created_at=gte.${encodeURIComponent(new Date(Date.now() - 86_400_000).toISOString())}`).catch(() => null);
        const rows = r?.ok ? await r.json().catch(() => null) : null;
        if (!Array.isArray(rows)) throw new Error('budget_unreadable');
        for (const row of rows) used += sheet.runSpentUsd(row);
      }
      let left = PIXEL_SET_BUDGET_USD - used - Math.max(0, Number(spentUsd) || 0);
      return { left: () => left, spend: (u: number) => { left -= u; } };
    },
    upload: async (path, jpg) => {
      try {
        const up = await fetch(`${BASE}/storage/v1/object/drawing-files/${path}`, { method: 'POST', headers: { ...auth, 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }, body: new Blob([jpg as Uint8Array<ArrayBuffer>], { type: 'image/jpeg' }), signal: AbortSignal.timeout(60_000) });
        return up.ok;
      } catch (_e) { return false; }
    },
    publish: async (id, body, o) => {
      let recorded = false;
      try { const r = await rest('drawing_redaction_runs', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(sheet.redactionRunRow(id, body, o)) }); recorded = r.ok; } catch (_e) { recorded = false; }
      if (!recorded && o.paths.length) { const rm = await removeObjects(key, o.paths); if (!rm || !rm.ok) console.log(`job ${job.id}: a sheet's run was not recorded and its page could not be removed`); }
      return recorded;
    },
  };
  // THE JOB'S BUDGET CUT IS NOT A FINDING (review of a3fe7161, item 3). The cut aborts the answer under way; after the checker
  // had painted a box, the gate's 'pixels_unverified' or 'time' then read as checker_found_then_* (drawing_pages_queued
  // sheetVerdict), a permanent hold. A sheet the cut reached that was not published is handed back as lost: asked again.
  const cut = () => stop.aborted || Date.now() >= stopAt;
  return async (b: SheetBody) => {
    const call = () => sheet.manualSheetsCall({ ...b, owner_customer_id: job.customer_id, owner_email: job.owner_email, source_path: job.source_path, stop_at: stopAt }, deps);
    // Inside the run (llm_hold.modelHeld asks a tagged run fresh, never from the cache an untagged job left).
    const out = run ? await E2E_RUN.run(run, call) : await call();
    if (!cut() || (out.ok === true && out.recorded === true && Number(out.pages_out) === 1)) return out;
    const d = Array.isArray(out.verify_detail) ? out.verify_detail[0] as Record<string, unknown> | undefined : undefined;
    const why = String(d?.skipped ?? '');
    return !d || BUDGET_CUT_HOLDS.includes(why) ? { ok: false, error: 'job_budget_cut', cut_hold: why || String(out.error ?? '') } : out;
  };
}

async function supplierDrawing(job: Job, bytes: Uint8Array, key: string): Promise<Record<string, unknown>> {
  const seeds = await seedsOf(job);
  // Imported here, not at the top: drawing_redact_page encodes with imagescript, whose Deno build fetches its
  // codec from deno.land when imported, and dwg_samples.check.ts imports this file with no network to it.
  const { cadPage } = await import('../supabase/functions/_shared/drawing_redact_page.ts');
  const { asciiDxfOf } = await import('../supabase/functions/_shared/cad_file_redact.ts');
  const src = await asciiDxfOf(bytes, Infinity);
  if (!src.ok) return { redaction_complete: false, held_reason: 'cad_' + src.held };
  const identity = await readStrings(job, key, src.dxf);
  if (!identity) return { redaction_complete: false, held_reason: 'strings_not_read' };
  const page = await cadPage(bytes, seeds, { maxDwgBytes: Infinity, maxSegments: WORKER_MAX_SEGMENTS, identity });
  if (!page.ok) return { redaction_complete: false, held_reason: page.skipped };
  const { pageSizeFromCad } = await import('../supabase/functions/_shared/drawing_pixel_gate.ts');
  const mm = (d: Record<string, unknown>) => { const z = pageSizeFromCad(Number(d.width), Number(d.height), Number(d.text_px_p10)); return { w: z.wMm, h: z.hMm }; };
  const seen = await gated(job, key, page.jpg, false, mm(page.detail));
  if (!(seen instanceof Uint8Array)) return { redaction_complete: false, held_reason: seen.held };
  const out = await publishPages(job, key, [seen], { method: 'cad_render', pages: [{ page: 0, ...page.detail }] });
  if (out.redaction_complete !== true) return out;
  // The anonymised DXF (28 Sep 2026, _shared/drawing_file_redact.ts) rides beside the preview as its own recorded
  // run, released only when its verifier proves geometry, counts and zero identifiers AND a drawing of its own bytes
  // is clean on the model's first look (13 Nov 2026); otherwise it is left out.
  const { anonymisedDrawingFile } = await import('../supabase/functions/_shared/drawing_file_redact.ts');
  const f = await anonymisedDrawingFile(bytes, seeds, { maxDwgBytes: Infinity, identity });
  if (!f.ok) { console.log(`job ${job.id}: the anonymised drawing file was held (${f.held})`); return out; }
  const fp = await cadPage(f.bytes, seeds, { maxDwgBytes: Infinity, maxSegments: WORKER_MAX_SEGMENTS });
  const fseen = fp.ok ? await gated(job, key, fp.jpg, true, mm(fp.detail)) : { held: 'released_file_not_drawn' };
  if (!(fseen instanceof Uint8Array)) { console.log(`job ${job.id}: the anonymised drawing file was held (${fseen.held})`); return out; }
  const file = await publishPages(job, key, [f.bytes], { method: 'file', kind: f.kind, ...f.proof }, { ext: f.ext, mime: f.mime });
  if (file.redaction_complete !== true) return out;
  return { ...out, redaction_job_ids: [out.redaction_job_id, file.redaction_job_id], drawing_redacted_paths: [...(out.drawing_redacted_paths as string[]), ...(file.drawing_redacted_paths as string[])] };
}

// A SCANNED DRAWING OR A PHOTO, REDACTED BY OCR (24 Sep 2026, sales_engineer; founder instruction 579: "OCR for
// scanned drawings"). customer_api stores the page rasters of a drawing with no text layer and queues them here
// (why 'scan_needs_ocr', boq_in.scan_pages). Each page is OCR'd with tesseract.js 7.0.0 and the repository's own
// eng + ara data (scripts/lib/scan_ocr.ts), boxed by the PDF path's own rules, painted, OCR'd AGAIN, and kept
// only if the re-read shows no identity (_shared/scan_redact.ts). Held is all-or-nothing, as on the edge
// (customer_api/drawing_hold.ts): one page that is not proved clean publishes none of them.
// Since the second review of #967 every page is read all four ways up, painted, and read all four ways again: eight
// OCR passes, measured 25 Sep 2026 at about 60 s for the ZZ scan's 2600 x 1400 page. customer_api sends at most 20
// pages (MAX_DRAWING_PAGES), so the budget is 30 minutes, inside the workflow's 75.
export const SCAN_JOB_MS = 30 * 60_000;
export async function scanDrawing(job: Job, key: string, pages: string[]): Promise<Record<string, unknown>> {
  const seeds = await seedsOf(job);
  const { Image } = await import('https://deno.land/x/imagescript@1.2.17/mod.ts');
  const { redactScan } = await import('../supabase/functions/_shared/scan_redact.ts');
  const { tesseractOcr } = await import('./lib/scan_ocr.ts');
  const engine = await tesseractOcr('eng+ara');
  let boq: unknown = null;
  const jpgs: Uint8Array[] = [];
  const detail: Record<string, unknown>[] = [];
  try {
    const imgs: { w: number; h: number; rgba: Uint8ClampedArray }[] = [];
    for (let i = 0; i < pages.length; i++) {
      const r = await fetch(`${BASE}/storage/v1/object/drawing-files/${pages[i].split('/').map(encodeURIComponent).join('/')}`, { headers: { Authorization: 'Bearer ' + key, apikey: key }, signal: AbortSignal.timeout(60_000) });
      if (!r.ok) throw new Error(`scan page ${i + 1} could not be downloaded (HTTP ${r.status})`);
      const img = await Image.decode(new Uint8Array(await r.arrayBuffer()));
      imgs.push({ w: img.width, h: img.height, rgba: img.bitmap });
    }
    // THE COUNT FIRST (28 Sep 2026, _shared/scan_takeoff.ts): the scanned set is taken off by the vector set's rules
    // from the same OCR engine, whether or not its pictures can then be shared; a held picture never loses the BOQ.
    const { scanTakeoff } = await import('../supabase/functions/_shared/scan_takeoff.ts');
    // A take-off that throws costs the BOQ only (review of #1056): the pages are still redacted and published.
    try { boq = (await scanTakeoff(imgs, engine.ocr)).boq; }
    catch (e) { boq = null; console.log(`job ${job.id}: the scanned take-off failed, BOQ omitted: ${String((e as Error)?.message || e).slice(0, 160)}`); }
    for (let i = 0; i < imgs.length; i++) {
      const img = imgs[i];
      const out = await redactScan(img, engine.ocr, seeds);
      if (!out.ok) return { redaction_complete: false, held_reason: 'scan_' + out.held, pages: [...detail, { page: i, held: out.held, ...out.detail }], boq };
      const painted = new Image(out.image.w, out.image.h);
      painted.bitmap.set(out.image.rgba);
      jpgs.push(await painted.encodeJPEG(85));   // from pixels: no text layer, no EXIF, no metadata
      detail.push({ page: i, ...out.detail });
    }
  } finally { await engine.done(); }
  // A (13 Nov 2026): every OCR-redacted page is looked at by a model before it is published; all pages or none.
  const seen: Uint8Array[] = [];
  for (let i = 0; i < jpgs.length; i++) {
    const g = await gated(job, key, jpgs[i]);
    if (!(g instanceof Uint8Array)) return { redaction_complete: false, held_reason: 'scan_' + g.held, pages: detail, boq };
    seen.push(g);
  }
  return publishPages(job, key, seen, { method: 'scan_ocr', pages: detail }, undefined, { boq });
}

// A CUSTOMER'S SITE PHOTO, CHECKED BEFORE ANY SUPPLIER SEES IT (15 Nov 2026, sales_engineer; founder rulings 1683 and 1704).
// customer_api site_photo stores the photo and queues it here (why 'site_photo_check'). _shared/site_photo_gate.ts reads it all
// four ways up (tesseract eng + ara), masks every line that is not plain technical content, reads it again, withholds it for
// writing nobody read or too much painted, and asks the final look: drawing_redact mode 'gate' with subject 'site_photo' (the
// photo prompt: faces, plates, house numbers), which paints what it names. Only the gate's own returned JPEG is published (from
// pixels: no EXIF, no GPS), recorded like a scanned page; anything else is withheld, and the customer's notice says why.
export async function sitePhoto(job: Job, key: string, bytes: Uint8Array): Promise<Record<string, unknown>> {
  const seeds = await seedsOf(job);
  const { Image } = await import('https://deno.land/x/imagescript@1.2.17/mod.ts');
  const { checkSitePhoto, photoNotice, photoScale } = await import('../supabase/functions/_shared/site_photo_gate.ts');
  const { tesseractOcr } = await import('./lib/scan_ocr.ts');
  const engine = await tesseractOcr('eng+ara');
  const shot = typeof job.boq_in?.shot === 'string' ? job.boq_in.shot : null;
  let seen: Uint8Array | null = null, lookPainted = false;
  try {
    // scaled down first (review item 6): eight OCR reads of a 12-megapixel photo would not fit the job's time
    const img0 = await Image.decode(bytes);
    const sz = photoScale(img0.width, img0.height);
    const img = sz.scaled ? img0.resize(sz.w, sz.h) : img0;
    const encode = async (x: { w: number; h: number; rgba: Uint8ClampedArray }) => { const o = new Image(x.w, x.h); o.bitmap.set(x.rgba); return await o.encodeJPEG(85); };
    const look = async (x: { w: number; h: number; rgba: Uint8ClampedArray }) => {
      const j = await edge(key, { __secret: await internalSecret(key), mode: 'gate', subject: 'site_photo', jpg_b64: b64u(await encode(x)), source_path: job.source_path, spent_usd: spent.get(job.id) ?? 0 });
      addSpent(job, j?.pixel_usd);
      if (!j?.ok || typeof j.jpg_b64 !== 'string') return null;
      seen = Uint8Array.from(atob(j.jpg_b64), (c) => c.charCodeAt(0));
      lookPainted = j.first_look_clean !== true;
      return { clean: true, regions: [] };
    };
    const r = await checkSitePhoto({ w: img.width, h: img.height, rgba: img.bitmap }, engine.ocr, seeds, look);
    const v = r.status === 'withheld' ? r : { ...r, status: (lookPainted ? 'masked' : r.status) as 'masked' | 'released', reasons: lookPainted ? [...r.reasons, 'face_or_other' as const] : r.reasons };
    const photo = (status: string) => ({ status, reasons: v.reasons, shot, notice_en: photoNotice(0, shot, { ...v, status } as never, 'en'), notice_ar: photoNotice(0, shot, { ...v, status } as never, 'ar') });
    if (v.status === 'withheld' || !seen) return { redaction_complete: false, held_reason: 'site_photo_' + (r.status === 'withheld' ? r.detail : 'not_seen'), photo: photo('withheld') };
    const out = await publishPages(job, key, [seen], { method: 'site_photo', reasons: v.reasons });
    return { ...out, photo: photo(out.redaction_complete === true ? v.status : 'withheld') };
  } finally { await engine.done(); }
}

/** A photo withheld because its check did not finish (time, or an error): the result the card reads, with the customer's notice. */
export async function photoWithheld(shot: string | null, why: string): Promise<Record<string, unknown>> {
  const { photoNotice } = await import('../supabase/functions/_shared/site_photo_gate.ts');
  const r = { status: 'withheld' as const, reasons: ['not_checked' as const], detail: why };
  return { redaction_complete: false, held_reason: why, photo: { status: 'withheld', reasons: r.reasons, shot, notice_en: photoNotice(0, shot, r, 'en'), notice_ar: photoNotice(0, shot, r, 'ar') } };
}

// A JOB THAT FAILS FOR GOOD IS RAISED, NOT ONLY LOGGED (24 Sep 2026, drawings audit finding 4): a customer's
// drawing that no reader could open was visible only in this runner's log. The same finding helper every
// seat uses, one deduplicated key; failing to raise it never stops the other jobs.
async function raiseFailed(job: Job, msg: string, key = 'cad_read_worker:job_failed'): Promise<void> {
  try {
    await sql(`select public.fn_it_engineer_finding_upsert(
      ${lit(key)}, ${lit(key === 'cad_read_worker:job_failed' ? 'A queued CAD drawing could not be read after 3 attempts' : 'A drawing\'s queued sheets were held: its sent requests get no pages')},
      'scripts/cad_read_worker.ts (.github/workflows/cad-read-worker.yml), table public.cad_read_jobs', 'customer_facing', 1,
      ${lit(JSON.stringify({ subject: 'cad_read_jobs', owner_seat: 'sales_engineer', job_id: job.id, error: msg.slice(0, 300) }))}::jsonb,
      '{}'::text[], '{}'::text[], 'sales_engineer')`);
  } catch (e) { console.log(`job ${job.id}: the finding could not be raised: ${String((e as Error)?.message || e).slice(0, 200)}`); }
}

/** A PDF drawing set's lengths (the call that died on the edge), merged into its counted take-off. */
// deno-lint-ignore no-explicit-any
export async function lengthsInto(set: any, pdf: Uint8Array): Promise<any> {
  return mergeLengths({ ...set, missing_info: Array.isArray(set.missing_info) ? set.missing_info : [] }, lengthsForSet(await pdfPages(pdf)));
}

/** The reader for one stored original: a DWG with no ceiling, anything else through the dispatcher. */
export async function readStored(bytes: Uint8Array, name: string): Promise<ReadResult> {
  const ctx = { filename: name, depth: 0 };
  if (/^AC10\d\d$/.test(new TextDecoder('latin1').decode(bytes.subarray(0, 6)))) return readDwg(bytes, ctx, Infinity);
  return readDocument(bytes, name);
}

/** One claimed job, start to finish (exported for the offline check of the queued-sheets path; main is the only caller). */
export async function runJob(job: Job, key: string): Promise<void> {
  const t0 = performance.now();
  const r = await fetch(`${BASE}/storage/v1/object/drawing-files/${job.source_path.split('/').map(encodeURIComponent).join('/')}`,
    { headers: { Authorization: 'Bearer ' + key, apikey: key } });
  if (!r.ok) throw new Error(`the stored drawing could not be downloaded (HTTP ${r.status})`);
  const bytes = new Uint8Array(await r.arrayBuffer());
  const budget = () => new Promise<never>((_, no) => setTimeout(() => no(new Error('the reader ran past its 5-minute budget')), JOB_MS));
  if (job.why === 'scan_needs_ocr') {
    const pages = Array.isArray(job.boq_in?.scan_pages) ? job.boq_in.scan_pages.map(String) : [];
    if (!pages.length) throw new Error('a scan job with no stored pages');
    const scanBudget = new Promise<never>((_, no) => setTimeout(() => no(new Error('the OCR ran past its 30-minute budget')), SCAN_JOB_MS));
    const drawing = await Promise.race([scanDrawing(job, key, pages), scanBudget]);
    await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(JSON.stringify({ boq: null, kind: 'scan', ms: Math.round(performance.now() - t0), ...drawing }))}::jsonb where id = ${lit(job.id)}::uuid`);
    console.log(`job ${job.id}: scan ${drawing.redaction_complete ? 'published' : 'held (' + drawing.held_reason + ')'}, ${pages.length} page(s), ${Math.round(performance.now() - t0)} ms`);
    return;
  }
  if (job.why === PAGES_NEED_TIME) {
    // THE SHEETS analyze_drawing COULD NOT VERIFY (17 Nov 2026; _shared/drawing_pages_queued.ts): held for time, lost to a 546 or
    // a timeout, or held for a transient reason. Each through drawing_redact's own manual path IN THIS PROCESS (18 Nov 2026,
    // sheetRedactorHere above: the edge's CPU cap is what lost them), one sheet a call with its own clock, asked again up to
    // SHEET_TRIES times; the set is published only when every sheet is verified.
    const q = job.boq_in?.queued_pages as QueuedPages | undefined;
    // No sheet left is a run cut after its last sheet was kept (progress) and before the job was closed: it completes at once.
    if (!q || !Array.isArray(q.left) || !Array.isArray(q.done) || q.done.length + q.left.length !== q.pages_in) throw new Error('a pages job whose sheets do not add up');
    const raster = async (p: string) => {
      const rr = await fetch(`${BASE}/storage/v1/object/drawing-files/${p.split('/').map(encodeURIComponent).join('/')}`, { headers: { Authorization: 'Bearer ' + key, apikey: key }, signal: AbortSignal.timeout(60_000) });
      if (!rr.ok) throw new Error(`a stored sheet could not be downloaded (HTTP ${rr.status})`);
      return b64u(new Uint8Array(await rr.arrayBuffer()));
    };
    // THE BUDGET STOPS THE ASKING (review 17 Nov 2026): at PAGES_JOB_MS the call under way is cut and no sheet is sent again,
    // so nothing is paid for after the budget; the job goes back to the queue with every sheet it kept.
    const stop = new AbortController();
    const budgetTimer = setTimeout(() => stop.abort(), PAGES_JOB_MS);
    // No view is asked past the budget either: its end is the clock's stop (drawing_deadline: a caller may bring it earlier).
    const redact = await sheetRedactorHere(job, key, stop.signal, Date.now() + PAGES_JOB_MS);
    // Each verified sheet is kept on the job at once, so a run that is cut, or a later run, never asks (or pays for) it again.
    const progress = async (now: QueuedPages) => { await sql(`update public.cad_read_jobs set boq_in = jsonb_set(boq_in, '{queued_pages}', ${lit(JSON.stringify(now))}::jsonb) where id = ${lit(job.id)}::uuid`); };
    const drawing = await redactQueuedPages(q, { originalB64: b64u(bytes), raster, redact, progress, signal: stop.signal }).finally(() => clearTimeout(budgetTimer));
    // A sheet still lost or held for a transient reason: back to the queue for the next run (three runs, then the finding).
    if (drawing.retry_later === true) throw new Error(`sheet ${Number(drawing.held_page) + 1} not checked yet (${drawing.held_reason}); asked again at the next run`);
    // THE PAGES REACH THE REQUESTS ALREADY SENT (_shared/drawing_pages_follow.ts): attached to each open request of this customer
    // with this drawing and no pages, every matched supplier and the customer told through the delivery door. A failure here
    // leaves the job done with its pages (the portal still adopts them) and is said in the log and on the job's result.
    let follow: Record<string, unknown> = {};
    if (drawing.redaction_complete === true) {
      const stmt = pagesReachTheirRequestsSql(job, (drawing.drawing_redacted_paths as string[]) ?? []);
      try { const r = stmt ? await sql<{ attached: unknown; delivered: unknown }>(stmt) : []; follow = { requests_attached: r[0]?.attached ?? [], deliveries: Array.isArray(r[0]?.delivered) ? (r[0].delivered as unknown[]).length : 0 }; }
      // Not swallowed: the job goes back to the queue with every sheet kept, and the next run attaches (never mails twice:
      // only requests with no pages are touched, and each e-mail carries a dedupe key).
      catch (e) { throw new Error('the verified pages could not be attached to the requests: ' + String((e as Error)?.message || e).slice(0, 200)); }
    }
    await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(JSON.stringify({ boq: null, kind: 'pdf_sheets', ms: Math.round(performance.now() - t0), ...drawing, ...follow }))}::jsonb where id = ${lit(job.id)}::uuid`);
    // HELD HERE IS NOT SILENT (review 17 Nov 2026): a request already sent says "pages follow", and no page will. The seat is told.
    if (drawing.redaction_complete !== true) await raiseFailed(job, 'pages job held, the requests that say pages follow get none: ' + String(drawing.held_reason ?? '').slice(0, 160), 'cad_read_worker:pages_held');
    console.log(`job ${job.id}: ${q.left.length} sheet(s) ${drawing.redaction_complete ? 'published with the set' : 'held (' + drawing.held_reason + ')'}, ${JSON.stringify(follow)}, ${Math.round(performance.now() - t0)} ms`);
    return;
  }
  if (job.why === 'site_photo_check') {
    // A PHOTO'S CHECK ENDS, ONE WAY OR THE OTHER, INSIDE PHOTO_JOB_MS (review of bf8b9ea45, items 6 and 8): past it, or on any error,
    // the photo is WITHHELD and the job is done, so the customer's card leaves "checking" with a reason and no retry pays again.
    // A late publish after the cut is never referenced: only this result's paths reach a supplier (supplier_api/site_photos_door.ts).
    const shot = typeof job.boq_in?.shot === 'string' ? job.boq_in.shot : null;
    const photo = await Promise.race([sitePhoto(job, key, bytes), new Promise<Record<string, unknown>>((res) => setTimeout(() => res(photoWithheld(shot, 'site_photo_time')), PHOTO_JOB_MS))])
      .catch(async (e): Promise<Record<string, unknown>> => ({ ...(await photoWithheld(shot, 'site_photo_failed')), error_detail: String((e as Error)?.message || e).slice(0, 160) }));
    await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(JSON.stringify({ boq: null, kind: 'site_photo', ms: Math.round(performance.now() - t0), ...photo }))}::jsonb where id = ${lit(job.id)}::uuid`);
    console.log(`job ${job.id}: site photo ${photo.redaction_complete ? 'published' : 'withheld (' + photo.held_reason + ')'}, ${Math.round(performance.now() - t0)} ms`);
    return;
  }
  if (job.boq_in && Array.isArray(job.boq_in.boq)) {
    const boq = await Promise.race([lengthsInto(job.boq_in, bytes), budget()]);
    await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(JSON.stringify({ boq, kind: 'pdf', ms: Math.round(performance.now() - t0), bytes: bytes.length }))}::jsonb where id = ${lit(job.id)}::uuid`);
    console.log(`job ${job.id}: lengths done, ${boq.boq?.length ?? 0} lines, ${Math.round(performance.now() - t0)} ms`);
    return;
  }
  const read = await Promise.race([
    readStored(bytes, job.file_name || 'drawing.dwg'),
    budget(),
  ]);
  if (!read.ok) throw new Error(`${read.error}: ${read.detail}`.slice(0, 300));
  // Nothing the CAD file says about its own job reaches a line (cad_identity.ts, as drawing_boq does).
  const boq = cadSupplierBoq(boqFromExtracted(read, '', '', {}), read.dxf_text ?? '');
  const drawing = read.dxf_text ? await Promise.race([supplierDrawing(job, bytes, key), budget()]).catch((e) => ({ redaction_complete: false, held_reason: String((e as Error)?.message || e).slice(0, 160) })) : { redaction_complete: false, held_reason: 'no_cad_entities' };
  const result = JSON.stringify({ boq, kind: read.kind, needs: read.needs, ms: Math.round(performance.now() - t0), bytes: bytes.length, ...drawing });
  await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(result)}::jsonb where id = ${lit(job.id)}::uuid`);
  console.log(`job ${job.id}: done, ${bytes.length} bytes, ${boq.boq?.length ?? 0} lines, ${Math.round(performance.now() - t0)} ms`);
}

if (import.meta.main) {
  token = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? (() => { try { return Deno.readTextFileSync(`${Deno.env.get('HOME') ?? Deno.env.get('USERPROFILE')}/.supabase/access-token`); } catch { return ''; } })()).trim();
  if (!token) { console.error('SUPABASE_ACCESS_TOKEN is not set'); Deno.exit(2); }
  const jobs = await sql<Job>(`select id, customer_id, owner_email, source_path, file_name, mime, attempts, boq_in, why from public.fn_cad_read_claim(${MAX_JOBS})`);
  console.log(`claimed ${jobs.length} job(s)`);
  if (jobs.length) {
    const key = await serviceKey();
    for (const job of jobs) {
      try { await runJob(job, key); } catch (e) {
        const msg = String((e as Error)?.message || e).slice(0, 300);
        // Back to 'queued' for another attempt; fn_cad_read_claim fails it for good after the third.
        await sql(`update public.cad_read_jobs set status = case when attempts >= 3 then 'failed' else 'queued' end,
                   finished_at = case when attempts >= 3 then now() end, error = ${lit(msg)} where id = ${lit(job.id)}::uuid`);
        console.log(`job ${job.id}: ${msg}`);
        if (job.attempts >= 3) await raiseFailed(job, msg);
      }
    }
  }
  // EVERY RUN, claimed jobs or none (review 17 Nov 2026, item 3; _shared/drawing_pages_follow.ts): the pages finished in the last
  // day reach any request saved after its job finished (idempotent, deduped mail), and a request still without the pages it was
  // promised 2 h after its job finished is raised. A failure here never fails the run's jobs.
  try {
    const f = await followUpFinishedPages({
      sql: (q) => sql(q),
      raise: async (k, title, evidence) => { await sql(`select public.fn_it_engineer_finding_upsert(${lit(k)}, ${lit(title)}, 'scripts/cad_read_worker.ts followUpFinishedPages, tables public.cad_read_jobs and public.inquiries', 'customer_facing', 1, ${lit(JSON.stringify({ subject: 'cad_read_jobs', owner_seat: 'sales_engineer', ...evidence }))}::jsonb, '{}'::text[], '{}'::text[], 'sales_engineer')`); },
    });
    console.log(`pages follow-up: ${f.jobs} finished job(s) re-checked, ${f.attached} request(s) given their pages, ${f.failed} attach(es) failed, ${f.still} job(s) raised`);
  } catch (e) { console.log(`pages follow-up could not run: ${String((e as Error)?.message || e).slice(0, 200)}`); }
  Deno.exit(0);
}
