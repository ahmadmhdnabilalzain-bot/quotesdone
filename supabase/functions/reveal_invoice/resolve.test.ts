// Run: deno test --node-modules-dir=none supabase/functions/reveal_invoice/resolve.test.ts
// ZZ DEMO fixtures only. Proves ownership is decided before anything is rendered, and that the
// invoice and receipt bodies are template documents in both languages with lines that add up.
import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { resolveSale, type Sale } from './resolve.ts';
import { NOT_PAID, paymentState, revealInvoiceDocument, revealReceiptDocument, type RevealSale } from '../_shared/reveal_fee_documents.ts';

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
  request: { summary: 'ZZ DEMO gypsum ceilings', category: 'gypsum', ref: 'QD-ZZDEMO01' }, card: { brand: 'visa', last4: '4242' }, refund: null,
};

const TX = { fee_status: 'paid', revealed_at: '2026-09-21T09:33:20Z', refund_status: null, refund_amount_aed: null, refund_confirmed_at: null, refund_resolved_at: null };

Deno.test('state (a) paid, not refunded: PAID documents, and a requested/approved/failed refund changes nothing', () => {
  const rows = [{ status: 'requested', amount_fils: 81637, settled_at: null }, { status: 'approved', amount_fils: 81637, settled_at: null }, { status: 'failed', amount_fils: 81637, settled_at: null }];
  assertEquals(paymentState(TX, rows), { state: 'paid', refund: null });
  assertEquals(paymentState({ ...TX, refund_status: 'requested' }, []), { state: 'paid', refund: null });
});

Deno.test('state (b) refunded: the invoice still shows it was paid, plus REFUNDED with amount and date; partial shows the net', () => {
  const full = paymentState(TX, [{ status: 'succeeded', amount_fils: 81637, settled_at: '2026-09-25T10:00:00Z' }]);
  assertEquals(full, { state: 'paid', refund: { amount: 816.37, date: '2026-09-25T10:00:00Z' } });
  const fromTx = paymentState({ ...TX, refund_status: 'refunded', refund_amount_aed: 816.37, refund_confirmed_at: '2026-09-26T08:00:00Z' }, []);
  assertEquals(fromTx, { state: 'paid', refund: { amount: 816.37, date: '2026-09-26T08:00:00Z' } });
  for (const lang of ['en', 'ar'] as const) {
    const s = JSON.stringify(revealInvoiceDocument({ ...SALE, refund: { amount: 816.37, date: '2026-09-25T10:00:00Z' } }, lang));
    assertEquals(s.includes(lang === 'ar' ? '"مستردّة"' : '"REFUNDED"'), true);
    assertEquals(s.includes(lang === 'ar' ? '25 سبتمبر 2026' : '25 September 2026'), true);
    assertEquals(s.includes(lang === 'ar' ? 'المدفوع بتاريخ' : 'Paid on'), true); // it was paid
    const r = JSON.stringify(revealReceiptDocument({ ...SALE, refund: { amount: 816.37, date: '2026-09-25T10:00:00Z' } }, lang));
    assertEquals(r.includes(lang === 'ar' ? '"مستردّة"' : '"REFUNDED"'), true);
  }
  const part = paymentState(TX, [{ status: 'succeeded', amount_fils: 38777, settled_at: '2026-09-25T10:00:00Z' }]);
  const doc = JSON.stringify(revealInvoiceDocument({ ...SALE, refund: part.state === 'paid' ? part.refund : null }, 'en'));
  assertEquals(doc.includes('"PART REFUNDED"'), true);
  assertEquals(doc.includes('AED 428.60'), true); // 816.37 - 387.77
  assertEquals(doc.includes('"REFUNDED"'), false);
});

Deno.test('state (c) not paid / pending / failed: no document, a readable EN + AR refusal', () => {
  for (const fee_status of [null, 'pending', 'failed', 'unpaid', 'requires_payment_method']) assertEquals(paymentState({ ...TX, fee_status }, []).state, 'not_paid');
  assertEquals(paymentState({ ...TX, revealed_at: null }, []).state, 'not_paid');
  assertEquals(NOT_PAID.code, 'payment_not_settled');
  assertEquals(/[؀-ۿ]/.test(NOT_PAID.ar) && /not been completed/.test(NOT_PAID.en), true);
});

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

// OUR NUMBER AND THE WINDOW'S END (accountant, 13 Nov 2026, ruling 1671 / ledger 1685): the invoice and the receipt print
// QuotesDone's own invoice number, Stripe's only as a reference, and the date the refund window ends, in both languages.
Deno.test('our invoice number is the document number, Stripe\'s a reference, and the refund window end is printed (EN + AR)', () => {
  const s: RevealSale = { ...SALE, invoice_no: 'QD-INV-000001', stripe_invoice_no: 'PQZAIUL8-0001', refund_window_ends: '2026-09-28T09:30:20Z' };
  for (const lang of ['en', 'ar'] as const) {
    for (const doc of [revealInvoiceDocument(s, lang), revealReceiptDocument(s, lang)]) {
      const text = JSON.stringify(doc);
      assertEquals(doc.ref, 'QD-INV-000001');
      assertEquals(text.includes(lang === 'en' ? 'Refund window ends' : 'تنتهي مهلة الاسترداد'), true, `${lang} ${doc.name}: no window line`);
      assertEquals(text.includes(lang === 'en' ? '28 September 2026' : '2026'), true, `${lang} ${doc.name}: no window date`);
    }
    assertEquals(JSON.stringify(revealInvoiceDocument(s, lang)).includes('PQZAIUL8-0001'), true, 'Stripe\'s number as a reference');
  }
  // a sale with no window recorded prints no invented date
  assertEquals(JSON.stringify(revealInvoiceDocument({ ...SALE }, 'en')).includes('Refund window ends'), false);
});
