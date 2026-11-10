// A paid reveal is written WITH its Stripe invoice reference (run 5, tag 321d13ae: the sale read
// fee_status=paid, stripe_invoice_id NULL until the webhook landed). Fails if the insert drops it.
// deno-lint-ignore-file no-explicit-any
import { assertEquals } from 'jsr:@std/assert@1';
import { recordRevealSale } from './reveal_sale.ts';

function fakeAdmin(existing: any = null) {
  const writes: any[] = [];
  const chain = (table: string): any => {
    const c: any = {
      select: () => c, eq: () => c, is: () => c, neq: () => c, not: () => c,
      maybeSingle: async () => ({ data: table === 'transactions' ? existing
        : table === 'quotes' ? { id: 'q1', inquiry_id: 'i1', supplier_id: 7, quote_amount: 118500 }
        : table === 'inquiries' ? { customer_id: 'c1' } : { refund_window_working_days: 3 } }),
      update: (v: any) => { writes.push({ table, op: 'update', v }); return c; },
      insert: (v: any) => { writes.push({ table, op: 'insert', v }); return { select: () => ({ single: async () => ({ data: { id: 'tx1' }, error: null }) }) }; },
    };
    return c;
  };
  return { writes, from: chain, rpc: async () => ({ data: '2026-10-23T00:00:00Z' }) };
}
const args = { quoteId: 'q1', customerId: 'c1', baseFee: 3555, processingFee: 0, totalCharged: 3555, paymentRef: 'pi_x', invoiceId: 'in_1ABC' };

Deno.test('a new sale is inserted with its invoice reference', async () => {
  const a = fakeAdmin();
  await recordRevealSale(a, args);
  assertEquals(a.writes.find((w) => w.table === 'transactions' && w.op === 'insert').v.stripe_invoice_id, 'in_1ABC');
});

Deno.test('an existing sale without a reference gets it; one with a reference keeps it', async () => {
  const a = fakeAdmin({ id: 'tx1', stripe_invoice_id: null });
  await recordRevealSale(a, args);
  assertEquals(a.writes.filter((w) => w.table === 'transactions').map((w) => w.v), [{ stripe_invoice_id: 'in_1ABC' }]);
  const b = fakeAdmin({ id: 'tx1', stripe_invoice_id: 'in_OTHER' });
  await recordRevealSale(b, args);
  // the sale itself is never rewritten (the statuses a repeat delivery heals are the test below)
  assertEquals(b.writes.filter((w) => w.table === 'transactions').length, 0);
});

// 3 Nov 2026 (gap #7): two tabs, two succeeded PaymentIntents, one quote. The second came back "already recorded"
// and nothing named it; now it is other_payment and a finding keyed on that payment (before: no rpc, no flag).
Deno.test('a second, different payment for a recorded sale is flagged for refund, never merged', async () => {
  const a: any = fakeAdmin({ id: 'tx1', stripe_invoice_id: 'in_FIRST', payment_ref: 'pi_first' });
  const calls: any[] = []; a.rpc = async (fn: string, p: any) => { calls.push({ fn, p }); return { data: null }; };
  const r: any = await recordRevealSale(a, { ...args, paymentRef: 'pi_second', invoiceId: 'in_SECOND' });
  assertEquals([r.id, r.created, r.other_payment], ['tx1', false, 'pi_second']);
  assertEquals(calls.map((c) => [c.fn, c.p.p_issue_key]), [['fn_it_engineer_finding_upsert', 'reveal:second_payment:pi_second']]);
  assertEquals(a.writes.length, 0);
  // The SAME payment delivered again is the same sale: no flag.
  const b: any = fakeAdmin({ id: 'tx1', stripe_invoice_id: 'in_FIRST', payment_ref: 'pi_x' });
  const r2: any = await recordRevealSale(b, args);
  assertEquals([r2.created, r2.other_payment], [false, undefined]);
});

// A racing delivery loses the unique insert: it answers with the winner's row, not an error (webhook answered 500).
Deno.test('an insert that loses the race reads the winner and is not an error', async () => {
  let reads = 0;
  const a: any = fakeAdmin();
  const base = a.from;
  a.from = (t: string) => {
    const c = base(t);
    if (t === 'transactions') {
      c.maybeSingle = async () => (reads++ === 0 ? { data: null } : { data: { id: 'txW', payment_ref: 'pi_x' } });
      c.insert = () => ({ select: () => ({ single: async () => ({ data: null, error: { message: 'duplicate key value violates unique constraint "transactions_quote_id_uidx"' } }) }) });
    }
    return c;
  };
  const r: any = await recordRevealSale(a, args);
  assertEquals([r.id, r.created, r.error], ['txW', false, undefined]);
});

