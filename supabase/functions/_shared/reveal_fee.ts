// THE REVEAL CHARGE, IN ONE PLACE (14 Sep 2026, agent: accountant).
//
// Founder, 14 Sep 2026, in order:
//   "make sure its 3% plus stripe fees included."
//   "charge as per the safest, but in most cases its gonna be UAE based card ... if it can be
//    automated during deduction then its better."
//   "make sure any service charge is added to the customer invoice. nothing on us"
// So the customer pays the 3% reveal fee plus EVERY Stripe cost of taking that payment, on one line
// called "Card processing", and QuotesDone nets the full 3%. No VAT is charged to the customer: "our
// company is not vat registered so for our reveal fee there is no vat". A refund returns everything
// the customer paid; QuotesDone absorbs Stripe's fee only then.
//
// EVERY STRIPE COST OF ONE REVEAL, AND WHERE EACH NUMBER CAME FROM (read 14 Sep 2026):
//   card processing   stripe.com/ae/pricing: "2.9% + AED1.00 per successful transaction for domestic
//                     cards", "+ 1% for international cards". Amex is not priced separately there.
//                     Apple Pay, Google Pay and Link carry no price of their own: Stripe prices the
//                     card inside them, so the card's issuing country decides the rate.
//   currency conv.    "+ 1% if currency conversion is required" -> ZERO here: the reveal charges AED
//                     and the account settles AED.
//   Invoicing         stripe.com/ae/invoicing/pricing: Starter "0.4% Per paid invoice", Plus "0.5% Per
//                     paid invoice". Every reveal is a paid Stripe Invoice. The account's plan could
//                     not be read (the account object is not exposed to our tooling and the live
//                     account has no Stripe fee transactions yet), so the HIGHER rate, 0.5%, is used.
//                     Invoicing is billed separately from the card fee, not inside it, so a balance
//                     transaction alone never shows it.
//   VAT on Stripe fees stripe.com/ae/pricing: "Stripe is required to charge tax on certain products and
//                     services. Tax is charged based on your location and/or your business/tax status."
//                     UAE VAT is 5%. It was not possible to establish that it does NOT apply to this
//                     account, so 5% is charged on top of every Stripe fee above.
// Every rate here is the conservative end of what could apply. The ACTUAL card fee is read from the
// balance transaction after payment (stripe_webhook recordStripeFee), compared with what was collected,
// and any shortfall is raised to the CEO as an incident: never absorbed silently.
export const STRIPE_DOMESTIC_PCT = 0.029;
export const STRIPE_CARD_PCT = 0.039;            // international: 2.9% + 1%
export const STRIPE_CARD_FIXED_AED = 1.0;
export const STRIPE_INVOICING_PCT = 0.005;       // Invoicing Plus; Starter is 0.4%
export const STRIPE_CURRENCY_CONVERSION_PCT = 0; // AED charged, AED settled
export const VAT_ON_STRIPE_FEES = 0.05;          // UAE VAT, on Stripe's own fees
export const HOME_CARD_COUNTRY = 'AE';

export type RevealCharge = { base_fee: number; processing_fee: number; total_charged: number };
export type FeeBasis = {
  basis: 'domestic' | 'international';
  card_country: string | null;
  wallet: string | null;
  method: string;
  reason: string;
};

const fils = (aed: number) => Math.round(aed * 100);

/** The percentage of the total that Stripe takes for this card basis, VAT on the fees included. */
export function stripePctFor(basis: FeeBasis['basis']): number {
  const card = basis === 'domestic' ? STRIPE_DOMESTIC_PCT : STRIPE_CARD_PCT;
  return (card + STRIPE_INVOICING_PCT + STRIPE_CURRENCY_CONVERSION_PCT) * (1 + VAT_ON_STRIPE_FEES);
}
/** The fixed part Stripe takes per payment, VAT on the fee included. */
export const STRIPE_FIXED_WITH_VAT = STRIPE_CARD_FIXED_AED * (1 + VAT_ON_STRIPE_FEES);

/** What Stripe costs us, in AED, on a total of `totalAed` for this basis. Never rounded down. */
export function stripeCostFor(totalAed: number, basis: FeeBasis['basis']): number {
  return Math.ceil((totalAed * stripePctFor(basis) + STRIPE_FIXED_WITH_VAT) * 100 - 1e-9) / 100;
}

/**
 * base = round(rate x quote), total = ceil_to_fils((base + fixed) / (1 - pct)), where pct and fixed
 * carry every Stripe cost above. base + processing === total exactly, to the fils.
 */
export function revealCharge(quoteAmount: number, rate: number,
  pct = stripePctFor('international'), fixed = STRIPE_FIXED_WITH_VAT): RevealCharge {
  const amount = Number(quoteAmount), r = Number(rate);
  if (!(amount > 0) || !(r > 0)) return { base_fee: 0, processing_fee: 0, total_charged: 0 };
  const baseF = fils(amount * r);
  // ceil on an integer number of fils; the tiny epsilon stops 1234.0000000002 from rounding up a fils.
  const totalF = Math.ceil((baseF + fixed * 100) / (1 - pct) - 1e-9);
  return { base_fee: baseF / 100, processing_fee: (totalF - baseF) / 100, total_charged: totalF / 100 };
}

/**
 * Which rate the card in a ConfirmationToken's payment_method_preview costs us. Anything that is not
 * a card whose issuing country Stripe reports falls to the international (safest) rate, and says why.
 */
export function feeBasisFromPreview(preview: Record<string, any> | null | undefined): FeeBasis {
  const method = String(preview?.type || 'unknown');
  const card = method === 'card' ? preview?.card : null;
  const country = card?.country ? String(card.country).toUpperCase() : null;
  const wallet = card?.wallet?.type ? String(card.wallet.type) : null;
  if (country === HOME_CARD_COUNTRY) {
    return { basis: 'domestic', card_country: country, wallet, method, reason: 'card issued in ' + country };
  }
  if (country) {
    return { basis: 'international', card_country: country, wallet, method, reason: 'card issued in ' + country };
  }
  return { basis: 'international', card_country: null, wallet, method,
    reason: 'card country not reported for ' + method + ' - charged at the safest rate' };
}

export function revealChargeFor(quoteAmount: number, rate: number, basis: FeeBasis['basis']): RevealCharge {
  return revealCharge(quoteAmount, rate, stripePctFor(basis), STRIPE_FIXED_WITH_VAT);
}

/**
 * After payment: what Stripe actually took on the card (the balance transaction's fee), plus the
 * Invoicing fee and its VAT that Stripe bills separately, against the processing line we collected.
 * A positive shortfall means the customer did not cover every Stripe cost.
 */
export function shortfallAfterPayment(a: { processing_fee: number; total_charged: number; actual_card_fee_fils: number }): number {
  const invoicingF = Math.ceil(a.total_charged * 100 * STRIPE_INVOICING_PCT * (1 + VAT_ON_STRIPE_FEES) - 1e-9);
  return (a.actual_card_fee_fils + invoicingF - fils(a.processing_fee)) / 100;
}
