import { siteCors } from '../_shared/site_origins.ts';
// refund_flow - the customer side of the unresponsive-supplier escalation.
//
//   reveal paid -> 1 WORKING DAY -> customer may press "Notify supplier"
//   -> ONE email, supplier addressed, customer + management cc'd, one thread
//   -> 3 WORKING DAYS -> founder calls -> only then may a refund be approved
//
// Deliberately a separate function rather than new actions inside customer_api: that file is 64KB
// and every byte would have to be redeployed to add two endpoints. Auth is replicated exactly
// (Bearer JWT -> auth.getUser -> customers row), so it behaves identically to customer_api.
//
// All timing lives in Postgres (fn_refund_state / fn_notify_supplier / fn_add_working_days). Those
// resolve every working-day count through the single fn_is_working_day rule (Asia/Dubai, honours
// public_holidays), so this function computes no dates itself and the whole ladder shares one
// implementation of "working days".
//
// v2: accepts quote_id as well as transaction_id. customer_api.my_inquiries resolves the
//     transaction internally but does NOT expose transaction_id on the quote it returns, so the
//     portal only ever holds a quote id. Resolving here avoids redeploying 64KB for one field.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

Deno.serve(siteCors(observe('refund_flow', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const auth = req.headers.get('Authorization') || '';
    const jwt = auth.replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    const { data: cust } = await admin.from('customers').select('id').eq('email', email).maybeSingle();
    if (!cust) return J({ error: 'no_customer' }, 403);

    const body = await req.json().catch(() => ({} as any));
    const action = String(body.action || 'state');

    if (action === 'list') {
      const { data: txs } = await admin.from('transactions')
        .select('id, inquiry_id, quote_id, revealed_at')
        .eq('customer_id', cust.id)
        .not('revealed_at', 'is', null)
        .order('revealed_at', { ascending: false })
        .limit(50);
      const out: any[] = [];
      for (const t of txs || []) {
        const { data: st } = await admin.rpc('fn_refund_state', { p_transaction: t.id });
        out.push({ transaction_id: t.id, inquiry_id: t.inquiry_id, quote_id: t.quote_id, ...(st || {}) });
      }
      return J({ ok: true, reveals: out });
    }

    // Accept either identifier. The portal holds a quote id; internal callers hold a transaction id.
    let txId = String(body.transaction_id || '');
    const quoteId = String(body.quote_id || '');
    if (!txId && !quoteId) return J({ error: 'transaction_id_or_quote_id_required' }, 400);

    if (!txId) {
      const { data: byQuote } = await admin.from('transactions')
        .select('id').eq('quote_id', quoteId).eq('customer_id', cust.id)
        .order('revealed_at', { ascending: false }).limit(1).maybeSingle();
      // No transaction means this quote was never revealed by this customer - nothing to escalate.
      if (!byQuote) return J({ ok: true, state: 'not_revealed', can_notify: false, refund_approvable: false });
      txId = String(byQuote.id);
    } else {
      // OWNERSHIP: a customer may only ever see or act on their own reveal. Checked here rather
      // than inside the SQL functions so those stay usable by the founder/admin side too.
      const { data: owned } = await admin.from('transactions')
        .select('id').eq('id', txId).eq('customer_id', cust.id).maybeSingle();
      if (!owned) return J({ error: 'not_found' }, 404);
    }

    if (action === 'state') {
      const { data: st, error } = await admin.rpc('fn_refund_state', { p_transaction: txId });
      if (error) return J({ error: 'state_failed', detail: error.message }, 500);
      return J({ ok: true, ...(st || {}) });
    }

    if (action === 'notify') {
      // fn_notify_supplier re-checks the working-day gate itself and is idempotent, so a double
      // click or a stale button cannot send twice or fire early.
      const { data: res, error } = await admin.rpc('fn_notify_supplier', { p_transaction: txId, p_actor: 'customer' });
      if (error) return J({ error: 'notify_failed', detail: error.message }, 500);
      return J(res);
    }

    return J({ error: 'unknown_action', allowed: ['list', 'state', 'notify'] }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
})));
