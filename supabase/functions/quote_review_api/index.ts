// quote_review_api - supplier-facing API for the blocking quote-detailing session.
// Actions (supplier JWT): start (open review from an extracted quote), reply (answer the agent, attach
// sub-quotes), get (load thread), submit (GATED: only when the agent marked the quote complete; freezes
// the committed line items + a sha256 hash as the binding record and writes the final quote row).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
const CONCLUDED = ['completed', 'closed', 'cancelled'];
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
function b64ToBytes(b64: string) { const bin = atob(String(b64).replace(/^data:[^;]+;base64,/, '')); const a = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) a[i] = bin.charCodeAt(i); return a; }
async function sha256(s: string) { const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join(''); }
function clip(v: unknown, n: number) { return (v == null || String(v).trim() === '') ? null : String(v).slice(0, n); }

async function loadThread(reviewId: string) {
  const [{ data: msgs }, { data: items }, { data: rv }] = await Promise.all([
    admin.from('quote_review_messages').select('role,body,attachments,created_at').eq('review_id', reviewId).order('created_at', { ascending: true }),
    admin.from('quote_committed_items').select('seq,description,brand,model,spec,qty,unit_price,line_amount,warranty,source,sub_cost,markup_pct,customer_description,hide_brand,confirmed').eq('review_id', reviewId).order('seq', { ascending: true }),
    admin.from('quote_reviews').select('id,status,total_amount,currency').eq('id', reviewId).maybeSingle(),
  ]);
  return { review_id: reviewId, status: rv?.status || 'open', total: rv?.total_amount ?? null, currency: rv?.currency || 'AED', messages: msgs || [], items: items || [] };
}
async function saveItems(reviewId: string, items: any[]) {
  await admin.from('quote_committed_items').delete().eq('review_id', reviewId);
  if (items.length) await admin.from('quote_committed_items').insert(items.map((it: any) => ({ review_id: reviewId, ...it })));
}
async function runAgent(review: any, inq: any, committed: any[], history: any[], reply: any | null) {
  const secret = await sec('inbound_secret');
  const r = await fetch(`${SUPA_URL}/functions/v1/quote_review`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, inquiry: inq || {}, extracted: review.extracted || {}, committed, history, supplier_reply: reply }) });
  return await r.json();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const body = await req.json().catch(() => ({} as any));
    const action = body.action;
    const { data: sup } = await admin.from('leads').select('id,company_name,approval_status,accepted_terms_at,registration_status').eq('claimed_by', email).maybeSingle();
    if (!sup) return J({ error: 'claim your company first' }, 400);
    const inquiry_id = body.inquiry_id;

    if (action === 'get') {
      if (!inquiry_id) return J({ error: 'inquiry_id required' }, 400);
      const { data: rv } = await admin.from('quote_reviews').select('id').eq('inquiry_id', inquiry_id).eq('supplier_id', sup.id).maybeSingle();
      if (!rv) return J({ ok: true, review: null });
      return J({ ok: true, review: await loadThread(rv.id) });
    }

    if (action === 'start') {
      if (!inquiry_id) return J({ error: 'inquiry_id required' }, 400);
      const extracted = body.extracted || {};
      const { data: inq } = await admin.from('inquiries').select('category,summary,status').eq('id', inquiry_id).maybeSingle();
      if (inq && CONCLUDED.includes(String(inq.status))) return J({ error: 'This request has been concluded.' }, 409);
      const { data: rv, error } = await admin.from('quote_reviews').upsert({ inquiry_id, supplier_id: sup.id, status: 'open', extracted, original_file_path: body.original_file_path || null, original_file_name: body.original_file_name || null, currency: extracted.currency || 'AED', updated_at: new Date().toISOString() }, { onConflict: 'inquiry_id,supplier_id' }).select('id').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      const reviewId = rv!.id;
      await admin.from('quote_review_messages').delete().eq('review_id', reviewId);
      const ai = await runAgent({ extracted }, inq, [], [], null);
      if (!ai?.ok) return J({ error: ai?.error || 'agent unavailable' }, 502);
      await saveItems(reviewId, ai.items || []);
      await admin.from('quote_review_messages').insert({ review_id: reviewId, role: 'agent', body: ai.message || '' });
      await admin.from('quote_reviews').update({ status: ai.status === 'complete' ? 'complete' : 'open', total_amount: ai.total, updated_at: new Date().toISOString() }).eq('id', reviewId);
      return J({ ok: true, review: await loadThread(reviewId) });
    }

    if (action === 'reply') {
      const { data: rv } = await admin.from('quote_reviews').select('id,extracted').eq('inquiry_id', inquiry_id).eq('supplier_id', sup.id).maybeSingle();
      if (!rv) return J({ error: 'no review in progress' }, 400);
      const reviewId = rv.id;
      const { data: inq } = await admin.from('inquiries').select('category,summary').eq('id', inquiry_id).maybeSingle();
      const secret = await sec('inbound_secret');
      const attachments: any[] = []; const subQuotes: any[] = [];
      for (const sq of (Array.isArray(body.sub_quotes) ? body.sub_quotes.slice(0, 6) : [])) {
        let path: string | null = null; const name = String(sq.filename || 'sub-quote').slice(0, 180);
        try { if (sq.b64) { const u8 = b64ToBytes(String(sq.b64)); path = `subquotes/${sup.id}/${inquiry_id}/${Date.now()}_${name.replace(/[^A-Za-z0-9._-]/g, '_')}`; await admin.storage.from('quote-files').upload(path, u8, { contentType: sq.mime || 'application/octet-stream', upsert: true }); } } catch (_e) { /* */ }
        let total: number | null = null; let line_items: any[] = [];
        try { const imgs = Array.isArray(sq.images) ? sq.images : []; if (imgs.length || sq.file_b64) { const er = await fetch(`${SUPA_URL}/functions/v1/quote_extract`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, images: imgs, file_b64: sq.file_b64, mime: sq.mime, filename: name, inquiry: inq || {} }) }); const ej = await er.json(); if (ej?.ok) { total = Number(ej.proposal?.amount) || null; line_items = ej.proposal?.line_items || []; } } } catch (_e) { /* */ }
        attachments.push({ path, name, kind: 'sub_quote' });
        subQuotes.push({ name, total, line_items });
      }
      await admin.from('quote_review_messages').insert({ review_id: reviewId, role: 'supplier', body: clip(body.body, 3000) || '', attachments });
      const thread = await loadThread(reviewId);
      const ai = await runAgent(rv, inq, thread.items, thread.messages, { body: body.body || '', sub_quotes: subQuotes });
      if (!ai?.ok) return J({ error: ai?.error || 'agent unavailable' }, 502);
      await saveItems(reviewId, ai.items || []);
      await admin.from('quote_review_messages').insert({ review_id: reviewId, role: 'agent', body: ai.message || '' });
      await admin.from('quote_reviews').update({ status: ai.status === 'complete' ? 'complete' : 'open', total_amount: ai.total, updated_at: new Date().toISOString() }).eq('id', reviewId);
      return J({ ok: true, review: await loadThread(reviewId) });
    }

    if (action === 'submit') {
      if (!sup.accepted_terms_at) return J({ error: 'accept the supplier terms first' }, 400);
      if (sup.approval_status !== 'approved') return J({ error: 'Your registration is pending verification.' }, 403);
      if (sup.registration_status === 'due') return J({ error: 'Your yearly registration is due.' }, 402);
      const { data: rv } = await admin.from('quote_reviews').select('id,status,total_amount,currency,original_file_path,original_file_name').eq('inquiry_id', inquiry_id).eq('supplier_id', sup.id).maybeSingle();
      if (!rv) return J({ error: 'no review in progress' }, 400);
      if (rv.status !== 'complete') return J({ error: 'Your quote is not fully detailed yet. Please finish answering the reviewer so every line has brand, model, specs and price. This protects your quote and locks in exactly what you will deliver.' }, 409);
      const { data: inqStat } = await admin.from('inquiries').select('status,customer_id,summary').eq('id', inquiry_id).maybeSingle();
      if (inqStat && CONCLUDED.includes(String(inqStat.status))) return J({ error: 'This request has been concluded.' }, 409);
      const { data: items } = await admin.from('quote_committed_items').select('seq,description,brand,model,spec,qty,unit_price,line_amount,warranty,source,sub_cost,markup_pct,customer_description,hide_brand,confirmed').eq('review_id', rv.id).order('seq', { ascending: true });
      const list = items || [];
      if (!list.length || list.some((x: any) => !x.confirmed)) return J({ error: 'Some lines are still unconfirmed.' }, 409);
      const amt = Number(rv.total_amount) || list.reduce((a: number, x: any) => a + (Number(x.line_amount) || 0), 0);
      if (!(amt > 0)) return J({ error: 'quote total is zero' }, 400);
      const frozen = { supplier_id: sup.id, inquiry_id, currency: rv.currency || 'AED', total: amt, items: list, committed_at: new Date().toISOString() };
      const hash = await sha256(JSON.stringify(frozen));
      const scopeLines = list.map((x: any) => { const b = (!x.hide_brand && x.brand) ? (x.brand + (x.model ? ' ' + x.model : '') + ' - ') : ''; return `- ${b}${x.customer_description || x.description}${x.qty ? ' (' + x.qty + ')' : ''}${x.line_amount ? ' - AED ' + Number(x.line_amount).toLocaleString() : ''}`; }).join('\n');
      const det: any = { inquiry_id, supplier_id: sup.id, quote_amount: amt, scope: scopeLines.slice(0, 4000), source: 'review', anonymized: true, original_file_path: rv.original_file_path || null, original_file_name: rv.original_file_name || null, review_id: rv.id, review_status: 'complete', committed_at: frozen.committed_at, committed_hash: hash, committed_items: list };
      const { data: q, error } = await admin.from('quotes').upsert(det, { onConflict: 'inquiry_id,supplier_id' }).select('id,quote_amount').maybeSingle();
      if (error) return J({ error: error.message }, 500);
      await admin.from('quote_reviews').update({ status: 'complete', completed_at: frozen.committed_at, committed_hash: hash, total_amount: amt, updated_at: new Date().toISOString() }).eq('id', rv.id);
      await admin.from('inquiries').update({ status: 'quoted' }).eq('id', inquiry_id).in('status', ['sent', 'quoted']);
      try { if (inqStat?.customer_id) { const { data: c } = await admin.from('customers').select('email').eq('id', inqStat.customer_id).maybeSingle(); if (c?.email) await admin.from('notifications').insert({ type: 'new_quote', to_email: c.email, to_role: 'customer', inquiry_id, subject: 'You have a new detailed quote on QuotesDone', body: 'A supplier submitted a fully itemized quote for your request' + (inqStat.summary ? ': ' + inqStat.summary : '') + '. Log in to compare line by line.' }); } } catch (_e) { /* */ }
      return J({ ok: true, quote: q, committed_hash: hash, total: amt });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
