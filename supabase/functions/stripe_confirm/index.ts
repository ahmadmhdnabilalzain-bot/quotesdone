import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function signedFile(path: string | null | undefined): Promise<string | null> { if (!path) return null; try { const { data } = await admin.storage.from('quote-files').createSignedUrl(path, 3600); return data?.signedUrl || null; } catch { return null; } }

// Observability: this is the browser-side confirmation path that records a paid reveal.
// It duplicates stripe_webhook, so a failure here can still be covered by the webhook -
// logging both makes it clear which one actually recorded the money.
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'stripe_confirm', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break reveal confirmation */ }
  };
}

Deno.serve(observe('stripe_confirm', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) { await logRun('error', {}, 'no_customer_profile for authenticated user'); return J({ error: 'No customer profile' }, 403); }
    const body = await req.json().catch(() => ({}));
    const sid = String(body.session_id || '');
    if (!sid) return J({ error: 'missing session_id' }, 400);
    const sk = await secret('stripe_secret_key');
    if (!sk) { await logRun('error', { session_id: sid }, 'CONFIRM BLOCKED - stripe_secret_key missing from app_secrets'); return J({ error: 'stripe_not_configured' }, 200); }
    const r = await fetch('https://api.stripe.com/v1/checkout/sessions/' + encodeURIComponent(sid), { headers: { 'Authorization': 'Bearer ' + sk } });
    const s = await r.json();
    if (!r.ok) { await logRun('error', { session_id: sid, http: r.status }, 'stripe session fetch failed: ' + String(s?.error?.message || '').slice(0, 250)); return J({ error: 'stripe_error', detail: String(s?.error?.message || '').slice(0, 300) }, 502); }
    const md = s.metadata || {};
    const qid = String(md.quote_id || '');
    if (!qid) { await logRun('error', { session_id: sid, payment_status: String(s?.payment_status || '') }, 'session has no metadata.quote_id - cannot record reveal'); return J({ error: 'no quote in session' }, 400); }
    const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount,original_file_path,original_file_name').eq('id', qid).maybeSingle();
    if (!q) { await logRun('error', { quote_id: qid, session_id: sid }, 'quote_id from Stripe session not found in quotes'); return J({ error: 'Quote not found' }, 404); }
    const { data: inq } = await admin.from('inquiries').select('id,customer_id,summary').eq('id', q.inquiry_id).maybeSingle();
    if (!inq || inq.customer_id !== cust.id) { await logRun('error', { quote_id: qid }, 'ownership violation: customer confirmed another customer inquiry'); return J({ error: 'Not your inquiry' }, 403); }
    const supSel = async () => { const { data: sup } = await admin.from('leads').select('company_name,phone,whatsapp,email,website,emirate').eq('id', q.supplier_id).maybeSingle(); return sup; };
    const { data: existing } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle();
    if (existing) { await logRun('ok', { quote_id: qid, already_revealed: true }, 'already recorded (likely by stripe_webhook)'); return J({ ok: true, already_revealed: true, supplier: await supSel(), original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null }); }
    if (s.payment_status !== 'paid') { await logRun('ok', { quote_id: qid, payment_status: String(s.payment_status || '') }, 'session not paid yet - returned pending'); return J({ ok: false, pending: true }); }
    const { data: cfg } = await admin.from('pricing_config').select('refund_window_working_days').eq('id', 1).maybeSingle();
    const { data: dl } = await admin.rpc('fn_add_working_days', { p_from: new Date().toISOString(), p_days: cfg?.refund_window_working_days ?? 3 });
    const fee = Number(md.reveal_fee || (s.amount_total ? s.amount_total / 100 : 0));
    const amount = Number(md.quote_amount || q.quote_amount);
    const payRef = String(s.payment_intent || s.id);
    await admin.from('quotes').update({ status: 'revealed' }).eq('id', qid);
    await admin.from('inquiries').update({ status: 'revealed' }).eq('id', q.inquiry_id);
    const { error: e2 } = await admin.from('transactions').insert({ quote_id: qid, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id, customer_id: cust.id, quote_amount: amount, reveal_fee: fee, app_fee: fee, customer_price: amount, paid_by: 'customer', payment_ref: payRef, fee_status: 'paid', revealed_at: new Date().toISOString(), refund_deadline: dl });
    if (e2) { const { data: again } = await admin.from('transactions').select('id').eq('quote_id', qid).maybeSingle(); if (!again) { await logRun('error', { quote_id: qid, reveal_fee: fee }, 'PAID BUT NOT RECORDED - insert failed and no row present: ' + e2.message + ' | payment_ref: ' + payRef); return J({ error: 'record_failed', detail: e2.message }, 500); } await logRun('ok', { quote_id: qid, raced: true }, 'insert conflicted but row exists - stripe_webhook won the race'); }
    try { const sup = await supSel(); if (sup?.email && /@/.test(sup.email)) await admin.from('notifications').insert([{ type: 'quote_accepted', to_email: sup.email, to_role: 'supplier', lead_id: q.supplier_id, inquiry_id: q.inquiry_id, quote_id: qid, subject: 'A customer revealed your quote on QuotesDone', body: 'A customer paid to reveal your contact for: ' + ((inq?.summary) || '') + '. Please respond promptly — under the Supplier Agreement you must respond within ' + (cfg?.refund_window_working_days ?? 5) + ' working days of the reveal; we chase you after 3 with the customer copied, our chief executive makes the final call on day ' + (cfg?.refund_window_working_days ?? 5) + ', and if you are still silent the customer is refunded and the reveal fee plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.' }]); } catch (_e) { /* */ }
    if (!e2) await logRun('ok', { quote_id: qid, reveal_fee: fee, quote_amount: amount }, 'recorded by stripe_confirm (browser path)');
    return J({ ok: true, supplier: await supSel(), original_file_url: await signedFile(q.original_file_path), original_file_name: q.original_file_name || null });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
