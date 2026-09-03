// reg_fetch - downloads an official regulation/code document (direct URL) into the compliance-docs bucket,
// links it to reg_catalog + compliance_sources, and (for real PDFs) triggers indexing. Rejects HTML/portal
// stubs. Free-published authority documents only. Internal use.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = (Deno.env.get('SUPABASE_URL')||'') + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
// SSRF GUARD. This function fetches a caller-supplied URL and INGESTS the response into the knowledge
// base (kb_ingest below), so the target must be a public http(s) origin. Loopback, private ranges,
// link-local (the cloud metadata address 169.254.169.254), carrier-grade NAT and internal names are
// refused. Redirects are followed, so the FINAL url is re-checked after the fetch: a public host may
// not bounce the request into a private one. Not covered here: a public hostname that RESOLVES to a
// private address (DNS rebinding) — the runtime does not expose the resolved IP; that residual is
// stated rather than hidden.
function unsafeUrl(u: string): string | null {
  let p: URL; try { p = new URL(u); } catch { return 'invalid_url'; }
  if (p.protocol !== 'http:' && p.protocol !== 'https:') return 'scheme_not_http';
  const h = p.hostname.toLowerCase().replace(/^[|]$/g, '');
  if (h === 'localhost' || h.endsWith('.localhost') || h.endsWith('.local') || h.endsWith('.internal') || h === '0.0.0.0') return 'internal_host';
  const m = h.match(/^(d+).(d+).(d+).(d+)$/);
  if (m) {
    const a = Number(m[1]), b = Number(m[2]);
    if (a === 10 || a === 127 || a === 0 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168)
        || (a === 169 && b === 254) || (a === 100 && b >= 64 && b <= 127)) return 'private_address';
  }
  if (h.includes(':') && (h === '::1' || h === '::' || h.startsWith('fc') || h.startsWith('fd') || h.startsWith('fe80'))) return 'private_address';
  return null;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    const secret = await sec('cred_fn_reg_fetch');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'reg_fetch');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const catId = body.catalog_id ? Number(body.catalog_id) : null;
    let url = body.url as string | undefined;
    let authority = body.authority as string | undefined;
    let topic = body.topic as string | undefined;
    let cat: any = null;
    if (catId) { const { data } = await admin.from('reg_catalog').select('*').eq('id', catId).maybeSingle(); cat = data; url = url || cat?.source_url; authority = authority || cat?.authority; topic = topic || cat?.code_name; }
    if (!url) return J({ error: 'no_url' });
    { const bad = unsafeUrl(url); if (bad) return J({ ok:false, error:'url_refused', reason: bad, url: String(url).slice(0,120) }, 400); }
    let resp: Response;
    try { resp = await fetch(url, { redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0 (compatible; QuotesDoneBot/1.0)' } }); }
    catch (e) { return J({ ok:false, error:'fetch_failed', detail:String((e as Error)?.message||e).slice(0,140) }); }
    { const badFinal = unsafeUrl(resp.url || url); if (badFinal) return J({ ok:false, error:'url_refused_after_redirect', reason: badFinal, final_url: String(resp.url||'').slice(0,120) }, 400); }
    if (!resp.ok) return J({ ok:false, error:'http_'+resp.status });
    const ct = (resp.headers.get('content-type')||'').toLowerCase();
    const buf = new Uint8Array(await resp.arrayBuffer());
    const isPdf = ct.includes('pdf') || (buf.length>4 && buf[0]===0x25 && buf[1]===0x50 && buf[2]===0x44 && buf[3]===0x46); // %PDF
    if (!isPdf || buf.length < 30000) {
      if (catId) await admin.from('reg_catalog').update({ status:'needs_source', notes: (cat?.notes? cat.notes+' | ':'')+'auto-fetch got '+(isPdf?'small PDF':ct||'non-pdf')+' ('+buf.length+'B) — needs a direct document URL', updated_at:new Date().toISOString() }).eq('id', catId);
      return J({ ok:false, note:'not_a_document', content_type: ct, bytes: buf.length });
    }
    const path = 'catalog/'+(catId||'x')+'_'+Date.now()+'.pdf';
    const { error: uerr } = await admin.storage.from('compliance-docs').upload(path, buf, { contentType: 'application/pdf', upsert: true });
    if (uerr) return J({ ok:false, error:'upload:'+uerr.message });
    // upsert compliance_sources
    const { data: csrow, error: cerr } = await admin.from('compliance_sources').insert({ authority, topic, url, doc_path: path, doc_bytes: buf.length, doc_content_type: 'application/pdf', doc_downloaded_at: new Date().toISOString(), fetch_mode: 'reg_fetch', active: true }).select('id').single();
    if (cerr) return J({ ok:false, error:'cs_insert:'+cerr.message });
    if (catId) await admin.from('reg_catalog').update({ compliance_source_id: csrow.id, status:'downloaded', source_url: url, updated_at:new Date().toISOString() }).eq('id', catId);
    // trigger indexing of this one document
    let indexed: any = null;
    try { const r = await fetch(FN+'/kb_ingest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: secret, id: csrow.id }) }); indexed = await r.json(); } catch (_e) {}
    if (catId && indexed?.results?.[0]?.chunks > 0) await admin.from('reg_catalog').update({ status:'indexed', updated_at:new Date().toISOString() }).eq('id', catId);
    return J({ ok:true, authority, bytes: buf.length, compliance_source_id: csrow.id, indexed: indexed?.results?.[0] || null });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
