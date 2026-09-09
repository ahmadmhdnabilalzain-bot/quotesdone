// cad_convert — WHAT THIS IS, STATED BEFORE ANYTHING ELSE.
//
// It is a RASTERISER (and, on `to:'pdf'`, a sheet printer). It hands the file to CloudConvert and
// returns what CloudConvert prints. It does NOT read the CAD file. It yields NO entities, NO
// layers, NO blocks or block attributes, NO xrefs, NO dimensions, NO coordinates and NO model
// space — not partially, not on a good day, ever. Anything downstream that reads geometry is
// reading it off a PICTURE with a vision model, with all the error that implies. Nothing here may
// be described to a customer or a supplier as "DWG support"; it is a preview of a drawing sheet.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b, while two callers still called
// it). See the CONTRACT note in the handler for what changed on the way back in.
//
// Not supported: IFC / RVT. sanitizeOrMessage is given SAFE_CAD, which is dwg + dxf only, so a BIM
// file is refused as unsupported_type rather than silently guessed at.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
import { sanitizeOrMessage, SAFE_CAD } from '../_shared/attachment.ts';
function toB64(buf: Uint8Array): string { let s = ''; const CH = 0x8000; for (let i = 0; i < buf.length; i += CH) { s += String.fromCharCode.apply(null, Array.from(buf.subarray(i, i + CH))); } return btoa(s); }
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function jf(url: string, opts: any, ms: number){ const c = new AbortController(); const t = setTimeout(() => c.abort(), ms); try { return await fetch(url, { ...opts, signal: c.signal }); } finally { clearTimeout(t); } }
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'cad_convert');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const key = await sec('cloudconvert_api_key');
    if (!key) return J({ ok: false, error: 'no_converter' }, 200);
    // ── CONTRACT (reconciled 9 Sep 2026). TWO CALLERS, TWO SHAPES, AND ONE OF THEM NEVER WORKED.
    //
    //   customer_api:581            {b64, filename}                wants page IMAGES
    //   supplier_catalog_ingest:150 {data, file_name, to:'pdf'}    wants a PDF SHEET, and reads
    //                               `conv.pdf_b64 || conv.data`
    //
    // Before the sweep this function knew only the first shape and only ever returned
    // {ok, images, pages}. So supplier_catalog_ingest's `!conv?.data && !conv?.pdf_b64` was ALWAYS
    // true and that branch ALWAYS reported conversion_failed — every CAD catalogue upload a
    // supplier ever made. supplier_catalog_ingest is owned by another effort and is not edited
    // here; the reconciliation is on THIS side, which is also the smaller and safer place for it:
    // one function learns both shapes instead of a caller being rewritten.
    //
    // Both callers are honest about what they want. customer_api rasterises to feed a vision model
    // page by page; supplier_catalog_ingest wants one printable sheet to feed as a PDF. `to`
    // selects between them and defaults to 'png', so the pre-sweep caller is unchanged.
    const b64 = String(body.b64 ?? body.data ?? '').replace(/^data:[^;]+;base64,/, '');
    if (!b64) return J({ ok: false, error: 'no_file' }, 200);
    const filename = String(body.filename || body.file_name || 'drawing.dwg');
    const to = String(body.to || 'png').toLowerCase() === 'pdf' ? 'pdf' : 'png';
    // AUDIT 9.1 (3 Aug 2026): the type came off the FILENAME and the bytes were forwarded to
    // CloudConvert unexamined — an unauthenticated-by-content file relay. sniff() now recognises
    // DWG by its AC10xx version header (matched as a shape, so a newer AutoCAD release does not
    // become an unknown upload) and both ASCII and binary DXF.
    const __san = sanitizeOrMessage({ input: b64, declaredMime: null, filename,
                                      allow: SAFE_CAD, maxBytes: 40 * 1024 * 1024,
                                      stripMetadata: false });
    if (!__san.ok) return J({ ok: false, ...__san.body }, __san.status);
    const ext = (filename.split('.').pop() || 'dwg').toLowerCase();
    const input_format = ext === 'dxf' ? 'dxf' : 'dwg';
    const auth = { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' };
    try {
      let jobRes: Response; let jobJson: any;
      try { jobRes = await jf('https://api.cloudconvert.com/v2/jobs', { method: 'POST', headers: auth, body: JSON.stringify({ tasks: {
        imp: { operation: 'import/base64', file: b64, filename },
        conv: to === 'pdf'
          ? { operation: 'convert', input: 'imp', input_format, output_format: 'pdf' }
          : { operation: 'convert', input: 'imp', input_format, output_format: 'png', pixel_density: 200 },
        exp: { operation: 'export/url', input: 'conv', inline: false, archive_multiple_files: false }
      } }) }, 25000); jobJson = await jobRes.json(); } catch (e) { return J({ ok: false, error: 'create_exception', detail: String((e as Error)?.message || e) }, 200); }
      if (body.__probe) return J({ ok: true, probe: true, createStatus: jobRes.status, jobId: jobJson?.data?.id || null, raw: JSON.stringify(jobJson).slice(0, 600) });
      if (!jobRes.ok) return J({ ok: false, error: 'convert_create_failed', detail: JSON.stringify(jobJson?.message || jobJson).slice(0, 400) }, 200);
      const jobId = jobJson?.data?.id;
      if (!jobId) return J({ ok: false, error: 'no_job_id' }, 200);
      let expTask: any = null; let lastStatus = '';
      for (let i = 0; i < 16; i++) {
        await sleep(3500);
        let pj: any = {};
        try { const pr = await jf('https://api.cloudconvert.com/v2/jobs/' + jobId, { headers: auth }, 12000); pj = await pr.json(); } catch (_e) { continue; }
        const tasks: any[] = pj?.data?.tasks || []; lastStatus = pj?.data?.status || '';
        const conv = tasks.find((t) => t.name === 'conv');
        if (conv && conv.status === 'error') return J({ ok: false, error: 'convert_failed', detail: String(conv?.message || 'conversion error').slice(0, 400) }, 200);
        if (lastStatus === 'error') { const ferr = tasks.find((t) => t.status === 'error'); return J({ ok: false, error: 'job_error', detail: String(ferr?.message || '').slice(0, 400) }, 200); }
        expTask = tasks.find((t) => t.name === 'exp');
        if (expTask && expTask.status === 'finished') break;
      }
      if (!expTask || expTask.status !== 'finished') return J({ ok: false, error: 'timeout', detail: 'status ' + lastStatus }, 200);
      const files: any[] = expTask?.result?.files || [];
      if (!files.length) return J({ ok: false, error: 'no_output' }, 200);
      if (to === 'pdf') {
        // ONE sheet. `pdf_b64` and `data` are the same bytes under both names because
        // supplier_catalog_ingest reads `conv.pdf_b64 || conv.data` and neither name is wrong.
        let pdf = '';
        for (const f of files.slice(0, 1)) { try { const fr = await jf(f.url, {}, 20000); if (!fr.ok) continue; const buf = new Uint8Array(await fr.arrayBuffer()); if (buf.length) pdf = toB64(buf); } catch (_e) { /* skip */ } }
        if (!pdf) return J({ ok: false, error: 'download_failed' }, 200);
        return J({ ok: true, pdf_b64: pdf, data: pdf, pages: 1, raster_preview_only: true });
      }
      const images: any[] = [];
      for (const f of files.slice(0, 10)) { try { const fr = await jf(f.url, {}, 20000); if (!fr.ok) continue; const buf = new Uint8Array(await fr.arrayBuffer()); if (buf.length) images.push({ mime: 'image/png', data: toB64(buf) }); } catch (_e) { /* skip */ } }
      if (!images.length) return J({ ok: false, error: 'download_failed' }, 200);
      // raster_preview_only is stated in the payload, not only in this file's header, so a caller
      // cannot read these images as an entity-level read of the CAD file.
      return J({ ok: true, images, pages: images.length, raster_preview_only: true });
    } catch (e) { return J({ ok: false, error: 'exception', detail: String((e as Error)?.message || e) }, 200); }
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
