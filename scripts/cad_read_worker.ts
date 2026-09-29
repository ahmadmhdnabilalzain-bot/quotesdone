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

const REF = 'htdblwldjkcgjvmqkbeh';
const BASE = `https://${REF}.supabase.co`;
const MAX_JOBS = 6;
const JOB_MS = 5 * 60_000;

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
  const s = Array.isArray(k) ? k.find((x) => x.name === 'service_role')?.api_key : undefined;
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
              array[${paths.map(lit).join(',')}]::text[], ${paths.length}, ${paths.length}, 0, 'complete', ${paths.length}, 0, ${lit(JSON.stringify({ ...detail, worker: true }))}::jsonb)`);
  } catch (e) {
    await removeObjects(key, paths);
    return { ...carry, redaction_complete: false, held_reason: 'run_not_recorded: ' + String((e as Error)?.message || e).slice(0, 120) };
  }
  return { ...carry, redaction_complete: true, redaction_job_id: runId, drawing_redacted_paths: paths };
}

async function supplierDrawing(job: Job, bytes: Uint8Array, key: string): Promise<Record<string, unknown>> {
  const seeds = await seedsOf(job);
  // Imported here, not at the top: drawing_redact_page encodes with imagescript, whose Deno build fetches its
  // codec from deno.land when imported, and dwg_samples.check.ts imports this file with no network to it.
  const { cadPage } = await import('../supabase/functions/_shared/drawing_redact_page.ts');
  const page = await cadPage(bytes, seeds, { maxDwgBytes: Infinity, maxSegments: WORKER_MAX_SEGMENTS });
  if (!page.ok) return { redaction_complete: false, held_reason: page.skipped };
  const out = await publishPages(job, key, [page.jpg], { method: 'cad_render', pages: [{ page: 0, ...page.detail }] });
  if (out.redaction_complete !== true) return out;
  // The anonymised DXF (28 Sep 2026, _shared/drawing_file_redact.ts) rides beside the preview as its own recorded
  // run, released only when its verifier proves geometry, counts and zero identifiers; otherwise it is left out.
  const { anonymisedDrawingFile } = await import('../supabase/functions/_shared/drawing_file_redact.ts');
  const f = await anonymisedDrawingFile(bytes, seeds, { maxDwgBytes: Infinity });
  if (!f.ok) { console.log(`job ${job.id}: the anonymised drawing file was held (${f.held})`); return out; }
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
  return publishPages(job, key, jpgs, { method: 'scan_ocr', pages: detail }, undefined, { boq });
}

// A JOB THAT FAILS FOR GOOD IS RAISED, NOT ONLY LOGGED (24 Sep 2026, drawings audit finding 4): a customer's
// drawing that no reader could open was visible only in this runner's log. The same finding helper every
// seat uses, one deduplicated key; failing to raise it never stops the other jobs.
async function raiseFailed(job: Job, msg: string): Promise<void> {
  try {
    await sql(`select public.fn_it_engineer_finding_upsert(
      'cad_read_worker:job_failed', ${lit('A queued CAD drawing could not be read after 3 attempts')},
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

async function runJob(job: Job, key: string): Promise<void> {
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
  token = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? (() => { try { return Deno.readTextFileSync('C:/Users/Opera/.supabase/access-token'); } catch { return ''; } })()).trim();
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
  Deno.exit(0);
}
