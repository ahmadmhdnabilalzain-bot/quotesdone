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
type Job = { id: string; source_path: string; file_name: string; mime: string; attempts: number; boq_in: any };

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
  const result = JSON.stringify({ boq, kind: read.kind, needs: read.needs, ms: Math.round(performance.now() - t0), bytes: bytes.length });
  await sql(`update public.cad_read_jobs set status = 'done', finished_at = now(), error = null, result = ${lit(result)}::jsonb where id = ${lit(job.id)}::uuid`);
  console.log(`job ${job.id}: done, ${bytes.length} bytes, ${boq.boq?.length ?? 0} lines, ${Math.round(performance.now() - t0)} ms`);
}

if (import.meta.main) {
  token = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? (() => { try { return Deno.readTextFileSync('C:/Users/Opera/.supabase/access-token'); } catch { return ''; } })()).trim();
  if (!token) { console.error('SUPABASE_ACCESS_TOKEN is not set'); Deno.exit(2); }
  const jobs = await sql<Job>(`select id, source_path, file_name, mime, attempts, boq_in from public.fn_cad_read_claim(${MAX_JOBS})`);
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
      }
    }
  }
  Deno.exit(0);
}
