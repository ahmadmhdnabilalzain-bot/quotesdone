// Run: deno test --node-modules-dir=none supabase/functions/reveal_invoice/resolve.test.ts
// ZZ DEMO fixtures only; the Stripe dependency is a recorder, so the test also proves WHEN it is asked.
import { assertEquals } from 'jsr:@std/assert@1';
import { receiptCitation, resolveInvoice, stripeInvoiceLink, type Sale } from './resolve.ts';

Deno.test('the customer opens the hosted invoice page (reads PAID), never the finalisation-time invoice_pdf when the page exists', () => {
  const inv = { hosted_invoice_url: 'https://invoice.stripe.com/i/acct_zz/test_zz?s=ap', invoice_pdf: 'https://pay.stripe.com/invoice/acct_zz/test_zz/pdf?s=ap' };
  assertEquals(stripeInvoiceLink(inv), inv.hosted_invoice_url);
  assertEquals(stripeInvoiceLink({ invoice_pdf: inv.invoice_pdf }), inv.invoice_pdf); // no hosted page: the PDF still opens
  assertEquals(stripeInvoiceLink({ hosted_invoice_url: 'https://evil.example/x', invoice_pdf: 'javascript:alert(1)' }), null);
  assertEquals(stripeInvoiceLink(null), null);
});

Deno.test('the receipt cites the Stripe invoice number and has no invoice number of its own', () => {
  const c = receiptCitation({ id: 'aaaabbbb-cccc-dddd-eeee-ffff00001111', stripe_invoice_number: 'ZZDEMO-0001' });
  assertEquals(c, { invoiceNo: 'ZZDEMO-0001', fileName: 'receipt-AAAABBBB' });
  const none = receiptCitation({ id: 'aaaabbbb-cccc', stripe_invoice_number: null });
  assertEquals(none.invoiceNo, null);
  assertEquals(/INV/.test(none.fileName + c.fileName), false);
});

const SALES: Record<string, Sale> = {
  'q-mine': { id: 'tx-1', customer_id: 'c-mine', stripe_invoice_id: 'in_zzdemo_mine', stripe_invoice_number: 'ZZDEMO-0001', doc_path: 'invoices/stripe/x.pdf' },
  'q-theirs': { id: 'tx-2', customer_id: 'c-theirs', stripe_invoice_id: 'in_zzdemo_theirs', stripe_invoice_number: 'ZZDEMO-0002', doc_path: 'invoices/stripe/y.pdf' },
  'q-old': { id: 'tx-3', customer_id: 'c-mine', stripe_invoice_id: null, stripe_invoice_number: null, doc_path: null },
};
function deps(stripeUp = true) {
  const asked: string[] = [];
  return {
    asked,
    d: {
      customerIdByEmail: async (e: string) => ({ 'zz.demo.buyer@example.invalid': 'c-mine', 'zz.demo.other@example.invalid': 'c-theirs' } as Record<string, string>)[e] ?? null,
      saleByQuote: async (q: string) => SALES[q] ?? null,
      stripeInvoicePdf: async (id: string) => { asked.push(id); return stripeUp ? 'https://pay.stripe.com/invoice/' + id + '/pdf' : null; },
      signedStoredCopy: async (p: string) => 'https://example.supabase.co/storage/v1/object/sign/finance-docs/' + p,
    },
  };
}

Deno.test("another customer's invoice is refused, and Stripe is never asked for it", async () => {
  const x = deps();
  const r = await resolveInvoice(x.d, 'ZZ.Demo.Buyer@example.invalid', 'q-theirs');
  assertEquals(r.status, 403);
  assertEquals(x.asked, []);
});

Deno.test('an Arabic-registered customer gets the receipt, never Stripe (no Arabic there), and only their own', async () => {
  const x = deps();
  const mine = await resolveInvoice({ ...x.d, preferReceipt: true }, 'zz.demo.buyer@example.invalid', 'q-mine');
  assertEquals('fallback' in mine && mine.fallback, true);
  assertEquals(x.asked, []);
  assertEquals((await resolveInvoice({ ...x.d, preferReceipt: true }, 'zz.demo.buyer@example.invalid', 'q-theirs')).status, 403);
});

Deno.test('an unknown sign-in gets no invoice', async () => {
  const x = deps();
  assertEquals((await resolveInvoice(x.d, 'nobody@example.invalid', 'q-mine')).status, 403);
  assertEquals(x.asked, []);
});

Deno.test('own invoice opens a FRESH Stripe PDF link', async () => {
  const x = deps();
  const r = await resolveInvoice(x.d, 'zz.demo.buyer@example.invalid', 'q-mine');
  assertEquals(r.status, 200);
  assertEquals('body' in r && 'url' in r.body ? r.body.url : null, 'https://pay.stripe.com/invoice/in_zzdemo_mine/pdf');
  assertEquals(x.asked, ['in_zzdemo_mine']);
});

Deno.test('Stripe unreachable: the stored copy of the same PDF is served', async () => {
  const x = deps(false);
  const r = await resolveInvoice(x.d, 'zz.demo.buyer@example.invalid', 'q-mine');
  assertEquals('body' in r && 'source' in r.body ? r.body.source : null, 'stored_copy');
});

Deno.test('no Stripe invoice on the sale falls back to the receipt; no quote is a 404', async () => {
  const x = deps();
  assertEquals('fallback' in (await resolveInvoice(x.d, 'zz.demo.buyer@example.invalid', 'q-old')), true);
  assertEquals((await resolveInvoice(x.d, 'zz.demo.buyer@example.invalid', 'q-none')).status, 404);
});
