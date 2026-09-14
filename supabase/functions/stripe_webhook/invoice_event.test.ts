// Run: deno test --node-modules-dir=none supabase/functions/stripe_webhook/invoice_event.test.ts
// The store below behaves like fn_transaction_attach_invoice: write-once on the invoice id, and the
// stored file fills in on a later call. Fixtures are ZZ DEMO shaped; nothing reaches Stripe.
import { assertEquals } from 'jsr:@std/assert@1';
import { handleRevealInvoiceEvent } from './invoice_event.ts';

function store() {
  const sale = { id: 'tx-zz-demo', quote_id: 'q-zz-demo', doc_path: null as string | null, stripe_invoice_id: null as string | null };
  const calls: string[] = [];
  return {
    sale, calls,
    deps: {
      findSale: async (qid: string) => (qid === sale.quote_id ? { ...sale } : null),
      capture: async (saleId: string, invoiceId: string) => {
        calls.push(invoiceId);
        if (sale.stripe_invoice_id && sale.stripe_invoice_id !== invoiceId) return; // write-once
        sale.stripe_invoice_id = invoiceId;
        sale.doc_path = 'invoices/stripe/2026-09-14/' + invoiceId + '_ZZDEMO-0001.pdf';
      },
    },
  };
}
const inv = (id: string, quote = 'q-zz-demo') => ({ id, object: 'invoice', metadata: { quote_id: quote } });

Deno.test('invoice.finalized files the invoice once; replays of both events are no-ops', async () => {
  const s = store();
  assertEquals((await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo1'))).action, 'captured');
  assertEquals((await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo1'))).action, 'already_filed');
  assertEquals((await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo1'))).action, 'already_filed'); // invoice.paid
  assertEquals(s.calls, ['in_zzdemo1']);
  assertEquals(s.sale.stripe_invoice_id, 'in_zzdemo1');
});

Deno.test('a reference without a stored PDF is repaired by the next invoice event', async () => {
  const s = store();
  s.sale.stripe_invoice_id = 'in_zzdemo2'; // checkout.session.completed attached the reference only
  assertEquals((await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo2'))).action, 'captured');
  assertEquals(s.sale.doc_path !== null, true);
});

Deno.test('a different invoice never overwrites the one the sale was billed under', async () => {
  const s = store();
  await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo3'));
  const r = await handleRevealInvoiceEvent(s.deps, inv('in_zzdemo_other'));
  assertEquals(r.action, 'other_invoice');
  assertEquals(s.sale.stripe_invoice_id, 'in_zzdemo3');
  assertEquals(s.calls, ['in_zzdemo3']);
});

Deno.test('not a reveal invoice, or no sale yet: nothing is captured', async () => {
  const s = store();
  assertEquals((await handleRevealInvoiceEvent(s.deps, { id: 'in_x', metadata: {} })).action, 'not_a_reveal');
  assertEquals((await handleRevealInvoiceEvent(s.deps, { id: 'ch_x', metadata: { quote_id: 'q-zz-demo' } })).action, 'not_a_reveal');
  assertEquals((await handleRevealInvoiceEvent(s.deps, inv('in_x', 'q-unknown'))).action, 'no_sale_yet');
  assertEquals(s.calls, []);
});
