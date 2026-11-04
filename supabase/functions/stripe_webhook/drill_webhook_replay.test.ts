// DRILL D4 (docs/release/qualification_matrix.md §5.1): a Stripe webhook delivered twice, out of
// order, late, and twice AT ONCE. Seat accountable: it_engineer (the drill); the money it guards is
// the accountant's. Offline, against the REAL stripe_webhook handler: the signature is the real v1
// scheme (HMAC-SHA256 over `${t}.${payload}`) with stub signing secrets, the database is a small
// stateful PostgREST that enforces transactions_quote_id_uidx the way production does
// (supabase/schema/full_schema/01_..._indexes.sql: UNIQUE (quote_id) WHERE quote_id IS NOT NULL), and
// api.stripe.com / pay.stripe.com are answered by the dispatcher below. Nothing reaches a network.
//
// What each case must show, in the matrix's terms:
//   safe      one transactions row, one reveal write per quote, one invoice attach, whatever the order
//   visible   every delivery leaves an agent_runs row under agent 'stripe_webhook' (the accountant's
//             run log), and no row cries "PAID BUT NOT RECORDED" for a sale that IS recorded
//   recovery  a late or early event needs no hand: Stripe's own retry, or the next event, completes it
//
// The known-bad control: a delivery signed with the wrong secret, and one whose signature timestamp is
// 11 minutes old, both write NOTHING; the positive control is the same event signed correctly, which
// does write. So a "zero writes" here cannot come from a stub that never sees the handler's calls.
//
// Run with the suite's flags (scripts/checks/run.mjs).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const LIVE_SECRET = 'whsec_zz_demo_live_0123456789abcdef';
const TEST_SECRET = 'whsec_zz_demo_test_0123456789abcdef';
const QUOTE = 'q-zz-demo-d4';
const INQUIRY = 'i-zz-demo-d4';
const PI = 'pi_zzdemod4';
const INVOICE = 'in_zzdemod4';

type Row = Record<string, unknown>;
type World = {
  stub: Stub; tx: Row[]; reveals: number; attaches: Row[]; settles: Row[]; runs: Row[]; stripe: string[];
  inserts: number;          // POST /transactions attempts, so the in-flight case can prove it really raced
  barrier: number;          // >0: the sale lookup waits until this many lookups are in flight (forces the race)
};

