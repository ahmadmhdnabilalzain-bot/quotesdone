import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { receiptCitation, resolveInvoice } from './resolve.ts';
import { registeredLocale } from '../_shared/registered_locale.ts';
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
    // The customer's registered language decides the document (founder, 14 Sep 2026).
    const ar = (await registeredLocale(admin, { role: 'customer', email: user.email })) === 'ar';
    const res = await resolveInvoice({
      preferReceipt: ar,
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
    // A cached receipt is reused only in the language it was made in: the Arabic copy carries -AR in its name.
    if (cached?.path && String(cached.path).includes('-AR') === ar) { const url = await signedDoc(cached.bucket, cached.path); if (url) { await logRun('ok', { quote_id: qid, cached: true, invoice_no: cached.invoice_no }, ''); return J({ ok: true, url, invoice_no: cached.invoice_no, cached: true }); } }
    const { data: inq } = await admin.from('inquiries').select('summary,category,emirate,rfq_no').eq('id', tx.inquiry_id).maybeSingle();
    // NO VAT, NO TRN (founder, 14 Sep 2026: "our company is not vat registered so for our reveal fee
    // there is no vat"). The branch that back-calculated 5% VAT when company_trn was set is removed.
    const fee = Number(tx.reveal_fee || 0);
    const processing = Number(tx.processing_fee || 0);
    const total = tx.total_charged != null ? Number(tx.total_charged) : fee + processing;
    // A receipt, not a second invoice: it cites Stripe's invoice number and makes none of its own.
    const cite = receiptCitation(res.sale);
    const invNo = cite.invoiceNo;
    // The job number (inquiries.rfq_no), the same one both portals and the quotation PDF print (21 Sep 2026).
    const inqRef = 'QD-' + (inq?.rfq_no != null ? String(inq.rfq_no) : String(tx.inquiry_id || '').replace(/-/g, '').slice(0, 8).toUpperCase());
    // ONE LANGUAGE PER RECEIPT: the customer's registered one (founder, 14 Sep 2026).
    const T = (en: string, arText: string) => ar ? arText : en;
    const dateStr = new Date(tx.revealed_at || Date.now()).toLocaleDateString(ar ? 'ar-AE' : 'en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
    const billTo = esc(cust?.full_name ? (cust.full_name + ' (' + cust.email + ')') : (cust?.email || user.email));
    const desc = T('Reveal fee — ', 'رسوم الكشف — ') + esc(inq?.summary || (inq?.category || T('service request', 'طلب خدمة'))) + ' (' + T('Ref ', 'المرجع ') + inqRef + ')';
    const title = T('Payment Receipt', 'إيصال دفع');
    const end = ar ? 'left' : 'right';
    const rows = [
      '<tr><th>' + T('Stripe invoice No.', 'رقم فاتورة Stripe') + '</th><td>' + esc(invNo || '—') + '</td><th>' + T('Date', 'التاريخ') + '</th><td>' + dateStr + '</td></tr>',
      '<tr><th>' + T('Billed to', 'صادر إلى') + '</th><td>' + billTo + '</td><th>' + T('Payment method', 'طريقة الدفع') + '</th><td>' + T('Card (Stripe)', 'بطاقة (Stripe)') + '</td></tr>',
      '<tr><th>' + T('Payment reference', 'مرجع الدفع') + '</th><td>' + esc(String(tx.payment_ref || '')) + '</td><th>' + T('Status', 'الحالة') + '</th><td>' + T('Paid', 'مدفوع') + '</td></tr>'
    ].join('');
    const lines = '<tr><td>' + desc + '</td><td style="text-align:' + end + '">' + money(fee) + '</td></tr>'
      + (processing > 0 ? '<tr><td>' + T('Card processing (Stripe)', 'رسوم معالجة البطاقة (Stripe)') + '</td><td style="text-align:' + end + '">' + money(processing) + '</td></tr>' : '');
    const body_html =
      '<table><tbody>' + rows + '</tbody></table>' +
      '<h2>' + T('Details', 'التفاصيل') + '</h2>' +
      '<table><thead><tr><th>' + T('Description', 'الوصف') + '</th><th style="text-align:' + end + '">' + T('Amount', 'المبلغ') + '</th></tr></thead><tbody>' + lines + '</tbody></table>' +
      '<table style="width:55%;margin-' + (ar ? 'right' : 'left') + ':auto"><tbody><tr><th>' + T('Total paid', 'إجمالي المدفوع') + '</th><td><b>' + money(total) + '</b></td></tr></tbody></table>' +
      (invNo ? '<p>' + T('This receipt confirms payment of the Stripe invoice numbered above. It is not a second invoice.', 'يؤكد هذا الإيصال سداد فاتورة Stripe المذكور رقمها أعلاه، وهو ليس فاتورة ثانية.') + '</p>' : '') +
      '<p>' + T('QuotesDone Technologies is not registered for VAT; no VAT has been charged on this amount.', 'QuotesDone غير مسجّلة لضريبة القيمة المضافة، ولم تُحتسب أي ضريبة على هذا المبلغ.') + '</p>' +
      '<p>' + T('This is the QuotesDone facilitation fee for revealing the selected supplier’s contact details. The amount payable to the supplier for the works is agreed separately and directly between the customer and the supplier.', 'هذه رسوم تسهيل من QuotesDone للكشف عن بيانات التواصل مع المورّد المختار. أمّا المبلغ المستحق للمورّد عن الأعمال فيُتفق عليه مباشرة وبشكل منفصل بين العميل والمورّد.') + '</p>';
    const inbound = await secret('cred_fn_reveal_invoice');
    const pr = await fetch(URL_ + '/functions/v1/pdf_native', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: inbound, title, body_html, name: cite.fileName + (ar ? '-AR' : ''), lang: ar ? 'ar' : 'en', options: { letterhead: true, sign: true, stamp: true } }) });
    const pj = await pr.json();
    if (!pj?.ok || !pj.path) { await logRun('error', { quote_id: qid, invoice_no: invNo }, 'pdf_native failed: ' + String(pj?.error || pj?.detail || '').slice(0, 200)); return J({ error: 'pdf_failed', detail: pj?.error || pj?.detail || '' }, 502); }
    const bucket = pj.bucket || 'agent-docs';
    try { await admin.from('reveal_invoices').upsert({ transaction_id: tx.id, invoice_no: invNo, bucket, path: pj.path, created_at: new Date().toISOString() }, { onConflict: 'transaction_id' }); } catch (_e) { /* */ }
    const url = pj.url || await signedDoc(bucket, pj.path);
    await logRun('ok', { quote_id: qid, invoice_no: invNo, cached: false, source: 'receipt' }, '');
    return J({ ok: true, url, invoice_no: invNo, source: 'receipt' });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
