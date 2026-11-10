// pdf_native v15 - serverless PDF (pdf-lib). Premium dark header band (site theme) + clean light body.
// The drawing lives in ./render.ts (a pure function, 14 Sep 2026); this file is the door: who may
// call it, where the brand assets come from, and where the finished document is stored.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { adminCaller, type TwoStepBody } from '../_shared/admin_session.ts';
import { docIdentity } from '../_shared/doc_template.ts';
import { observe } from '../_shared/observe.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { renderPdf } from './render.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const ASSET = Deno.env.get('SUPABASE_URL')! + '/storage/v1/object/public/brand';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// deno-lint-ignore no-explicit-any
// The JWT half goes through the one admin door (_shared/admin_session.ts): admin_emails AND an aal2 session. An admin
// whose session has one factor gets the body naming the step instead of `true` (security audit 10 Nov 2026, item 1).
async function authed(req: Request, body: any): Promise<true | false | TwoStepBody> { if (body?.__secret && (await requireInternal(admin, body.__secret, 'pdf_native')).ok) return true; const a = await adminCaller(admin, sec, req.headers.get('Authorization')); return a.kind === 'admin' ? true : a.kind === 'two_step_required' ? a.body : false; }
// THE STAMP AND THE SIGNATURE ARE NOT PUBLIC (pre-launch security pass, 6 Oct 2026, M4). Both were in
// the public brand bucket, so anyone could download them and forge a QuotesDone invoice or letter. They
// now live in the PRIVATE bucket company-seal (no storage policy, so only the service role can read it)
// and are read here, server side, at the moment a signed document is drawn. They never reach a browser
// as images; they leave only inside the finished PDF. Fonts and the logo stay in the public brand bucket.
const SEAL_BUCKET = 'company-seal';
const SEAL_FILES = new Set(['qd_stamp.png', 'qd_signature.png']);
async function fetchBytes(path: string){
  try {
    if (SEAL_FILES.has(path)) { const { data, error } = await admin.storage.from(SEAL_BUCKET).download(path); return error || !data ? null : new Uint8Array(await data.arrayBuffer()); }
    const r = await timedFetch(`${ASSET}/${path}`); if(!r.ok) return null; return new Uint8Array(await r.arrayBuffer());
  } catch { return null; }
}

Deno.serve(observe('pdf_native', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    // deno-lint-ignore no-explicit-any
    const body = await req.json().catch(()=>({} as any));
    const ok = await authed(req, body);
    if (ok !== true) return J(ok || { error: 'forbidden' }, 403);
    const identity = await docIdentity(admin);
    const out = await renderPdf(body, { fetchBytes, identity });
    if (!out.ok) return J(out.body, out.status);
    const { bytes, meta, title } = out;
    // CORS carries 'Content-Type': 'application/json', so it goes FIRST and application/pdf wins.
    if (body.raw){ return new Response(bytes as unknown as BodyInit, { status:200, headers:{ ...CORS, 'Content-Type':'application/pdf' } }); }
    const bucket=String(body.bucket||'agent-docs');
    const safe=String(body.name||title||'document').replace(/[^\w.\-]+/g,'_').slice(0,60)||'document';
    const path=(body.folder?String(body.folder).replace(/[^\w\-\/]/g,'')+'/':(new Date().toISOString().slice(0,10)+'/'))+Date.now()+'_'+safe+'.pdf';
    const up=await admin.storage.from(bucket).upload(path, bytes, { contentType:'application/pdf', upsert:true });
    if (up.error) return J({ error:'store_failed', detail: up.error.message }, 500);
    const { data: signed } = await admin.storage.from(bucket).createSignedUrl(path, 7*24*3600);
    return J({ ok:true, bucket, path, url: signed?.signedUrl||null, bytes: bytes.length,
      // Say what the document actually got: fonts embedded, characters dropped, links written,
      // whether the glyph check really ran, which lockup and which letterhead source.
      fonts: meta.fonts, glyphs_dropped: meta.glyphs_dropped, links: meta.links, glyph_check: meta.glyph_check,
      lockup_trimmed: meta.lockup_trimmed, letterhead_source: meta.letterhead_source, pages: meta.pages });
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
}));
