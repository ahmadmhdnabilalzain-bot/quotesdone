// Run: deno test --no-lock --node-modules-dir=none supabase/functions/_shared/reveal_args.test.ts
// The webhook's two doors into the one sale insert, run through recordRevealSale against an in-memory table that,
// like public.transactions, refuses a second row for one quote_id (review of #1835).
// deno-lint-ignore-file no-explicit-any
import { assertEquals } from 'jsr:@std/assert@1';
import { checkoutSaleArgs, elementSaleArgs } from './reveal_args.ts';
import { recordRevealSale } from './reveal_sale.ts';

function table() {
  const rows: any[] = []; const findings: string[] = [];
  const tick = () => new Promise((r) => setTimeout(r, 1));
  const from = (t: string): any => {
    const f: Record<string, unknown> = {};
    const c: any = {
      select: () => c, is: () => c,
      eq: (k: string, v: unknown) => { f[k] = v; return c; },
      maybeSingle: async () => {
        await tick();
        if (t === 'transactions') return { data: rows.find((r) => Object.entries(f).every(([k, v]) => r[k] === v)) ?? null };
        if (t === 'quotes') return { data: { id: f.id, inquiry_id: 'i1', supplier_id: 7, quote_amount: 12345.67 } };
        if (t === 'inquiries') return { data: { customer_id: 'c1' } };
        return { data: { refund_window_working_days: 3 } };
      },
      update: () => c,
      insert: (v: any) => ({ select: () => ({ single: async () => {
        await tick();
        if (rows.some((r) => r.quote_id === v.quote_id)) return { data: null, error: { message: 'duplicate key value violates unique constraint "transactions_quote_id_uidx"' } };
        const row = { id: 'tx' + (rows.length + 1), ...v }; rows.push(row); return { data: { id: row.id }, error: null };
      } }) }),
    };
    return c;
  };
  return { rows, findings, from, rpc: async (fn: string, p: any) => { if (fn === 'fn_it_engineer_finding_upsert') findings.push(p.p_issue_key); return { data: '2026-11-10T00:00:00Z' }; } };
}

const session = (pi: string | null, invoice: string | null) => ({
  id: 'cs_test_q1', payment_status: 'paid', amount_total: 37037, payment_intent: pi, invoice,
  metadata: { quote_id: 'q1', customer_id: 'c1', reveal_fee: '370.37', processing_fee: '0', total_charged: '370.37' },
});

Deno.test('checkout.session.completed twice at once: one sale, both answers are that sale, nothing flagged', async () => {
  const db = table();
  const s = session('pi_one', 'in_one');
  const [a, b] = await Promise.all([recordRevealSale(db, checkoutSaleArgs(s)), recordRevealSale(db, checkoutSaleArgs(s))]);
  assertEquals(db.rows.length, 1);
  assertEquals(['error' in a, 'error' in b], [false, false]);
  assertEquals((a as any).id, (b as any).id);
  assertEquals(db.findings, []);
  assertEquals([db.rows[0].payment_ref, db.rows[0].total_charged, db.rows[0].reveal_fee], ['pi_one', 370.37, 370.37]);
});

Deno.test('a session without a PaymentIntent and the same sale under its pi are one sale, in either order', async () => {
  for (const order of [['cs', 'pi'], ['pi', 'cs']]) {
    const db = table();
    for (const k of order) await recordRevealSale(db, checkoutSaleArgs(session(k === 'pi' ? 'pi_one' : null, 'in_one')));
    assertEquals([db.rows.length, db.findings], [1, []], order.join(' then '));
  }
});

Deno.test('the element invoice.paid never records the invoice id as the payment, and never flags the only payment', async () => {
  const inv = { id: 'in_one', amount_paid: 100000, metadata: { quote_id: 'q1', customer_id: 'c1', base_fee: '1000', processing_fee: '0', flow: 'element' } };
  assertEquals(elementSaleArgs(inv, ''), null);        // PaymentIntent unreadable: the webhook answers 500, Stripe retries
  assertEquals(elementSaleArgs(inv, 'in_one'), null);
  // element_pay recorded pi_one under in_one; the webhook's invoice.paid then arrives with the same pair.
  const db = table();
  await recordRevealSale(db, elementSaleArgs(inv, 'pi_one')!);
  const again: any = await recordRevealSale(db, elementSaleArgs(inv, 'pi_one')!);
  assertEquals([db.rows.length, again.other_payment, db.findings], [1, undefined, []]);
});

Deno.test('a genuinely second PaymentIntent for the quote is still flagged once', async () => {
  const db = table();
  await recordRevealSale(db, checkoutSaleArgs(session('pi_one', 'in_one')));
  const second: any = await recordRevealSale(db, checkoutSaleArgs(session('pi_two', 'in_two')));
  assertEquals([db.rows.length, second.other_payment, db.findings], [1, 'pi_two', ['reveal:second_payment:pi_two']]);
});
