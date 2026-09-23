// THE REVEAL, PRICED ON THE CARD ACTUALLY USED (14 Sep 2026, agent: accountant).
//
// Founder: "maybe in the checkout its better to confirm with the customer so that we charge them
// correctly. or if it can be automated during deduction then its better." A Checkout Session fixes
// its amount before the customer picks a card, so it cannot do this. The reveal therefore moves to
// the Payment Element with a deferred intent: the browser turns the customer's card (or Apple Pay)
// into a ConfirmationToken, this module reads the card's issuing country from it, prices the
// processing line for THAT card, and only then creates and pays a Stripe Invoice for the exact
// amount. The invoice is paid through its own PaymentIntent, confirmed with the same token, so the
// portal's "Invoice (PDF)" and the accountant's filing work exactly as before.
//
// TWO GUARDS ON MONEY
//   1. The customer is never charged an amount they were not shown: `expected_total_fils` is what
//      the portal displayed on the final confirm line, and a different total is returned as
//      'repriced' with nothing created at Stripe.
//   2. A payment that fails leaves no open invoice behind: the invoice is voided.
import { feeBasisFromPreview, revealChargeFor, type FeeBasis, type RevealCharge } from '../_shared/reveal_fee.ts';

export type StripeResult = { ok: boolean; status: number; j: any };
/** GET when form is undefined, POST otherwise. idem becomes the Idempotency-Key header. */
export type StripeCall = (path: string, form?: URLSearchParams, idem?: string) => Promise<StripeResult>;

export const INVOICE_FOOTER =
  'QuotesDone Technologies · DET licence 1633275 · TDRA NOL-26-100000665 · not registered for VAT, no VAT charged';

export type Priced = { basis: FeeBasis; charge: RevealCharge };

export async function priceToken(stripe: StripeCall, ct: string, quoteAmount: number, rate: number):
  Promise<{ ok: true; priced: Priced } | { ok: false; error: string; status: number }> {
  if (!/^ctoken_[A-Za-z0-9_]+$/.test(ct)) return { ok: false, error: 'bad_confirmation_token', status: 400 };
  const r = await stripe('confirmation_tokens/' + encodeURIComponent(ct));
  if (!r.ok) return { ok: false, error: 'confirmation_token_unreadable', status: 502 };
  const basis = feeBasisFromPreview(r.j?.payment_method_preview);
  return { ok: true, priced: { basis, charge: revealChargeFor(quoteAmount, rate, basis.basis) } };
}

export type PayArgs = {
  ct: string; quoteAmount: number; rate: number; expectedTotalFils: number;
  email: string; qdCustomerId: string; quoteId: string; inquiryId: string; supplierId: string;
  requestRef: string; letter: string; returnUrl: string;
};
export type PayResult =
  | { status: 'repriced'; priced: Priced }
  | { status: 'succeeded' | 'requires_action' | 'processing'; priced: Priced; invoice: string; payment_intent: string; client_secret?: string }
  | { status: 'failed'; priced?: Priced; invoice?: string; error: string };

const fils = (aed: number) => Math.round(aed * 100);

export async function payReveal(stripe: StripeCall, a: PayArgs): Promise<PayResult> {
  const p = await priceToken(stripe, a.ct, a.quoteAmount, a.rate);
  if (!p.ok) return { status: 'failed', error: p.error };
  const { priced } = p;
  if (fils(priced.charge.total_charged) !== Math.round(Number(a.expectedTotalFils))) return { status: 'repriced', priced };

  // One Stripe customer per QuotesDone customer, found by our id rather than by email.
  let customer = '';
  const found = await stripe('customers/search?query=' + encodeURIComponent(`metadata['qd_customer_id']:'${a.qdCustomerId}'`));
  if (found.ok && found.j?.data?.[0]?.id) customer = String(found.j.data[0].id);
  if (!customer) {
    const cf = new URLSearchParams({ email: a.email, 'metadata[qd_customer_id]': a.qdCustomerId });
    const c = await stripe('customers', cf, 'qd-cus-' + a.qdCustomerId);
    if (!c.ok) return { status: 'failed', priced, error: 'customer_create_failed' };
    customer = String(c.j.id);
  }

  const md: Record<string, string> = {
    kind: 'reveal', flow: 'element', quote_id: a.quoteId, inquiry_id: a.inquiryId, customer_id: a.qdCustomerId,
    supplier_id: a.supplierId, quote_amount: String(a.quoteAmount), base_fee: String(priced.charge.base_fee),
    processing_fee: String(priced.charge.processing_fee), total_charged: String(priced.charge.total_charged),
    fee_basis: priced.basis.basis, card_country: priced.basis.card_country || '', wallet: priced.basis.wallet || '',
  };
  const inf = new URLSearchParams({
    customer, currency: 'aed', collection_method: 'charge_automatically', auto_advance: 'false',
    pending_invoice_items_behavior: 'exclude',
    description: 'Reveal fee — ' + a.requestRef + ' / Supplier ' + a.letter, footer: INVOICE_FOOTER,
  });
  for (const [k, v] of Object.entries(md)) inf.set(`metadata[${k}]`, v);
  const inv = await stripe('invoices', inf, 'qd-inv-' + a.ct);
  if (!inv.ok) return { status: 'failed', priced, error: 'invoice_create_failed' };
  const invoice = String(inv.j.id);

  const lines: [string, number][] = [
    ['Reveal fee (3% of AED ' + Number(a.quoteAmount).toFixed(2) + ')', fils(priced.charge.base_fee)],
  ];
  // No card-fee line: Cabinet Res. 66/2023 Art. 5(3) (24 Sep 2026). A non-zero one would be a surcharge; refuse it.
  if (priced.charge.processing_fee !== 0) return { status: 'failed', priced, error: 'card_surcharge_refused' };
  for (const [i, [desc, amount]] of lines.entries()) {
    const li = await stripe('invoiceitems', new URLSearchParams({ customer, invoice, currency: 'aed', amount: String(amount), description: desc }), 'qd-ii' + i + '-' + a.ct);
    if (!li.ok) { await stripe('invoices/' + invoice + '/void', new URLSearchParams()); return { status: 'failed', priced, invoice, error: 'invoice_line_failed' }; }
  }

  const fin = await stripe('invoices/' + invoice + '/finalize', new URLSearchParams({ auto_advance: 'false', 'expand[]': 'confirmation_secret' }), 'qd-fin-' + a.ct);
  const secretStr = String(fin.j?.confirmation_secret?.client_secret || '');
  const pi = secretStr.split('_secret_')[0];
  if (!fin.ok || !/^pi_/.test(pi) || Number(fin.j?.amount_due) !== fils(priced.charge.total_charged)) {
    await stripe('invoices/' + invoice + '/void', new URLSearchParams());
    return { status: 'failed', priced, invoice, error: 'invoice_finalize_failed' };
  }

  const conf = await stripe('payment_intents/' + pi + '/confirm', new URLSearchParams({ confirmation_token: a.ct, return_url: a.returnUrl }), 'qd-confirm-' + a.ct);
  const st = String(conf.j?.status || '');
  if (conf.ok && (st === 'succeeded' || st === 'processing')) return { status: st, priced, invoice, payment_intent: pi };
  if (conf.ok && st === 'requires_action') return { status: 'requires_action', priced, invoice, payment_intent: pi, client_secret: secretStr };
  await stripe('invoices/' + invoice + '/void', new URLSearchParams());
  return { status: 'failed', priced, invoice, error: String(conf.j?.error?.decline_code || conf.j?.error?.code || conf.j?.last_payment_error?.code || 'payment_failed') };
}
