import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { resolveInvoice } from './resolve.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const URL_ = Deno.env.get('SUPABASE_URL')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function secret(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
function esc(s: string) { return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function money(n: number) { return 'AED ' + Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
async function signedDoc(bucket: string, path: string, ttl = 7 * 24 * 3600) { try { const { data } = await admin.storage.from(bucket || 'agent-docs').createSignedUrl(path, ttl); return data?.signedUrl || null; } catch { return null; } }

// The accountant's invoice door for the customer (14 Sep 2026). A sale billed by Stripe opens
// Stripe's own PDF, fetched fresh at click time (resolve.ts); only a sale with no Stripe invoice
// falls back to the QuotesDone receipt below.
async function stripeInvoicePdf(invoiceId: string): Promise<string | null> {
  // The sale does not record which mode it was charged in, so live is asked first and the test key
  // (when configured) second. An invoice id exists in exactly one mode; the other answers 404.
  for (const k of ['stripe_secret_key', 'stripe_secret_key_test']) {
    const sk = await secret(k);
    if (!sk) continue;
    try {
      const r = await fetch('https://api.stripe.com/v1/invoices/' + encodeURIComponent(invoiceId), { headers: { Authorization: 'Bearer ' + sk } });
      if (r.status === 404) continue;
      const j = await r.json().catch(() => ({}));
      const pdf = String(j?.invoice_pdf || '');
      return /^https:\/\/[a-z0-9.-]*\.?stripe\.com\//.test(pdf) ? pdf : null;
    } catch { return null; }
  }
  return null;
}

function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'accountant', status, counts: { fn: 'reveal_invoice', ...counts },
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break invoice delivery */ }
  };
}

Deno.serve(observe('reveal_invoice', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const body = await req.json().catch(() => ({}));
    const qid = String(body.quote_id || '');
    const res = await resolveInvoice({
      customerIdByEmail: async (e) => { const { data } = await admin.from('customers').select('id').eq('email', e).maybeSingle(); return data?.id ? String(data.id) : null; },
      saleByQuote: async (q) => { const { data } = await admin.from('transactions').select('id,customer_id,stripe_invoice_id,stripe_invoice_number,doc_path').eq('quote_id', q).maybeSingle(); return data ? { ...data, id: String(data.id) } : null; },
      stripeInvoicePdf,
      signedStoredCopy: (p) => signedDoc('finance-docs', p, 3600),
    }, user.email, qid);
    if (!('fallback' in res)) {
      if (res.status !== 200) await logRun('error', { quote_id: qid, status: res.status }, 'invoice refused: ' + (res.body as { error: string }).error);
      else await logRun('ok', { quote_id: qid, source: (res.body as { source: string }).source }, '');
      return J(res.body, res.status);
    }

    // ---- FALLBACK: the QuotesDone receipt, for a sale Stripe did not invoice -------------------
    const { data: tx } = await admin.from('transactions').select('id,quote_id,inquiry_id,reveal_fee,processing_fee,total_charged,payment_ref,revealed_at').eq('id', res.sale.id).maybeSingle();
    if (!tx) return J({ error: 'No paid reveal found for this quote' }, 404);
    const { data: cust } = await admin.from('customers').select('id,email,full_name').eq('email', user.email.toLowerCase()).maybeSingle();
    const { data: cached } = await admin.from('reveal_invoices').select('bucket,path,invoice_no').eq('transaction_id', tx.id).maybeSingle();
    if (cached?.path) { const url = await signedDoc(cached.bucket, cached.path); if (url) { await logRun('ok', { quote_id: qid, cached: true, invoice_no: cached.invoice_no }, ''); return J({ ok: true, url, invoice_no: cached.invoice_no, cached: true }); } }
    const { data: inq } = await admin.from('inquiries').select('summary,category,emirate').eq('id', tx.inquiry_id).maybeSingle();
    // NO VAT, NO TRN (founder, 14 Sep 2026: "our company is not vat registered so for our reveal fee
    // there is no vat"). The branch that back-calculated 5% VAT when company_trn was set is removed.
    const fee = Number(tx.reveal_fee || 0);
    const processing = Number(tx.processing_fee || 0);
    const total = tx.total_charged != null ? Number(tx.total_charged) : fee + processing;
    const invNo = 'QD-INV-' + String(tx.id).replace(/-/g, '').slice(0, 8).toUpperCase();
    const inqRef = 'QD-' + String(tx.inquiry_id || '').replace(/-/g, '').slice(0, 8).toUpperCase();
    const dateStr = new Date(tx.revealed_at || Date.now()).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    const billTo = esc(cust?.full_name ? (cust.full_name + ' (' + cust.email + ')') : (cust?.email || user.email));
    const desc = 'Reveal fee — ' + esc(inq?.summary || (inq?.category || 'service request')) + ' (Ref ' + inqRef + ')';
    const title = 'Payment Receipt';
    const rows = [
      '<tr><th>Invoice No.</th><td>' + invNo + '</td><th>Date</th><td>' + dateStr + '</td></tr>',
      '<tr><th>Billed to</th><td>' + billTo + '</td><th>Payment method</th><td>Card (Stripe)</td></tr>',
      '<tr><th>Payment reference</th><td>' + esc(String(tx.payment_ref || '')) + '</td><th>Status</th><td>Paid</td></tr>'
    ].join('');
    const lines = '<tr><td>' + desc + '</td><td style="text-align:right">' + money(fee) + '</td></tr>'
      + (processing > 0 ? '<tr><td>Card processing (Stripe)</td><td style="text-align:right">' + money(processing) + '</td></tr>' : '');
    const body_html =
      '<table><tbody>' + rows + '</tbody></table>' +
      '<h2>Details</h2>' +
      '<table><thead><tr><th>Description</th><th style="text-align:right">Amount</th></tr></thead><tbody>' + lines + '</tbody></table>' +
      '<table style="width:55%;margin-left:auto"><tbody><tr><th>Total paid</th><td><b>' + money(total) + '</b></td></tr></tbody></table>' +
      '<p>QuotesDone Technologies is not registered for VAT; no VAT has been charged on this amount.</p>' +
      '<p>This is the QuotesDone facilitation fee for revealing the selected supplier’s contact details. The amount payable to the supplier for the works is agreed separately and directly between the customer and the supplier.</p>';
    const inbound = await secret('cred_fn_reveal_invoice');
    const pr = await fetch(URL_ + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: inbound, title, body_html, name: invNo, lang: 'en', options: { letterhead: true, sign: true, stamp: true } }) });
    const pj = await pr.json();
    if (!pj?.ok || !pj.path) { await logRun('error', { quote_id: qid, invoice_no: invNo }, 'pdf_native failed: ' + String(pj?.error || pj?.detail || '').slice(0, 200)); return J({ error: 'pdf_failed', detail: pj?.error || pj?.detail || '' }, 502); }
    const bucket = pj.bucket || 'agent-docs';
    try { await admin.from('reveal_invoices').upsert({ transaction_id: tx.id, invoice_no: invNo, bucket, path: pj.path, created_at: new Date().toISOString() }, { onConflict: 'transaction_id' }); } catch (_e) { /* */ }
    const url = pj.url || await signedDoc(bucket, pj.path);
    await logRun('ok', { quote_id: qid, invoice_no: invNo, cached: false, source: 'receipt' }, '');
    return J({ ok: true, url, invoice_no: invNo, source: 'receipt' });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
