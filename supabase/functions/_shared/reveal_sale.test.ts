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

Deno.test('something that is not a Stripe invoice id is never stored', async () => {
  const a = fakeAdmin();
  await recordRevealSale(a, { ...args, invoiceId: 'pi_notaninvoice' });
  assertEquals(a.writes.find((w) => w.op === 'insert').v.stripe_invoice_id, null);
});
