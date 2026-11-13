// RECORD A PAID REVEAL (14 Sep 2026, agent: accountant).
//
// The Payment Element reveal can be settled from three places: the pay action when the card needs
// nothing more, the settle action after 3-D Secure, and stripe_webhook's invoice.paid as the safety
// net. They all come here, so there is one insert, one refund deadline rule and one answer to "was
// this sale already recorded". transactions.quote_id is unique, so two of them racing produce one
// sale: the loser reads the winner's row.
// deno-lint-ignore-file no-explicit-any
export type SaleArgs = {
  quoteId: string; customerId: string | null; baseFee: number; processingFee: number;
  totalCharged: number; paymentRef: string;
  // The Stripe invoice (in_...) the reveal was billed under. REQUIRED: every caller holds it at the
  // moment of sale. Run 5 (tag 321d13ae, 18 Oct 2026) read the sale straight after element_pay and
  // found stripe_invoice_id NULL, because only stripe_webhook invoice.paid -> fn_transaction_attach_invoice
  // set it, seconds later; a paid reveal had no invoice in that gap. The webhook still files the
  // number and the PDF; this only makes the reference exist from the first write.
  invoiceId: string;
  // STRIPE'S OWN PAID TIME (accountant, 13 Nov 2026, ledger 1685): ISO, when the caller holds it (the invoice's
  // status_transitions.paid_at, the PaymentIntent's charge). The refund window counts from it (public.fn_reveal_refund_window_ends,
  // through trg_reveal_window). A caller that does not hold it leaves it null: stripe_webhook's recordStripeFee writes it from
  // the charge, and trg_reveal_window moves the deadline to count from it.
  paidAt?: string | null;
};

/** An ISO time from Stripe's unix seconds, or null. */
export function paidAtFromUnix(sec: unknown): string | null {
  const n = Number(sec);
  return Number.isFinite(n) && n > 1_000_000_000 ? new Date(n * 1000).toISOString() : null;
}

export function invoiceRef(id: string | null | undefined): string | null {
  return id && /^in_[A-Za-z0-9_]+$/.test(id) ? id : null;
}

// A SECOND PAYMENT IS NOT THE SAME SALE (3 Nov 2026, accountant, gap #7). Two tabs paid one quote twice in Stripe
// test mode (runs acpay01-03: two succeeded PaymentIntents, one transaction) and this answered "already recorded"
// for the second, so the second AED 1,000 sat at Stripe with nothing but an error line. A payment whose reference
// is not the recorded sale's comes back as `other_payment` and is filed as a finding keyed on that payment, for the
// CEO to refund (refunds are the CEO's); it is never written as a second sale and never merged into the first.
export type SaleResult = { id: string; created: boolean; other_payment?: string } | { error: string };

export async function recordRevealSale(admin: any, a: SaleArgs): Promise<SaleResult> {
  const inv = invoiceRef(a.invoiceId);
  const { data: existing } = await admin.from('transactions').select('id,stripe_invoice_id,payment_ref').eq('quote_id', a.quoteId).maybeSingle();
  if (existing?.id) return sameOrSecond(admin, existing, a, inv);
  const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount').eq('id', a.quoteId).maybeSingle();
  if (!q) return { error: 'quote not found: ' + a.quoteId };
  const { data: inq } = await admin.from('inquiries').select('customer_id').eq('id', q.inquiry_id).maybeSingle();
  // THE SALE IS WRITTEN FIRST, THEN THE QUOTE AND THE REQUEST READ REVEALED (sales_engineer, customer-journey follow-up,
  // 10 Nov 2026). MEASURED on origin/main: both were marked 'revealed' BEFORE the insert, so an insert that failed (any
  // error but the unique race) left a quote reading revealed with no sale behind it: the portal treated it as paid-for,
  // nothing to refund, nothing for the accountant. Now a failed insert changes nothing, and a sale whose status writes
  // did not land is healed by the next delivery of the same payment (sameOrSecond -> markRevealed): the webhook retries.
  // THE REFUND WINDOW IS THE DATABASE'S: this sent refund_deadline computed with a fallback of 3 working days, while
  // pricing_config holds 5 (measured on production) and trg_reveal_window already computes the deadline from that row
  // when none is sent — and also opens refund_status 'window_open', which this path's own deadline skipped. One rule now.
  // 13 Nov 2026: the rule counts from paid_at (Stripe's paid time), not from this insert (a late webhook started it late).
  const { data: tx, error } = await admin.from('transactions').insert({
    quote_id: a.quoteId, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id,
    customer_id: inq?.customer_id || a.customerId || null, quote_amount: Number(q.quote_amount),
    reveal_fee: a.baseFee, app_fee: a.baseFee, processing_fee: a.processingFee, total_charged: a.totalCharged,
    customer_price: Number(q.quote_amount), paid_by: 'customer', payment_ref: a.paymentRef, fee_status: 'paid',
    // revealed_at is the database's default (the moment this row is written); paid_at is Stripe's, the window's start.
    paid_at: a.paidAt || null, stripe_invoice_id: inv,
  }).select('id').single();
  if (error) {
    // transactions.quote_id is unique: a racing delivery lost the insert, so the row the winner wrote is the answer.
    const { data: again } = await admin.from('transactions').select('id,stripe_invoice_id,payment_ref').eq('quote_id', a.quoteId).maybeSingle();
    return again?.id ? sameOrSecond(admin, again, a, inv) : { error: 'insert failed: ' + error.message };
  }
  await markRevealed(admin, a.quoteId, q.inquiry_id);
  return { id: String(tx.id), created: true };
}