/** A stateful PostgREST: enough of it to hold one quote's sale, with the unique index production has. */
function world(): World {
  const w: World = { stub: {}, tx: [], reveals: 0, attaches: [], settles: [], runs: [], stripe: [], inserts: 0, barrier: 0 };
  const waiting: (() => void)[] = [];
  const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
  const rows: Record<string, Row[]> = {
    quotes: [{ id: QUOTE, inquiry_id: INQUIRY, supplier_id: 77, quote_amount: 1000 }],
    inquiries: [{ id: INQUIRY, customer_id: 'c-zz-demo-d4', summary: 'ZZ DEMO D4' }],
    pricing_config: [{ id: 1, refund_window_working_days: 3 }],
    customers: [{ id: 'c-zz-demo-d4', is_demo: true }],
  };
  const match = (r: Row, u: URL) => {
    for (const [k, v] of u.searchParams) {
      if (['select', 'limit', 'order', 'offset', 'on_conflict', 'columns'].includes(k)) continue;
      if (v.startsWith('eq.') && String(r[k]) !== v.slice(3)) return false;
      if (v === 'is.null' && r[k] != null) return false;
    }
    return true;
  };
  w.stub = {
    secrets: { stripe_webhook_secret: LIVE_SECRET, stripe_webhook_secret_test: TEST_SECRET },
    handle: async (req, u) => {
      const m = u.pathname.match(/^\/rest\/v1\/([^/]+)$/);
      if (u.pathname.startsWith('/storage/v1/object/')) return J({ Key: u.pathname.slice('/storage/v1/object/'.length) });
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        const body = await req.clone().json().catch(() => ({}));
        if (rpc[1] === 'fn_inquiry_is_demo') return J(true);
        if (rpc[1] === 'fn_add_working_days') return J('2026-11-06T00:00:00Z');
        if (rpc[1] === 'fn_transaction_attach_invoice') {
          w.attaches.push(body);
          const t = w.tx.find((x) => x.id === body.p_transaction_id);
          if (t && (t.stripe_invoice_id == null || t.stripe_invoice_id === body.p_invoice?.id)) {   // write-once, as the routine
            t.stripe_invoice_id = body.p_invoice?.id; if (body.p_doc_path) t.doc_path = body.p_doc_path;
          }
          return J({ ok: true, state: t?.doc_path ? 'stored' : 'reference_only' });
        }
        if (rpc[1] === 'fn_refund_settle') { w.settles.push(body); return J({ ok: true, refund_id: 9 }); }
        return J(null);
      }
      if (!m) return undefined;
      const table = m[1];
      if (table === 'app_secrets') return undefined;            // the harness answers secrets
      if (table === 'agent_runs' && req.method === 'POST') { w.runs.push(await req.clone().json().catch(() => ({}))); return J([], 201); }
      if (table === 'notifications' && req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/2' } });
      const wantsObject = (req.headers.get('accept') || '').includes('vnd.pgrst.object');
      if (table === 'transactions') {
        if (req.method === 'GET') {
          const snapshot = w.tx.filter((r) => match(r, u));
          if (waiting.length + 1 < w.barrier) await new Promise<void>((r) => { waiting.push(r); setTimeout(r, 500); });
          else { w.barrier = 0; waiting.splice(0).forEach((r) => r()); }
          return J(snapshot);
        }
        if (req.method === 'POST') {
          w.inserts++;
          const body = await req.clone().json();
          if (body.quote_id != null && w.tx.some((r) => r.quote_id === body.quote_id)) {
            return J({ code: '23505', message: 'duplicate key value violates unique constraint "transactions_quote_id_uidx"', details: 'Key (quote_id)=(' + body.quote_id + ') already exists.', hint: null }, 409);
          }
          const row = { id: 'tx-' + (w.tx.length + 1), doc_path: null, stripe_invoice_id: null, ...body };
          w.tx.push(row);
          return wantsObject ? J({ id: row.id }, 201) : J([{ id: row.id }], 201);
        }
        if (req.method === 'PATCH') {
          const body = await req.clone().json();
          for (const r of w.tx.filter((x) => match(x, u))) Object.assign(r, body);
          return J([]);
        }
      }
      if (table === 'quotes' && req.method === 'PATCH') { const b = await req.clone().json(); if (b.status === 'revealed') w.reveals++; return J([]); }
      if (req.method === 'GET' && rows[table]) return J(rows[table].filter((r) => match(r, u)));
      return undefined;
    },
  };
  return w;
}

// api.stripe.com and the invoice PDF host, answered here (the shared harness gives {} to unknown hosts).
let current: World | null = null;
async function loaded() {
  const h = await loadFunction('stripe_webhook', () => import('./index.ts'));
  const g = globalThis as unknown as { __d4Wrapped?: boolean };
  if (!g.__d4Wrapped) {
    g.__d4Wrapped = true;
    const inner = globalThis.fetch;
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      const u = new URL(url);
      if (u.hostname === 'api.stripe.com' || u.hostname === 'pay.stripe.com') {
        current?.stripe.push(u.pathname + u.search);
        const J = (o: unknown) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
        if (u.hostname === 'pay.stripe.com') return new Response(new TextEncoder().encode('%PDF-1.4 zz demo invoice'), { status: 200, headers: { 'content-type': 'application/pdf' } });
        if (u.pathname.startsWith('/v1/payment_intents/')) return J({ id: PI, latest_charge: { balance_transaction: { fee: 120, fee_details: [] } } });
        if (u.pathname === '/v1/invoices/' + INVOICE) return J({ id: INVOICE, number: 'ZZDEMO-0004', invoice_pdf: 'https://pay.stripe.com/invoice/' + INVOICE + '/pdf' });
        if (u.pathname === '/v1/refunds') return J({ data: [{ id: 're_zzdemod4', object: 'refund', amount: 3090, status: 'succeeded', payment_intent: PI, charge: 'ch_zzdemod4' }] });
        return J({});
      }
      return inner(input, init);
    }) as typeof fetch;
  }
  return h;
}

