// THE REVEAL CHARGE, IN ONE PLACE (agent: accountant).
//
// 24 SEP 2026 — NO CARD SURCHARGE ON ANY BUYER. Founder: "we must be fully compliant with UAE law, and nobody may
// be able to sue us". Cabinet Resolution 66/2023 (executive regulation of the Consumer Protection Law, Federal
// Law 15/2020), Art. 5(3): the supplier shall "Not add any further amounts on the value of commodity, if credit
// cards are used in the purchase of commodities and services." Law 15/2020 Art. 1 defines the consumer as every
// natural OR juristic person who obtains a good or service for his own needs or those of others, so a company
// buying for itself is a consumer too: no account type can safely be charged the fee. The customer therefore
// pays the 3% reveal fee and NOTHING else; QuotesDone bears every Stripe cost, booked to expense 6100 from the
// balance transaction (fn_gl_sync_business). The 14 Sep ruling "3% plus stripe fees included ... nothing on us"
// is superseded by the law, which the founder's 24 Sep instruction puts first.
//
// The Stripe rates below no longer price the customer. They estimate what QuotesDone absorbs (stripeCostFor), for
// the books' fallback and for the revenue-impact figure, until the balance transaction gives the real fee.
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
// Every rate here is the conservative end of what could apply.
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

/** Never true: Cabinet Res. 66/2023 Art. 5(3). reveal_fee.test.ts fails if a charge ever carries a card fee. */
export const CARD_FEE_CHARGED_TO_BUYER = false as const;

/**
 * rate x quote in fils, rounded half-up EXACTLY as public.reveal_fee() rounds numeric (3 Nov 2026, accountant).
 * Math.round(amount * rate * 100) is binary floating point: AED 33.50 x 3% = 1.005 lands just under 100.5 fils,
 * so the card was charged AED 1.00 where the database says AED 1.01. The quote is whole fils and the rate has at
 * most six places, so integers carry the product exactly.
 */
export function revealFeeFils(quoteAmount: number, rate: number): number {
  const amount = Number(quoteAmount), r = Number(rate);
  if (!(amount > 0) || !(r > 0)) return 0;
  const n = BigInt(Math.round(amount * 100)) * BigInt(Math.round(r * 1e6));
  const q = n / 1_000_000n;
  return Number((n % 1_000_000n) * 2n >= 1_000_000n ? q + 1n : q);
}

/** base = round(rate x quote) to the fils; that is the whole charge. processing_fee is always 0. */
export function revealCharge(quoteAmount: number, rate: number): RevealCharge {
  const baseF = revealFeeFils(quoteAmount, rate);
  return { base_fee: baseF / 100, processing_fee: 0, total_charged: baseF / 100 };
}

/**
 * Which Stripe rate the card in a ConfirmationToken's payment_method_preview will cost QuotesDone. Anything that
 * is not a card whose issuing country Stripe reports falls to the international (higher) rate, and says why.
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
    reason: 'card country not reported for ' + method + ' - costed at the higher rate' };
}

/** The charge does not depend on the card: the basis is kept only so callers record what Stripe will cost us. */
export function revealChargeFor(quoteAmount: number, rate: number, _basis: FeeBasis['basis']): RevealCharge {
  return revealCharge(quoteAmount, rate);
}

/**
 * After payment: every Stripe cost QuotesDone bears on this reveal, in AED — the card fee Stripe actually took
 * (balance transaction, VAT included) plus the Invoicing fee and its VAT that Stripe bills separately. Booked to
 * 6100. Not a shortfall and not an incident: absorbing it is the law (Cabinet Res. 66/2023 Art. 5(3)).
 */
export function absorbedStripeCost(a: { total_charged: number; actual_card_fee_fils: number }): number {
  const invoicingF = Math.ceil(a.total_charged * 100 * STRIPE_INVOICING_PCT * (1 + VAT_ON_STRIPE_FEES) - 1e-9);
  return (a.actual_card_fee_fils + invoicingF) / 100;
}
