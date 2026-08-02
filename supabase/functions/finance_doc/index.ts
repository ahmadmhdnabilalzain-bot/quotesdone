// finance_doc — store an original finance PDF/receipt, AI-extract it, post it via finance_ingest with doc_path,
// and queue it for Dropbox backup. Admin-JWT or __secret gated.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function isAdmin(email: string){ if(!email) return false; const em=email.toLowerCase(); try{const{data}=await admin.rpc('fn_role_of',{p_email:em}); if(['owner','admin'].includes(String(data||'').toLowerCase())) return true;}catch(_e){} try{const{data}=await admin.from('app_secrets').select('value').eq('key','admin_emails').maybeSingle(); const list=String((data as any)?.value||'').toLowerCase().split(/[,;\s]+/).filter(Boolean); if(list.includes(em)) return true;}catch(_e){} return false; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return J({ ok: true });
  try {
    const body = await req.json().catch(() => ({} as any));
    let ok = false;
    if (body?.__secret && body.__secret === (await sec('inbound_secret'))) ok = true;
    else { const tok = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim(); if (tok) { const { data: u } = await admin.auth.getUser(tok); const em = u?.user?.email || ''; if (em && await isAdmin(em)) ok = true; } }
    if (!ok) return J({ error: 'unauthorized' }, 401);

    const filename = String(body?.filename || 'invoice.pdf');
    const mime = String(body?.mime || 'application/octet-stream');
    let b64 = String(body?.b64 || '');
    const comma = b64.indexOf(','); if (b64.slice(0, 5) === 'data:' && comma > -1) b64 = b64.slice(comma + 1);
    if (!b64) return J({ error: 'file_required' }, 400);

    // 1) store original
    let bytes: Uint8Array;
    try { bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); } catch (_e) { return J({ error: 'bad_base64' }, 400); }
    const safe = filename.replace(/[^a-zA-Z0-9._-]+/g, '_').slice(-80);
    const path = new Date().toISOString().slice(0, 7) + '/' + Date.now() + '-' + safe;
    const up = await admin.storage.from('finance-docs').upload(path, bytes, { contentType: mime, upsert: true });
    if (up.error) return J({ error: 'store_failed: ' + up.error.message }, 500);

    // 2) extract text
    let text = '';
    try { const r = await fetch(`${BASE}/extract_text`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), filename, mime, b64 }) }); const jd = await r.json().catch(() => ({})); text = String((jd as any)?.text || ''); } catch (_e) {}

    // 3) AI parse into a finance entry
    let entry: any = null;
    if (text && text.length > 10) {
      const key = await sec('inbound_secret');
      if (key) {
        const prompt = `Extract a finance entry from this UAE invoice/receipt text. Return STRICT JSON only: {\"kind\":\"expense|income|subscription\",\"amount\":<number in AED>,\"currency\":\"AED\",\"vendor\":\"...\",\"category\":\"...\",\"description\":\"...\",\"cycle\":\"monthly|annual|quarterly|weekly (only if subscription)\"}. If it is a recurring software/service subscription, use kind=subscription. Amount is the total incl VAT. No prose.\n\nTEXT:\n` + text.slice(0, 6000);
        try { const r = await fetch(`${BASE}/ai_gateway`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'finance_doc', sys: '', input: prompt, temperature: 0.1 }) }); const jd = await r.json().catch(() => ({})); let t = (jd as any)?.content || ''; t = String(t).replace(/```json/gi, '').replace(/```/g, '').trim(); const m = t.match(/\{[\s\S]*\}/); entry = JSON.parse(m ? m[0] : t); } catch (_e) { entry = null; }
      }
    }

    // 4) post via finance_ingest with doc_path (only if we parsed a valid amount)
    let logged: any = null;
    if (entry && Number(entry.amount) > 0) {
      entry.source = 'invoice_upload'; entry.doc_path = path; entry.doc_name = filename; entry.doc_content_type = mime;
      try { const r = await fetch(`${BASE}/finance_ingest`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: await sec('inbound_secret'), action: 'log', entry }) }); logged = await r.json().catch(() => ({})); } catch (e) { logged = { error: String((e as Error)?.message || e) }; }
    }

    // 5) queue for Dropbox backup (best-effort)
    try { await admin.from('doc_backups').insert({ source: 'storage', entity: 'expense_entries', entity_id: String(logged?.id || ''), doc_type: 'finance_invoice', bucket: 'finance-docs', path, file_name: filename, dropbox_path: '/QuotesDone Backup/Finance/' + (new Date().toISOString().slice(0, 7)) + '/' + safe, status: 'pending', attempts: 0, dedupe_key: 'finance-docs:' + path }); } catch (_e) {}

    return J({ ok: true, path, extracted_chars: text.length, parsed: entry, logged });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
