import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
function esc(s: string) { return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function money(n: number) { return 'AED ' + Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
async function signedDoc(bucket: string, path: string) { try { const { data } = await admin.storage.from(bucket || 'agent-docs').createSignedUrl(path, 7 * 24 * 3600); return data?.signedUrl || null; } catch { return null; } }

// Observability: log failures and completions to agent_runs. Unauthenticated callers are not
// logged (normal browser traffic, would drown the signal); ownership violations are.
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'reveal_invoice', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break invoice delivery */ }
  };
}

Deno.serve(async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const { data: cust } = await admin.from('customers').select('id,email,full_name').eq('email', user.email.toLowerCase()).maybeSingle();
    if (!cust) { await logRun('error', {}, 'no_customer_profile for authenticated user'); return J({ error: 'No customer profile' }, 403); }
    const body = await req.json().catch(() => ({}));
    const qid = String(body.quote_id || '');
    const { data: tx } = await admin.from('transactions').select('id,quote_id,inquiry_id,reveal_fee,payment_ref,revealed_at,customer_id').eq('quote_id', qid).maybeSingle();
    if (!tx) { await logRun('error', { quote_id: qid }, 'no paid reveal found for quote - customer cannot get an invoice'); return J({ error: 'No paid reveal found for this quote' }, 404); }
    if (tx.customer_id !== cust.id) { await logRun('error', { quote_id: qid, transaction_id: tx.id }, 'ownership violation: customer requested another customer transaction'); return J({ error: 'Not your transaction' }, 403); }
    const { data: cached } = await admin.from('reveal_invoices').select('bucket,path,invoice_no').eq('transaction_id', tx.id).maybeSingle();
    if (cached?.path) { const url = await signedDoc(cached.bucket, cached.path); if (url) { await logRun('ok', { quote_id: qid, cached: true, invoice_no: cached.invoice_no }, ''); return J({ ok: true, url, invoice_no: cached.invoice_no, cached: true }); } }
    const { data: inq } = await admin.from('inquiries').select('summary,category,emirate').eq('id', tx.inquiry_id).maybeSingle();
    const trn = await secret('company_trn');
    const isTax = !!trn;
    const fee = Number(tx.reveal_fee || 0);
    let subtotal = fee, vat = 0, total = fee;
    if (isTax) { total = fee; subtotal = Math.round((fee / 1.05) * 100) / 100; vat = Math.round((total - subtotal) * 100) / 100; }
    const invNo = 'QD-INV-' + String(tx.id).replace(/-/g, '').slice(0, 8).toUpperCase();
    const inqRef = 'QD-' + String(tx.inquiry_id || '').replace(/-/g, '').slice(0, 8).toUpperCase();
    const dateStr = new Date(tx.revealed_at || Date.now()).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    const billTo = esc(cust.full_name ? (cust.full_name + ' (' + cust.email + ')') : cust.email);
    const desc = 'Supplier contact reveal fee — ' + esc(inq?.summary || (inq?.category || 'service request')) + ' (Ref ' + inqRef + ')';
    const title = isTax ? 'Tax Invoice' : 'Payment Receipt';
    const rows = [
      '<tr><th>Invoice No.</th><td>' + invNo + '</td><th>Date</th><td>' + dateStr + '</td></tr>',
      '<tr><th>Billed to</th><td>' + billTo + '</td><th>Payment method</th><td>Card (Stripe)</td></tr>',
      '<tr><th>Payment reference</th><td>' + esc(String(tx.payment_ref || '')) + '</td><th>Status</th><td>Paid</td></tr>'
    ].join('');
    const totalsRows = [
      '<tr><th>Subtotal</th><td>' + money(subtotal) + '</td></tr>',
      isTax ? ('<tr><th>VAT (5%)</th><td>' + money(vat) + '</td></tr>') : '',
      '<tr><th>Total paid</th><td><b>' + money(total) + '</b></td></tr>'
    ].join('');
    const note = isTax
      ? ('<p>Tax Registration Number (TRN): ' + esc(trn) + '. Amount shown is inclusive of 5% VAT.</p>')
      : ('<p>QuotesDone Technologies is not currently registered for VAT; no VAT has been charged on this amount.</p>');
    const body_html =
      '<table><tbody>' + rows + '</tbody></table>' +
      '<h2>Details</h2>' +
      '<table><thead><tr><th>Description</th><th style="text-align:right">Amount</th></tr></thead><tbody>' +
      '<tr><td>' + desc + '</td><td style="text-align:right">' + money(subtotal) + '</td></tr>' +
      '</tbody></table>' +
      '<table style="width:55%;margin-left:auto"><tbody>' + totalsRows + '</tbody></table>' +
      note +
      '<p>This is the QuotesDone facilitation fee for revealing the selected supplier’s contact details. The amount payable to the supplier for the works is agreed separately and directly between the customer and the supplier.</p>';
    const inbound = await secret('cred_fn_reveal_invoice');
    const pr = await fetch(URL_ + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: inbound, title, body_html, name: invNo, lang: 'en', options: { letterhead: true, sign: true, stamp: true } }) });
    const pj = await pr.json();
    if (!pj?.ok || !pj.path) { await logRun('error', { quote_id: qid, invoice_no: invNo }, 'pdf_native failed: ' + String(pj?.error || pj?.detail || '').slice(0, 200)); return J({ error: 'pdf_failed', detail: pj?.error || pj?.detail || '' }, 502); }
    const bucket = pj.bucket || 'agent-docs';
    try { await admin.from('reveal_invoices').upsert({ transaction_id: tx.id, invoice_no: invNo, bucket, path: pj.path, created_at: new Date().toISOString() }, { onConflict: 'transaction_id' }); } catch (_e) { /* */ }
    const url = pj.url || await signedDoc(bucket, pj.path);
    await logRun('ok', { quote_id: qid, invoice_no: invNo, cached: false, is_tax_invoice: isTax }, '');
    return J({ ok: true, url, invoice_no: invNo });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
