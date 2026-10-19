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
};

export function invoiceRef(id: string | null | undefined): string | null {
  return id && /^in_[A-Za-z0-9_]+$/.test(id) ? id : null;
}

export async function recordRevealSale(admin: any, a: SaleArgs): Promise<{ id: string; created: boolean } | { error: string }> {
  const inv = invoiceRef(a.invoiceId);
  const { data: existing } = await admin.from('transactions').select('id,stripe_invoice_id').eq('quote_id', a.quoteId).maybeSingle();
  if (existing?.id) {
    // Write-once, as fn_transaction_attach_invoice: an empty reference is filled, a set one never replaced.
    if (inv && !existing.stripe_invoice_id) await admin.from('transactions').update({ stripe_invoice_id: inv }).eq('id', existing.id).is('stripe_invoice_id', null);
    return { id: String(existing.id), created: false };
  }
  const { data: q } = await admin.from('quotes').select('id,inquiry_id,supplier_id,quote_amount').eq('id', a.quoteId).maybeSingle();
  if (!q) return { error: 'quote not found: ' + a.quoteId };
  const { data: inq } = await admin.from('inquiries').select('customer_id').eq('id', q.inquiry_id).maybeSingle();
  const { data: cfg } = await admin.from('pricing_config').select('refund_window_working_days').eq('id', 1).maybeSingle();
  const { data: dl } = await admin.rpc('fn_add_working_days', { p_from: new Date().toISOString(), p_days: cfg?.refund_window_working_days ?? 3 });
  await admin.from('quotes').update({ status: 'revealed' }).eq('id', a.quoteId);
  await admin.from('inquiries').update({ status: 'revealed' }).eq('id', q.inquiry_id);
  const { data: tx, error } = await admin.from('transactions').insert({
    quote_id: a.quoteId, inquiry_id: q.inquiry_id, supplier_id: q.supplier_id,
    customer_id: inq?.customer_id || a.customerId || null, quote_amount: Number(q.quote_amount),
    reveal_fee: a.baseFee, app_fee: a.baseFee, processing_fee: a.processingFee, total_charged: a.totalCharged,
    customer_price: Number(q.quote_amount), paid_by: 'customer', payment_ref: a.paymentRef, fee_status: 'paid',
    revealed_at: new Date().toISOString(), refund_deadline: dl, stripe_invoice_id: inv,
  }).select('id').single();
  if (error) {
    const { data: again } = await admin.from('transactions').select('id').eq('quote_id', a.quoteId).maybeSingle();
    return again?.id ? { id: String(again.id), created: false } : { error: 'insert failed: ' + error.message };
  }
  return { id: String(tx.id), created: true };
}
