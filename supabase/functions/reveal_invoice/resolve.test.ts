// Run: deno test --node-modules-dir=none supabase/functions/reveal_invoice/resolve.test.ts
// ZZ DEMO fixtures only. Proves ownership is decided before anything is rendered, and that the
// invoice and receipt bodies are template documents in both languages with lines that add up.
import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { resolveSale, type Sale } from './resolve.ts';
import { revealInvoiceDocument, revealReceiptDocument, type RevealSale } from '../_shared/reveal_fee_documents.ts';

const SALES: Record<string, Sale> = {
  'q-mine': { id: 'tx-1', customer_id: 'c-mine', stripe_invoice_id: 'in_zzdemo_mine', stripe_invoice_number: 'ZZDEMO-0001' },
  'q-theirs': { id: 'tx-2', customer_id: 'c-theirs', stripe_invoice_id: 'in_zzdemo_theirs', stripe_invoice_number: 'ZZDEMO-0002' },
};
const deps = {
  customerIdByEmail: async (e: string) => ({ 'zz.demo.buyer@example.invalid': 'c-mine' } as Record<string, string>)[e] ?? null,
  saleByQuote: async (q: string) => SALES[q] ?? null,
};

Deno.test("another customer's sale is refused; an unknown sign-in and a missing quote get nothing", async () => {
  assertEquals((await resolveSale(deps, 'ZZ.Demo.Buyer@example.invalid', 'q-theirs')).status, 403);
  assertEquals((await resolveSale(deps, 'nobody@example.invalid', 'q-mine')).status, 403);
  assertEquals((await resolveSale(deps, 'zz.demo.buyer@example.invalid', 'q-none')).status, 404);
  const r = await resolveSale(deps, 'zz.demo.buyer@example.invalid', 'q-mine');
  assertEquals('sale' in r ? r.sale.id : null, 'tx-1');
});

const SALE: RevealSale = {
  tx_id: 'tx-1', invoice_no: 'ZZDEMO-0001', paid_at: '2026-09-21T09:33:20Z', reveal_fee: 777.6, processing_fee: 38.77, total_charged: 816.37,
  quote_amount: 25920, payment_ref: 'pi_zzdemo', customer: { name: 'ZZ DEMO Buyer', email: 'zz.demo.buyer@example.invalid', phone: null },
  request: { summary: 'ZZ DEMO gypsum ceilings', category: 'gypsum', ref: 'QD-ZZDEMO01' }, card: { brand: 'visa', last4: '4242' },
};

Deno.test('the invoice is a template document, PAID, no TRN, carries Stripe\'s number and no other, EN and AR', () => {
  for (const lang of ['en', 'ar'] as const) {
    const d = revealInvoiceDocument(SALE, lang);
    const s = JSON.stringify(d);
    assertEquals(d.options, { letterhead: true, sign: true, stamp: true });
    assertEquals(!!d.cover, true);
    assertEquals(d.ref, 'ZZDEMO-0001');
    assertEquals(/TRN|Tax Invoice|فاتورة ضريبية/.test(s), false);
    assertEquals(/QD-INV-/.test(s), false);
    assertEquals(s.includes(lang === 'ar' ? 'مدفوعة' : 'PAID'), true);
    assertEquals(s.includes(lang === 'ar' ? '816.37 درهم' : 'AED 816.37'), true);
    assertEquals(s.includes(lang === 'ar' ? '0.00 درهم' : 'AED 0.00'), true); // balance due
    if (lang === 'ar') assertEquals(/Invoice|Receipt|Paid|Total/.test(s.replace(/"(name|title)":"[^"]*"/g, '')), false);
  }
});

Deno.test('the receipt cites the invoice and makes no number of its own, EN and AR', () => {
  for (const lang of ['en', 'ar'] as const) {
    const d = revealReceiptDocument(SALE, lang);
    assertEquals(d.ref, 'ZZDEMO-0001');
    assertEquals(JSON.stringify(d).includes(lang === 'ar' ? 'ليس فاتورة ثانية' : 'not a second invoice'), true);
  }
  const old = revealReceiptDocument({ ...SALE, invoice_no: null }, 'en');
  assertEquals(old.ref, 'pi_zzdemo');
});

Deno.test('lines that do not add up to what was charged are refused, not printed', () => {
  assertThrows(() => revealInvoiceDocument({ ...SALE, total_charged: 778 }, 'en'));
});