// The quote and its request read revealed once the sale exists. Written only when they do not already say so (a repeat
// delivery writes nothing: one reveal write per quote, stripe_webhook/drill_webhook_replay.test.ts D4), and never a step
// back: a request already completed (hired) stays completed. Called after the insert and on every later delivery.
async function markRevealed(admin: any, quoteId: string, inquiryId: string | null | undefined) {
  const { data: qs } = await admin.from('quotes').select('status').eq('id', quoteId).maybeSingle();
  if (String(qs?.status ?? '') !== 'revealed') await admin.from('quotes').update({ status: 'revealed' }).eq('id', quoteId);
  if (!inquiryId) return;
  const { data: is } = await admin.from('inquiries').select('status').eq('id', inquiryId).maybeSingle();
  if (!['revealed', 'completed'].includes(String(is?.status ?? ''))) await admin.from('inquiries').update({ status: 'revealed' }).eq('id', inquiryId);
}

async function sameOrSecond(admin: any, existing: any, a: SaleArgs, inv: string | null): Promise<SaleResult> {
  const id = String(existing.id);
  const recorded = String(existing.payment_ref || '');
  // A SECOND PAYMENT IS TWO DIFFERENT PaymentIntents, nothing less (review of #1835). A path that could not read the
  // PaymentIntent used to fall back to the invoice id (in_...) or the session id (cs_...), so comparing it with a pi_
  // flagged the ONLY payment as one to refund. Same invoice = same sale; only pi_ against a different pi_ is flagged.
  const isPi = (r: string) => /^pi_[A-Za-z0-9_]+$/.test(r);
  const sameInvoice = Boolean(inv && existing.stripe_invoice_id && inv === existing.stripe_invoice_id);
  if (!sameInvoice && isPi(recorded) && isPi(a.paymentRef) && recorded !== a.paymentRef) {
    try {
      await admin.rpc('fn_it_engineer_finding_upsert', {
        p_issue_key: 'reveal:second_payment:' + a.paymentRef,
        p_title: 'A revealed quote was paid a second time: the second payment must be refunded',
        p_where: 'recordRevealSale (stripe_checkout element_pay/element_settle, stripe_webhook checkout and invoice.paid, stripe_confirm)',
        p_blast: 'customer_facing', p_affected: 1,
        p_evidence: { quote_id: a.quoteId, transaction_id: id, recorded_payment: recorded, second_payment: a.paymentRef,
          second_invoice: inv, amount_aed: a.totalCharged, owner_seat: 'ceo', fix: 'a CEO-approved refund of the second payment' },
        p_raised_by: 'accountant',
      });
    } catch (_e) { /* every caller also logs other_payment at error level */ }
    return { id, created: false, other_payment: a.paymentRef };
  }
  // Write-once, as fn_transaction_attach_invoice: an empty reference is filled, a set one never replaced.
  if (inv && !existing.stripe_invoice_id) await admin.from('transactions').update({ stripe_invoice_id: inv }).eq('id', id).is('stripe_invoice_id', null);
  // The same sale delivered again: the statuses its first delivery may not have written are written now.
  const { data: q } = await admin.from('quotes').select('id,inquiry_id').eq('id', a.quoteId).maybeSingle();
  if (q) await markRevealed(admin, a.quoteId, q.inquiry_id);
  return { id, created: false };
}
