import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
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
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const key = await sec('cloudconvert_api_key');
    if (!key) return J({ ok: false, error: 'no_converter' }, 200);
    const b64 = String(body.b64 || '').replace(/^data:[^;]+;base64,/, '');
    if (!b64) return J({ ok: false, error: 'no_file' }, 200);
    const filename = String(body.filename || 'drawing.dwg');
    const ext = (filename.split('.').pop() || 'dwg').toLowerCase();
    const input_format = ext === 'dxf' ? 'dxf' : 'dwg';
    const auth = { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' };
    try {
      let jobRes: Response; let jobJson: any;
      try { jobRes = await jf('https://api.cloudconvert.com/v2/jobs', { method: 'POST', headers: auth, body: JSON.stringify({ tasks: {
        imp: { operation: 'import/base64', file: b64, filename },
        conv: { operation: 'convert', input: 'imp', input_format, output_format: 'png', pixel_density: 200 },
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
      const images: any[] = [];
      for (const f of files.slice(0, 10)) { try { const fr = await jf(f.url, {}, 20000); if (!fr.ok) continue; const buf = new Uint8Array(await fr.arrayBuffer()); if (buf.length) images.push({ mime: 'image/png', data: toB64(buf) }); } catch (_e) { /* skip */ } }
      if (!images.length) return J({ ok: false, error: 'download_failed' }, 200);
      return J({ ok: true, images, pages: images.length });
    } catch (e) { return J({ ok: false, error: 'exception', detail: String((e as Error)?.message || e) }, 200); }
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
