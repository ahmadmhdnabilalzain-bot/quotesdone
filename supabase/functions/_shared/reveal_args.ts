// WHAT stripe_webhook HANDS recordRevealSale (accountant, 3 Nov 2026; review of #1835). Pure, so the two webhook
// doors into the one sale insert are tested with the recorder itself (_shared/reveal_args.test.ts).
// deno-lint-ignore-file no-explicit-any
import { paidAtFromUnix, type SaleArgs } from './reveal_sale.ts';

/** checkout.session.completed (paid): the hosted Checkout Session's reveal. */
export function checkoutSaleArgs(s: any): SaleArgs {
  const md = s?.metadata || {};
  const fee = Number(md.reveal_fee || (s?.amount_total ? s.amount_total / 100 : 0));
  // total_charged is what a refund returns (founder, 14 Sep 2026): everything the customer paid.
  const totalCharged = s?.amount_total ? s.amount_total / 100 : Number(md.total_charged || fee);
  const processing = md.processing_fee != null ? Number(md.processing_fee) : Math.round((totalCharged - fee) * 100) / 100;
  return { quoteId: String(md.quote_id || ''), customerId: md.customer_id || null, baseFee: fee, processingFee: processing,
    totalCharged, paymentRef: String(s?.payment_intent || s?.id || ''), invoiceId: String(s?.invoice || ''),
    // The session names no paid time (its `created` is when the page opened); recordStripeFee writes it from the charge.
    paidAt: null, livemode: s?.livemode === true };
}

/**
 * invoice.paid of a Payment Element reveal. null when the PaymentIntent behind the invoice could not be read: the
 * invoice id is NOT a payment reference (a refund is issued against the PaymentIntent, and recording in_... made the
 * real pi_ look like a second payment). The caller answers Stripe 500 so the event is delivered again.
 */
export function elementSaleArgs(inv: any, paymentIntent: string): SaleArgs | null {
  if (!/^pi_[A-Za-z0-9_]+$/.test(paymentIntent)) return null;
  const md = inv?.metadata || {};
  return { quoteId: String(md.quote_id || ''), customerId: md.customer_id || null, baseFee: Number(md.base_fee),
    processingFee: Number(md.processing_fee), totalCharged: Number(inv?.amount_paid) / 100, paymentRef: paymentIntent,
    invoiceId: String(inv?.id || ''), paidAt: paidAtFromUnix(inv?.status_transitions?.paid_at), livemode: inv?.livemode === true };
}
