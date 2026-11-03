// A paid reveal is written WITH its Stripe invoice reference (run 5, tag 321d13ae: the sale read
// fee_status=paid, stripe_invoice_id NULL until the webhook landed). Fails if the insert drops it.
// deno-lint-ignore-file no-explicit-any
import { assertEquals } from 'jsr:@std/assert@1';
import { recordRevealSale } from './reveal_sale.ts';

function fakeAdmin(existing: any = null) {
  const writes: any[] = [];
  const chain = (table: string): any => {
    const c: any = {
      select: () => c, eq: () => c, is: () => c,
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
  assertEquals(b.writes.length, 0);
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