async function sign(payload: string, secret: string, t = Math.floor(Date.now() / 1000)) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(t + '.' + payload)));
  return `t=${t},v1=${[...mac].map((b) => b.toString(16).padStart(2, '0')).join('')}`;
}
async function delivery(event: Row, opts: { secret?: string; t?: number } = {}) {
  const payload = JSON.stringify(event);
  const secret = opts.secret ?? (event.livemode === true ? LIVE_SECRET : TEST_SECRET);
  return new Request('https://fn.invalid/stripe_webhook', {
    method: 'POST', headers: { 'content-type': 'application/json', 'Stripe-Signature': await sign(payload, secret, opts.t) }, body: payload,
  });
}
async function send(w: World, event: Row, opts: { secret?: string; t?: number } = {}) {
  current = w;
  const h = await loaded();
  return await invokeRequest(h, w.stub, await delivery(event, opts));
}

const completed = (id = 'evt_zzdemod4_completed', livemode = false): Row => ({
  id, object: 'event', livemode, type: 'checkout.session.completed',
  data: { object: { id: 'cs_zzdemod4', object: 'checkout.session', payment_status: 'paid', payment_intent: PI, amount_total: 3090, invoice: INVOICE,
    metadata: { quote_id: QUOTE, reveal_fee: '30', quote_amount: '1000', customer_id: 'c-zz-demo-d4' } } },
});
const invoicePaid = (): Row => ({
  id: 'evt_zzdemod4_invoice_paid', object: 'event', livemode: false, type: 'invoice.paid',
  data: { object: { id: INVOICE, object: 'invoice', amount_paid: 3090, metadata: { quote_id: QUOTE } } },
});
const refundCreated = (): Row => ({
  id: 'evt_zzdemod4_refund_created', object: 'event', livemode: true, type: 'refund.created',
  data: { object: { id: 're_zzdemod4', object: 'refund', amount: 3090, status: 'succeeded', payment_intent: PI, charge: 'ch_zzdemod4' } },
});
const chargeRefunded = (): Row => ({
  id: 'evt_zzdemod4_charge_refunded', object: 'event', livemode: true, type: 'charge.refunded',
  data: { object: { id: 'ch_zzdemod4', object: 'charge', payment_intent: PI, receipt_url: 'https://pay.stripe.com/receipts/zz' } },
});
const notRecorded = (w: World) => w.runs.filter((r) => r.agent === 'stripe_webhook' && /PAID BUT NOT RECORDED/.test(String(r.note || '')));

Deno.test('D4 positive control: one signed checkout.session.completed records one sale, one reveal and one invoice', async () => {
  const w = world();
  const r = await send(w, completed());
  assertEquals(r.status, 200);
  assertEquals(w.tx.length, 1, 'the sale is recorded');
  assertEquals(w.reveals, 1, 'the quote is revealed once');
  assertEquals(w.attaches.length, 1, 'the invoice is attached once');
  assert(String(w.tx[0].doc_path || '').startsWith('invoices/stripe/'), 'the invoice PDF is stored with the sale');
  assert(w.runs.some((x) => x.agent === 'stripe_webhook' && x.status === 'ok'), 'visible: an ok row in the accountant\'s run log');
});

Deno.test('D4 known-bad control: a wrong secret and an 11-minute-old signature are refused before any write', async () => {
  const w = world();
  const bad = await send(w, completed(), { secret: 'whsec_not_the_endpoint_secret_000000' });
  assertEquals(bad.status, 400);
  const late = await send(w, completed(), { t: Math.floor(Date.now() / 1000) - 660 });
  assertEquals(late.status, 400, 'a captured delivery replayed outside the 600 s window is refused');
  assertEquals(w.tx.length, 0); assertEquals(w.reveals, 0); assertEquals(w.attaches.length, 0);
  assertEquals(w.runs.filter((x) => /bad_signature/.test(String(x.note))).length, 2, 'visible: both refusals are logged');
  // Recovery with no hand: Stripe re-signs every retry with a fresh t, and that retry is accepted.
  const retry = await send(w, completed());
  assertEquals(retry.status, 200); assertEquals(w.tx.length, 1);
});

Deno.test('D4 duplicate: the same event delivered twice is one sale, one reveal, one invoice', async () => {
  const w = world();
  assertEquals((await send(w, completed())).status, 200);
  assertEquals((await send(w, completed())).status, 200);
  assertEquals(w.tx.length, 1, 'one transactions row');
  assertEquals(w.reveals, 1, 'one reveal write');
  assertEquals(w.attaches.length, 1, 'the second delivery does not re-file an invoice that is already stored');
  assert(w.runs.some((x) => /duplicate delivery ignored/.test(String(x.note))), 'visible: the duplicate is named');
  assertEquals(notRecorded(w).length, 0);
});

