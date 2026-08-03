// os_pages — in-OS Content Studio backend: legal/marketing edit + translate, generate new SEO service pages (background), and publish. Admin-gated. Audit-logged.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN_BASE = (Deno.env.get('SUPABASE_URL') || '') + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-os-key', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function isAdmin(email: string): Promise<boolean> {
  if (!email) return false; const em = email.toLowerCase();
  try { const { data } = await admin.rpc('fn_role_of', { p_email: em }); if (['owner','admin'].includes(String(data||'').toLowerCase())) return true; } catch (_e) {}
  try { const { data } = await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle(); const list = String((data as any)?.value||'').toLowerCase().split(/[,;\s]+/).filter(Boolean); if (list.includes(em)) return true; } catch (_e) {}
  return false;
}
const FILES: Record<string,string> = { legal: 'src/content/legal.json', marketing: 'src/content/marketing.json' };
const SERVICES = 'src/content/services.json';
async function readPath(path: string): Promise<any> {
  const { data } = await admin.from('qd_deploy_src').select('data').eq('path', path).maybeSingle();
  if (!data) return null; try { return JSON.parse(data.data as string); } catch { return null; }
}
async function readFile(src: string){ const path = FILES[src]; if (!path) return null; return await readPath(path); }
async function orLLM(models: string[], sys: string, user: string, max = 4500): Promise<string | null> {
  const key = await sec('cred_fn_os_pages'); if (!key) return null;
  try {
    const r = await fetch(FN_BASE + '/ai_gateway', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'os_pages', sys, input: user, max, temperature: 0.3 }) });
    const j = await r.json(); if (!r.ok) return null;
    let c = j?.content || ''; c = c.replace(/^```[a-z]*\n?/i, '').replace(/```\s*$/, '').trim(); return c || null;
  } catch { return null; }
}
async function translateHtml(html: string, model?: string): Promise<string> {
  const prot = html.replace(/\{\{LOC_THE\}\}/g, '<xloct></xloct>').replace(/\{\{LOC\}\}/g, '<xloc></xloc>');
  const r = await fetch(`${FN_BASE}/translate_html`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_os_pages'), html: prot, model: model || 'anthropic/claude-sonnet-5' }) });
  const jd = await r.json().catch(() => ({} as any));
  if (!(jd as any)?.ok) throw new Error((jd as any)?.error || 'translate_failed');
  return String((jd as any).ar || '').replace(/<xloct><\/xloct>/g, '{{LOC_THE}}').replace(/<xloc><\/xloc>/g, '{{LOC}}');
}
function slugify(name: string){ return name.toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 50); }
async function buildService(name: string, slug: string){
  try {
    const j = await readPath(SERVICES); if (!j || j[slug]) return;
    const tpl = j[Object.keys(j)[0]]?.en?.html; if (!tpl) return;
    const sys = 'You build a QuotesDone SEO service landing page by cloning an existing one. QuotesDone is a UAE B2B anonymous quotation marketplace: a customer posts a job, vetted UAE suppliers quote blind, the customer pays a 3% reveal fee only on the quote they accept. HARD RULES: (1) Keep the EXACT same HTML structure as the template — every tag, class, id, and href, in the same order. (2) Keep every {{LOC_THE}} and {{LOC}} placeholder EXACTLY as-is and in the same relative places (substituted with the emirate/UAE name at build). (3) Only rewrite the human-readable text so the page is about the NEW service, with accurate, specific, non-hyped UAE-market wording (what the service typically covers, what a customer should specify to get a firm quote, common scope). (4) Do NOT invent prices or statistics. (5) Output ONLY the HTML fragment.';
    const enHtml = await orLLM(['anthropic/claude-sonnet-5', 'openai/gpt-4o'], sys, 'NEW SERVICE NAME: ' + name + '\n\nTEMPLATE PAGE TO CLONE:\n' + tpl, 4500);
    if (!enHtml || enHtml.indexOf('{{LOC_THE}}') < 0) return;
    const tplTags = (tpl.match(/</g) || []).length; const newTags = (enHtml.match(/</g) || []).length;
    if (newTags < tplTags * 0.6) return;
    const enTitle = name + ' in {{LOC_THE}} — Get Free Quotes | QuotesDone';
    let arHtml = enHtml, arTitle = enTitle;
    try { arHtml = await translateHtml(enHtml); arTitle = await translateHtml(enTitle); } catch (_e) { /* AR falls back to EN so the page is still valid */ }
    const j2 = await readPath(SERVICES); if (!j2 || j2[slug]) return;
    j2[slug] = { en: { title: enTitle, html: enHtml }, ar: { title: arTitle, html: arHtml } };
    await admin.from('qd_deploy_src').update({ data: JSON.stringify(j2) }).eq('path', SERVICES);
  } catch (_e) { /* background best-effort */ }
}
// Every action below that only READS. Anything not on this list is refused when the caller arrived
// through the x-os-key preview bypass (see the OS BYPASS note in Deno.serve). Derived by walking the
// action handlers in this file one by one, not by name: pages_list and page_get select legal.json and
// marketing.json out of qd_deploy_src, service_list selects services.json, and '' is the empty action,
// which reaches no handler at all. Deliberately NOT here:
//   page_save, translate, service_delete - update qd_deploy_src
//   service_generate                     - spends OpenRouter credit and writes the new page back
//   publish                              - calls deploy_next_preview with target:'production', i.e.
//                                          ships whatever is in qd_deploy_src to quotesdone.com
// An unknown action is not on the list either, so the bypass cannot reach a handler added later
// without someone deciding it is a read.
const READONLY = new Set(['','pages_list','page_get','service_list']);
Deno.serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') return J({ ok: true });
    let email = '';
    // OS BYPASS FIX 28 Jul 2026. os_ops was hardened on 27 Jul and os_api on 28 Jul; this third twin
    // carries the same branch and was missed by both passes. A single static app_secrets.os_bypass_key
    // in an x-os-key header skipped the entire admin identity check, so anyone holding that string could
    // rewrite the legal and marketing pages, spend OpenRouter credit generating or translating service
    // pages, delete a service page and - worst - call publish, which posts to deploy_next_preview with
    // target:'production' and so publishes whatever is in qd_deploy_src to quotesdone.com. The audit row
    // then named 'os-preview@quotesdone.com', a fabricated person, so the log read as if a colleague had
    // done it. Nothing reads through os_bypass_key and app_secrets has no os_bypass_key row, which is the
    // only reason the branch is currently unreachable. Do NOT create that row to make a preview work; it
    // is a static bearer secret on an admin surface. The branch is kept only so that a key created in
    // future cannot mutate anything: it is read-only (see the READONLY gate above) and it is recorded
    // under its own name, never as an email address. os_ops and os_api carry the same gate.
    let viaBypass = false;
    const osKey = req.headers.get('x-os-key') || '';
    if (osKey && osKey === (await sec('os_bypass_key'))) { email = 'os_bypass_key (no human identity)'; viaBypass = true; }
    else {
      const token = (req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'').trim();
      if (!token) return J({ error: 'unauthorized' }, 401);
      const { data: u, error: uerr } = await admin.auth.getUser(token);
      email = u?.user?.email || ''; if (uerr || !email) return J({ error: 'unauthorized' }, 401);
      if (!(await isAdmin(email))) return J({ error: 'forbidden' }, 403);
    }
    const b = await req.json().catch(() => ({} as any));
    const action = String(b?.action || '');

    // A non-read action arriving on the preview key is audited here too, even when it is not one of the
    // five named mutations: an attempt to mutate with the static key is exactly the event worth having
    // on record, so it is logged first and refused second.
    if (['page_save','publish','translate','service_generate','service_delete'].includes(action) || (viaBypass && !READONLY.has(action))) {
      try { const det: any = { ...b }; delete det.action; if (det.html) det.html = '[' + String(det.html).length + ' chars]'; await admin.from('os_audit_log').insert({ actor: email, action, entity: b.source || (action.startsWith('service')?'services':'site'), entity_id: b.slug || b.name || null, detail: det }); } catch (_e) {}
    }
    // Deliberately after the audit insert, for the reason given above.
    if (viaBypass && !READONLY.has(action)) return J({ error: 'forbidden', hint: 'the x-os-key preview key is read-only — sign in with an admin account to make changes' }, 403);

    if (action === 'pages_list') {
      const out: any[] = [];
      for (const src of Object.keys(FILES)) {
        const j = await readFile(src) || {};
        for (const slug of Object.keys(j)) out.push({ source: src, slug, title: (j[slug]?.en?.title) || slug, has_ar: !!(j[slug]?.ar) });
      }
      out.sort((a,b)=> (a.source+a.slug).localeCompare(b.source+b.slug));
      return J({ ok: true, data: { columns: ['source','slug','title','has_ar'], rows: out, total: out.length } });
    }
    if (action === 'page_get') {
      const j = await readFile(String(b.source)); if (!j) return J({ error: 'bad_source' }, 400);
      const loc = b.locale === 'ar' ? 'ar' : 'en'; const rec = j[b.slug]?.[loc];
      if (!rec) return J({ error: 'not_found' }, 404);
      return J({ ok: true, data: { title: rec.title || '', html: rec.html || '' } });
    }
    if (action === 'page_save') {
      const path = FILES[String(b.source)]; if (!path) return J({ error: 'bad_source' }, 400);
      const j = await readFile(String(b.source)); if (!j) return J({ error: 'file_missing' }, 404);
      const loc = b.locale === 'ar' ? 'ar' : 'en';
      if (!j[b.slug]) return J({ error: 'unknown_slug' }, 400);
      if (!j[b.slug][loc]) j[b.slug][loc] = {};
      if (typeof b.title === 'string') j[b.slug][loc].title = b.title;
      if (typeof b.html === 'string') j[b.slug][loc].html = b.html;
      const { error } = await admin.from('qd_deploy_src').update({ data: JSON.stringify(j) }).eq('path', path);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { saved: true } });
    }
    if (action === 'translate') {
      const path = FILES[String(b.source)]; if (!path) return J({ error: 'bad_source' }, 400);
      const j = await readFile(String(b.source)); if (!j) return J({ error: 'file_missing' }, 404);
      const en = j[b.slug]?.en; if (!en) return J({ error: 'no_en_source' }, 404);
      const model = String(b.source) === 'legal' ? 'openai/gpt-4o' : 'openai/gpt-4o-mini';
      let arHtml = '', arTitle = '';
      try { arHtml = await translateHtml(en.html || '', model); arTitle = (await translateHtml('<t>' + (en.title || '') + '</t>', model)).replace(/<\/?t>/g, '').trim(); } catch (e) { return J({ error: String((e as Error)?.message || e) }, 502); }
      if (!j[b.slug].ar) j[b.slug].ar = {};
      j[b.slug].ar.html = arHtml; j[b.slug].ar.title = arTitle || en.title;
      const { error } = await admin.from('qd_deploy_src').update({ data: JSON.stringify(j) }).eq('path', path);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true, data: { translated: true } });
    }

    if (action === 'service_list') {
      const j = await readPath(SERVICES) || {};
      const rows = Object.keys(j).map((slug) => ({ slug, title: String(j[slug]?.en?.title || slug).replace(/ in \{\{LOC_THE\}\}.*/, '').replace(/ —.*/, ''), has_ar: !!(j[slug]?.ar) }));
      rows.sort((a,b)=>a.slug.localeCompare(b.slug));
      return J({ ok: true, data: { columns: ['slug','title','has_ar'], rows, total: rows.length } });
    }
    if (action === 'service_generate') {
      const name = String(b.name || '').trim(); if (!name) return J({ error: 'name_required' }, 400);
      const slug = slugify(name); if (!slug) return J({ error: 'bad_name' }, 400);
      const j = await readPath(SERVICES); if (!j) return J({ error: 'services_missing' }, 404);
      if (j[slug]) return J({ error: 'already_exists', slug }, 400);
      const ER = (globalThis as any).EdgeRuntime; const p = buildService(name, slug);
      if (ER && ER.waitUntil) ER.waitUntil(p); else await p;
      return J({ ok: true, data: { queued: true, slug, note: 'Generating EN + AR in the background (~1 min). It will appear in the service list, then Publish to go live across the UAE + 7 emirates.' } });
    }
    if (action === 'service_delete') {
      const slug = String(b.slug || ''); const j = await readPath(SERVICES); if (!j || !j[slug]) return J({ error: 'not_found' }, 404);
      delete j[slug];
      const { error } = await admin.from('qd_deploy_src').update({ data: JSON.stringify(j) }).eq('path', SERVICES);
      if (error) return J({ error: error.message }, 500);
      return J({ ok: true });
    }

    if (action === 'publish') {
      const r = await fetch(`${FN_BASE}/deploy_next_preview`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __deploy_secret: await sec('deploy_secret'), target: 'production' }) });
      const jd = await r.json().catch(() => ({}));
      if (!(jd as any)?.ok) return J({ error: (jd as any)?.error || 'deploy_failed' }, 502);
      return J({ ok: true, data: { id: (jd as any).id, url: (jd as any).url } });
    }
    return J({ error: 'unknown_action', action }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
