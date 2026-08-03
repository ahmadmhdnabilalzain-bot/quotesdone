// make_pdf v6 - native delegator to pdf_native (pdf-lib). Brand letterhead is now the DEFAULT for every
// generated document (header band + logo + footer) unless the caller passes options.letterhead=false or plain=true.
// Detects a doc_render letterhead document and re-renders it natively WITH letterhead + signature + stamp; otherwise
// renders the body content in the standard QuotesDone branded format. Keeps the same {ok,url,path,bytes} response shape.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any){ if (body?.__secret && (await requireInternal(admin, body.__secret, 'make_pdf')).ok) return true; const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,''); const { data:{ user } }=await admin.auth.getUser(jwt); const allow=(await sec('admin_emails')||'').split(',').map((s)=>s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }
function grab(re: RegExp, html: string){ const m = html.match(re); return m ? m[1].replace(/<[^>]+>/g,'').replace(/&amp;/g,'&').trim() : ''; }
function letterheadFragment(html: string){ const metaIdx = html.indexOf('class="doc-meta"'); if(metaIdx<0) return null; const closeMeta = html.indexOf('</div>', metaIdx); if(closeMeta<0) return null; const start = closeMeta + 6; const signIdx = html.indexOf('class="sign"', start); let end; if(signIdx>=0){ const wrap = html.lastIndexOf('<div', signIdx); end = wrap>start ? wrap : signIdx; } else { const ftIdx = html.indexOf('class="ft"', start); end = ftIdx>=0 ? html.lastIndexOf('<div', ftIdx) : html.length; } const frag = html.slice(start, end).trim(); return frag.length>20 ? frag : null; }
function extractTitle(html: string){ return grab(/<title[^>]*>([\s\S]*?)<\/title>/i, html) || grab(/class="doc-title"[^>]*>([\s\S]*?)<\/div>/i, html) || grab(/<h1[^>]*>([\s\S]*?)<\/h1>/i, html); }
function bodyInner(html: string){ let h = html.replace(/<script[\s\S]*?<\/script>/gi,'').replace(/<style[\s\S]*?<\/style>/gi,'').replace(/<head[\s\S]*?<\/head>/gi,''); const m = h.match(/<body[^>]*>([\s\S]*?)<\/body>/i); if(m) h=m[1]; h=h.replace(/<h1[^>]*>[\s\S]*?<\/h1>/i,''); return h; }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(()=>({} as any));
    if (!(await authed(req, body))) return J({ error:'forbidden' }, 403);
    let html = body.html ? String(body.html) : '';
    if (!html && body.url) { try { html = await (await fetch(String(body.url))).text(); } catch(_e){} }
    if (!html || html.length < 20) return J({ error:'html_or_url_required' }, 400);
    const isLetterhead = /class="doc-title"/.test(html) || /qd_lockup_dark/.test(html);
    let frag = '', options = body.options || {};
    if (isLetterhead){ const f = letterheadFragment(html); if(f){ frag = f; options = { letterhead:true, sign:true, stamp:true, ...(body.options||{}) }; } }
    if (!frag) frag = bodyInner(html);
    // Brand letterhead is the default for every generated document unless explicitly opted out.
    if (!body.plain && options.letterhead === undefined) options.letterhead = true;
    const secret = await sec('inbound_secret');
    const payload: Record<string, unknown> = {
      __secret: secret,
      title: body.title || extractTitle(html) || 'Document',
      body_html: frag,
      name: body.name || 'document',
      folder: body.folder || null,
      bucket: body.bucket || 'agent-docs',
      lang: body.lang || 'en',
      options,
      raw: !!body.raw,
    };
    const r = await fetch(`${BASE}/pdf_native`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify(payload) });
    if (body.raw){ const buf = new Uint8Array(await r.arrayBuffer()); return new Response(buf, { status: r.status, headers: { 'Content-Type':'application/pdf', ...CORS } }); }
    const jd = await r.json();
    return J(jd, r.status);
  } catch (e) { return J({ error: String((e as Error)?.message||e) }, 500); }
});