Deno.test('D4 duplicate in flight: two deliveries of one event at the same moment are one sale, one invoice and no false alarm', async () => {
  const w = world();
  current = w;
  const h = await loaded();
  const [ra, rb] = [await delivery(completed()), await delivery(completed())];   // both signed first, then sent together
  w.barrier = 2;   // both look for the sale before either records it: the race Stripe can produce on a retry storm
  const [a, b] = await Promise.all([invokeRequest(h, w.stub, ra), invokeRequest(h, w.stub, rb)]);
  assertEquals(w.inserts, 2, 'the race was real: both deliveries tried to record the sale');
  assertEquals(w.tx.length, 1, 'transactions_quote_id_uidx holds: one sale');
  // ONE INVOICE is a property of the sale, not a count of calls: the loser may also ask
  // fn_transaction_attach_invoice to file it (the re-delivery repair path), and that routine is
  // write-once on the invoice identity. What must hold is that only one invoice is ever named.
  assertEquals([...new Set(w.attaches.map((x) => (x.p_invoice as Row)?.id))], [INVOICE], 'only one invoice is ever attached');
  assertEquals(w.tx[0].stripe_invoice_id, INVOICE);
  // The loser of the race must not tell the accountant a recorded sale was lost.
  assertEquals(notRecorded(w).map((x) => x.note), [], 'no "PAID BUT NOT RECORDED" for a sale that is recorded');
  assertEquals([a.status, b.status], [200, 200], 'neither delivery is answered as a failure');
});

Deno.test('D4 out of order: invoice.paid before checkout.session.completed files the invoice exactly once', async () => {
  const w = world();
  const early = await send(w, invoicePaid());
  assertEquals(early.status, 200);
  assertEquals(w.tx.length, 0, 'an invoice event never creates a sale');
  assertEquals(w.attaches.length, 0);
  assert(w.runs.some((x) => (x.counts as Row)?.action === 'no_sale_yet'), 'visible: the early invoice is logged as no_sale_yet');
  await send(w, completed());
  assertEquals(w.tx.length, 1); assertEquals(w.attaches.length, 1, 'the sale files its own invoice when it lands');
  await send(w, invoicePaid());   // Stripe redelivers the invoice event later
  assertEquals(w.attaches.length, 1, 'already filed: nothing attached twice');
  assertEquals(w.reveals, 1);
});

Deno.test('D4 out of order: a refund before its charge, then the charge, then the refund again, settles on one refund id', async () => {
  const w = world();
  assertEquals((await send(w, refundCreated())).status, 200);
  assertEquals((await send(w, completed('evt_zzdemod4_completed_live', true))).status, 200);
  assertEquals((await send(w, chargeRefunded())).status, 200);
  assertEquals((await send(w, refundCreated())).status, 200);
  assertEquals(w.tx.length, 1, 'one sale');
  assertEquals(w.reveals, 1, 'one reveal');
  assertEquals(w.settles.length, 3, 'every refund delivery reaches fn_refund_settle (nothing dropped for arriving early)');
  // fn_refund_settle is idempotent on p_stripe_refund_id (scripts/sql/every_refund_approval_goes_through_
  // the_one_decision_and_the_second_seat.sql: `for update` on the id, "Duplicate delivery: same state twice"),
  // so the handler's half of the bargain is to hand it the SAME id every time, and the event id beside it.
  assertEquals([...new Set(w.settles.map((s) => s.p_stripe_refund_id))], ['re_zzdemod4']);
  assert(w.settles.every((s) => String(s.p_stripe_event_id || '').startsWith('evt_')), 'each settle carries its event id');
});

Deno.test('D4 an event type the handler does not act on (payment_intent.succeeded) writes no sale and no reveal', async () => {
  const w = world();
  const r = await send(w, { id: 'evt_zzdemod4_pi', object: 'event', livemode: false, type: 'payment_intent.succeeded',
    data: { object: { id: PI, object: 'payment_intent', metadata: { quote_id: QUOTE } } } });
  assertEquals(r.status, 200);
  assertEquals(w.tx.length, 0); assertEquals(w.reveals, 0); assertEquals(w.attaches.length, 0);
});
