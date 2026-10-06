import { siteCors } from '../_shared/site_origins.ts';
// refunds_api v6 — READ-ONLY views of reveal-fee refund cases. It moves no money.
// Actions: list_pending · list_recent.   'resolve' is RETIRED (410).
// Auth: __secret == inbound_secret OR admin-email JWT.
//
// v6, 14 SEP 2026 — ONE REFUND RAIL (accountant). Independent review of PR #640 found that 'resolve'
// still refunded straight off transactions.refund_status / refund_stripe_id, outside public.refunds,
// with Stripe Idempotency-Key qd_refund_<transaction id> and no guard but "prevStatus is refunded",
// while the customer's case is paid by accountant execute_refunds from public.refunds. Two rails, two
// keys: the same reveal could be refunded twice in Stripe. There is now one rail and it runs through
// public.refunds only:
//   customer asks (fn_refund_open_from_customer) or the day-5 ladder files it (fn_refund_request)
//   -> the CEO decides on the checklist (fn_ceo_refund_review -> ceo_approval + refund_decision_id)
//   -> the accountant pays it (accountant execute_refunds, key qd_refund_<transaction id>)
//   -> stripe_webhook / fn_refund_settle record what Stripe did.
// The table refuses a second live platform refund on one payment
// (refunds_one_live_platform_refund_per_payment, scripts/sql/a_customer_may_ask_at_any_time_and_the_ceo_decides_after_the_final_call.sql),
// whoever writes it. A founder who wants a refund reversed or paid does it through that rail; nothing
// here can reach Stripe any more, so the Control Mode gate that guarded this file's Stripe call went
// with the call. No caller existed: no page or function in the repository invoked 'resolve' (14 Sep).
//
// History kept for the reader: v4 (the caller told the truth when an update failed) and v5 (27 Jul
// 2026, the first time an approval actually called Stripe) both lived in 'resolve'. Their lessons
// live on in execute_refunds: money first, bookkeeping second, fail closed, one idempotency key.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | undefined> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
async function authed(req: Request, body: any) { if (body?.__secret && (await requireInternal(admin, body.__secret, 'refunds_api')).ok) return true; const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, ''); if (!jwt) return false; const { data: { user } } = await admin.auth.getUser(jwt); const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean); return !!(user?.email && allow.includes(user.email.toLowerCase())); }

const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'refunds_api', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break a read */ }
}

async function enrich(txs: any[]) {
  const sids = [...new Set(txs.map((t) => t.supplier_id).filter(Boolean))];
  const cids = [...new Set(txs.map((t) => t.customer_id).filter(Boolean))];
  const iids = [...new Set(txs.map((t) => t.inquiry_id).filter(Boolean))];
  const [{ data: leads }, { data: custs }, { data: inqs }] = await Promise.all([
    sids.length ? admin.from('leads').select('id,company_name,email,phone,rv_response_rate,rv_nonresponse_refunds,matching_blocked').in('id', sids) : Promise.resolve({ data: [] } as any),
    cids.length ? admin.from('customers').select('id,full_name,email,phone').in('id', cids) : Promise.resolve({ data: [] } as any),
    iids.length ? admin.from('inquiries').select('id,summary,category,emirate').in('id', iids) : Promise.resolve({ data: [] } as any),
  ]);
  // TYPED ON PURPOSE. The empty branches above are `Promise.resolve({ data: [] } as any)`, so when
  // a batch is empty `leads`/`custs`/`inqs` infer as never[]; the Maps then infer Map<never, never>,
  // .get() returns undefined, and `undefined || {}` is `{}` — which is why all twelve property reads
  // below were TS2339 "does not exist on type '{}'". The rows really are untyped PostgREST payloads,
  // so the honest annotation is any, not a fabricated row interface.
  const lm = new Map<number, any>((leads || []).map((l: any) => [Number(l.id), l]));
  const cm = new Map<string, any>((custs || []).map((c: any) => [String(c.id), c]));
  const im = new Map<string, any>((inqs || []).map((i: any) => [String(i.id), i]));
  return txs.map((t) => { const l = lm.get(Number(t.supplier_id)) || {}; const c = cm.get(String(t.customer_id)) || {}; const i = im.get(String(t.inquiry_id)) || {}; return {
    transaction_id: t.id, inquiry_id: t.inquiry_id, reveal_fee: t.reveal_fee, quote_amount: t.quote_amount,
    revealed_at: t.revealed_at, refund_requested_at: t.refund_requested_at, refund_status: t.refund_status, refund_note: t.refund_note,
    supplier_ack_at: t.supplier_ack_at,
    supplier: { id: t.supplier_id, company: l.company_name, email: l.email, phone: l.phone, response_rate: l.rv_response_rate, prior_nonresponse: l.rv_nonresponse_refunds, blocked: l.matching_blocked },
    customer: { name: c.full_name, email: c.email, phone: c.phone },
    inquiry: { summary: i.summary, category: i.category, emirate: i.emirate },
  }; });
}

Deno.serve(siteCors(observe('refunds_api', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    if (!(await authed(req, body))) { await logRun('error', { action: String(body?.action || '') }, 'forbidden: refund API called without valid secret or admin JWT'); return J({ error: 'forbidden' }, 403); }
    const action = String(body.action || '');

    if (action === 'list_pending') {
      const { data } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,quote_amount,revealed_at,refund_requested_at,refund_status,refund_note,supplier_ack_at').eq('refund_status', 'requested').order('refund_requested_at', { ascending: true }).limit(200);
      return J({ ok: true, rows: await enrich(data || []) });
    }
    if (action === 'list_recent') {
      const { data } = await admin.from('transactions').select('id,inquiry_id,supplier_id,customer_id,reveal_fee,quote_amount,revealed_at,refund_requested_at,refund_status,refund_note,supplier_ack_at').not('refund_status', 'is', null).order('refund_requested_at', { ascending: false }).limit(100);
      return J({ ok: true, rows: await enrich(data || []) });
    }
    if (action === 'resolve') {
      await logRun('error', { action, transaction_id: String(body.transaction_id || '') }, 'resolve is retired: refunds have one rail, public.refunds');
      return J({ ok: false, applied: false, error: 'retired',
        detail: 'Refunds have one rail: the case on public.refunds, decided by the CEO (fn_ceo_refund_review) and paid by the accountant (execute_refunds). This endpoint moves no money.' }, 410);
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
})));