Deno.test('something that is not a Stripe invoice id is never stored', async () => {
  const a = fakeAdmin();
  await recordRevealSale(a, { ...args, invoiceId: 'pi_notaninvoice' });
  assertEquals(a.writes.find((w) => w.op === 'insert').v.stripe_invoice_id, null);
});

// Review of #1835: a path that could not read the PaymentIntent used to record the invoice id instead, and the real
// pi_ arriving next (or before) was flagged as a second payment to refund. Same invoice = same sale, both orders.
Deno.test('an invoice-id fallback and the real PaymentIntent of the same invoice are one sale, in either order', async () => {
  for (const [recorded, incoming] of [['in_1ABC', 'pi_x'], ['pi_x', 'in_1ABC']]) {
    const a: any = fakeAdmin({ id: 'tx1', stripe_invoice_id: 'in_1ABC', payment_ref: recorded });
    const calls: string[] = []; a.rpc = async (fn: string) => { calls.push(fn); return { data: null }; };
    const r: any = await recordRevealSale(a, { ...args, paymentRef: incoming, invoiceId: 'in_1ABC' });
    assertEquals([r.other_payment, calls], [undefined, []], `${recorded} recorded, ${incoming} arrives`);
  }
  // A checkout session id (cs_) is not a PaymentIntent either: never compared as one.
  const b: any = fakeAdmin({ id: 'tx1', stripe_invoice_id: null, payment_ref: 'cs_test_1' });
  const callsB: string[] = []; b.rpc = async (fn: string) => { callsB.push(fn); return { data: null }; };
  const rb: any = await recordRevealSale(b, { ...args, paymentRef: 'pi_x', invoiceId: '' });
  assertEquals([rb.other_payment, callsB], [undefined, []]);
});

// Customer-journey follow-up, 10 Nov 2026: the quote and the request were marked revealed BEFORE the sale was inserted, so
// a failed insert left a "revealed" quote with no sale behind it. Fails on origin/main (the two updates come first).
Deno.test('a sale that could not be written leaves the quote and the request as they were', async () => {
  const a: any = fakeAdmin();
  const base = a.from;
  a.from = (t: string) => {
    const c = base(t);
    if (t === 'transactions') c.insert = (v: any) => { a.writes.push({ table: t, op: 'insert', v }); return { select: () => ({ single: async () => ({ data: null, error: { message: 'connection reset' } }) }) }; };
    return c;
  };
  const r: any = await recordRevealSale(a, args);
  assertEquals(r.error, 'insert failed: connection reset');
  assertEquals(a.writes.filter((w: any) => w.op === 'update'), []);
});

Deno.test('the sale is written first, then the quote and the request read revealed', async () => {
  const a = fakeAdmin();
  await recordRevealSale(a, args);
  assertEquals(a.writes.map((w) => w.table + ':' + w.op), ['transactions:insert', 'quotes:update', 'inquiries:update']);
});

// pricing_config.refund_window_working_days is 5 on production; this path sent a deadline computed with `?? 3`, and
// trg_reveal_window computes it from the row when none is sent. Fails on origin/main (refund_deadline was sent).
Deno.test('the refund deadline is left to the database, which reads pricing_config', async () => {
  const a: any = fakeAdmin();
  const rpcs: string[] = []; a.rpc = async (fn: string) => { rpcs.push(fn); return { data: null }; };
  await recordRevealSale(a, args);
  const ins = a.writes.find((w: any) => w.op === 'insert').v;
  assertEquals(['refund_deadline' in ins, rpcs], [false, []]);
  const src = await Deno.readTextFile(new URL('./reveal_sale.ts', import.meta.url));
  assertEquals(/refund_window_working_days \?\? \d/.test(src), false, 'no hard-coded refund window');
});

Deno.test('the same sale delivered again writes the statuses its first delivery may not have', async () => {
  const a = fakeAdmin({ id: 'tx1', stripe_invoice_id: 'in_1ABC', payment_ref: 'pi_x' });
  const r: any = await recordRevealSale(a, args);
  assertEquals([r.id, r.created], ['tx1', false]);
  assertEquals(a.writes.map((w) => w.table + ':' + w.op), ['quotes:update', 'inquiries:update']);
});
