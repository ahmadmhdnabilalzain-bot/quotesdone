// drawing_redact - blacks out client/consultant/contractor/project identifiers (title block, logos, address,
// contacts, drawing/project numbers) on drawing pages so a REDACTED copy can be shared with suppliers.
// Fail-closed: any page we cannot confidently clean is skipped (not shared). Internal-only: __secret auth.
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return null; } }
function stripB64(s:string){ return String(s).replace(/^data:[^;]+;base64,/,''); }
function b64ToBytes(b64:string){ const bin=atob(stripB64(b64)); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
const MAXW = 1600;
const MARGIN = 0.03;

const SYS = `You are a privacy redaction assistant for construction / architectural / MEP drawings that will be shared with COMPETING suppliers. For EACH page image, find EVERY area containing information that could identify the client, the project, or the firms involved — so a supplier cannot identify or contact them.\nCover: the title block (usually a vertical strip on the right edge or a horizontal strip along the bottom), and any consultant / architect / engineer / contractor / developer / owner / client names, company logos, stamps, signatures, addresses, plot / parcel / makani numbers, project name or number, drawing number or reference, phone numbers, emails and websites — wherever they appear (including next to the legend).\nDo NOT cover the technical drawing, dimensions, room/space names, grid bubbles, north arrow, or the legend's symbol explanations themselves — only the identifying text/logos.\nBe GENEROUS: if unsure whether a block is identifying, INCLUDE it. It is far better to over-cover than to leak.\nReturn STRICT JSON ONLY: {\"pages\":[{\"i\":0,\"has_identity\":true,\"regions\":[{\"x\":0.80,\"y\":0.0,\"w\":0.20,\"h\":1.0}]}]} — x,y,w,h are fractions 0..1 of the page (x,y = top-left corner of the box). One object per page, in the SAME order as the images. If a page truly has no identifying info, set has_identity=false and regions=[].`;

// REDACTION PROVENANCE 2 Aug 2026 (external security review). WHY: suppliers are served the paths
// this function returns as SIGNED URLs before any reveal fee is paid, and supplier_api will sign
// ANY object in the 'drawing-files' bucket - including the customer's ORIGINAL, unredacted upload,
// which lives in that same bucket under drawings/<customer_id>/. Until now these paths were only
// RETURNED to the caller and were then copied into inquiries.drawing_redacted_paths straight from
// the create_inquiry REQUEST BODY, so nothing server-side knew which paths were genuinely produced
// by a redaction run, who owned them, or how many pages had actually been cleaned. Every run is now
// recorded in public.drawing_redaction_runs and create_inquiry resolves what may be attached from
// that table alone. Recording is therefore load-bearing, not telemetry: if the insert fails the run
// is reported as unrecorded (recorded:false) and its paths will be refused downstream - fail-closed,
// exactly like a page we could not clean.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function recordRun(id: string, body: any, o: { status: string; paths: string[]; pages_in: number; pages_out: number; skipped: number }): Promise<boolean> {
  try {
    const custId = typeof body?.owner_customer_id === 'string' && UUID_RE.test(body.owner_customer_id) ? body.owner_customer_id : null;
    const { error } = await admin.from('drawing_redaction_runs').insert({
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
    });
    return !error;
  } catch (_e) { return false; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    const __exp = await sec('inbound_secret');
    if (!secretOk(__exp) || body.__secret !== __exp) return J({ error: 'forbidden' }, 403);
    const key = await sec('inbound_secret'); if (!key) return J({ error: 'no_ai_key' }, 500);
    const job_id = crypto.randomUUID();
    // ANONYMITY 27 Jul 2026. These objects are handed to matched suppliers as SIGNED URLs before any
    // reveal or payment, and a signed URL necessarily contains the object path. The path is therefore
    // untrusted output: anything a caller puts in it is readable by every supplier who is matched.
    // Callers used to supply the whole prefix and both of them embedded an identifier plus a clock —
    // customer_api sent `redacted/<customers.id>/<Date.now()>` and attach_photos sends
    // `refphoto/<user.id>/<Date.now()>` — so a supplier could correlate the same buyer across every
    // RFQ they ever post, which is exactly the identity QuotesDone charges a reveal fee to disclose.
    // The caller's prefix now selects ONLY the namespace (its first path segment, e.g. 'redacted' or
    // 'refphoto'); the identifying remainder is discarded and replaced here with an opaque random
    // UUID that is not derivable from the customer, the inquiry or the time. This is deliberately
    // enforced at the single point where the stored path is built, so no caller — present or future —
    // can reintroduce the leak. Retrieval is unaffected: the paths returned below are stored verbatim
    // in inquiries.drawing_redacted_paths, which remains the only source of truth for reading,
    // signing and deleting these objects. Nothing anywhere reconstructs or prefix-lists this path.
    const ns = (String(body.prefix || 'redacted').split('/')[0] || 'redacted').replace(/[^A-Za-z0-9._-]/g, '_');
    const prefix = `${ns}/${crypto.randomUUID()}/page`;
    const imgs: any[] = Array.isArray(body.images) ? body.images.slice(0, 8) : [];
    if (!imgs.length) { const recorded = await recordRun(job_id, body, { status: 'empty', paths: [], pages_in: 0, pages_out: 0, skipped: 0 }); return J({ ok: true, job_id, recorded, paths: [], pages_in: 0, pages_out: 0 }); }

    const content: any[] = [{ type: 'text', text: 'Find identifying regions to black out on each of the following ' + imgs.length + ' drawing page(s). Return the JSON.' }];
    for (const im of imgs) { const b = (im && (im.b64 || im.data)) || im; const m = (im && im.mime) || 'image/jpeg'; if (b && typeof b === 'string') content.push({ type: 'image_url', image_url: { url: 'data:' + m + ';base64,' + stripB64(b) } }); }
    const regionsByPage: Record<number, {x:number;y:number;w:number;h:number}[]> = {};
    const identityByPage: Record<number, boolean> = {};
    try {
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'drawing_redact', max: 2000, temperature: 0, sys: SYS, input: [{ role: 'user', content }] }) });
      const jd = await r.json();
      const parsed = parseJson(jd?.content || '');
      if (!parsed || !Array.isArray(parsed.pages)) { const recorded = await recordRun(job_id, body, { status: 'detect_failed', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'detect_failed', job_id, recorded }, 200); }
      for (const p of parsed.pages) { const i = Number(p?.i); if (!Number.isFinite(i)) continue; identityByPage[i] = p?.has_identity !== false; regionsByPage[i] = Array.isArray(p?.regions) ? p.regions.map((g:any)=>({x:Number(g.x)||0,y:Number(g.y)||0,w:Number(g.w)||0,h:Number(g.h)||0})).filter((g:any)=>g.w>0&&g.h>0) : []; }
    } catch (_e) { const recorded = await recordRun(job_id, body, { status: 'detect_exception', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'detect_exception', job_id, recorded }, 200); }

    const paths: string[] = []; let skipped = 0;
    for (let i = 0; i < imgs.length; i++) {
      try {
        const regions = regionsByPage[i] || [];
        const hasId = identityByPage[i] !== false;
        if (hasId && regions.length === 0) { skipped++; continue; }
        const b = (imgs[i] && (imgs[i].b64 || imgs[i].data)) || imgs[i];
        let img = await Image.decode(b64ToBytes(String(b)));
        if (img.width > MAXW) img = img.resize(MAXW, Image.RESIZE_AUTO);
        const W = img.width, H = img.height;
        for (const g of regions) {
          let x = Math.floor((g.x - MARGIN) * W), y = Math.floor((g.y - MARGIN) * H);
          let w = Math.ceil((g.w + 2 * MARGIN) * W), h = Math.ceil((g.h + 2 * MARGIN) * H);
          x = Math.max(0, Math.min(x, W - 1)); y = Math.max(0, Math.min(y, H - 1));
          w = Math.max(1, Math.min(w, W - x)); h = Math.max(1, Math.min(h, H - y));
          const box = new Image(w, h).fill(0x000000ff);
          img.composite(box, x, y);
        }
        const jpg = await img.encodeJPEG(82);
        const path = `${prefix}_p${i}.jpg`;
        const up = await admin.storage.from('drawing-files').upload(path, jpg, { contentType: 'image/jpeg', upsert: true });
        if (up.error) { skipped++; continue; }
        paths.push(path);
      } catch (_e) { skipped++; continue; }
    }
    const status = paths.length === 0 ? 'failed' : (paths.length < imgs.length ? 'partial' : 'complete');
    const recorded = await recordRun(job_id, body, { status, paths, pages_in: imgs.length, pages_out: paths.length, skipped });
    return J({ ok: true, job_id, recorded, paths, pages_in: imgs.length, pages_out: paths.length, skipped, status });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
});
