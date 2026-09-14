// THE REVEAL CHARGE, IN ONE PLACE (14 Sep 2026, agent: accountant).
//
// Founder, 14 Sep 2026: "make sure its 3% plus stripe fees included." The customer pays the 3%
// reveal fee PLUS Stripe's card-processing fee, so QuotesDone nets the full 3%. No VAT: "our
// company is not vat registered so for our reveal fee there is no vat". Refund (same day): the
// customer gets back everything they paid, both lines; QuotesDone absorbs Stripe's fee.
//
// Then: "charge as per the safest, but in most cases its gonna be UAE based card ... if it can be
// automated during deduction then its better." So the processing line is priced on the card
// ACTUALLY being used, read from the Stripe ConfirmationToken before any money moves
// (feeBasisFromPreview), and the safest rate is only the fallback when the card cannot be known.
//
// THE RATES, AND WHERE THEY CAME FROM. stripe.com/ae/pricing, read 14 Sep 2026: "2.9% + AED1.00 per
// successful transaction for domestic cards", "+ 1% for international cards", "+ 1% if currency
// conversion is required". The currency-conversion 1% does not apply: the reveal charges AED and the
// account settles AED. A wallet (Apple Pay) carries the underlying card, and Stripe prices it as that
// card, so the wallet does not change the rate - the card's issuing country does.
// The ACTUAL fee is still read from the balance transaction after payment and stored on the sale
// (transactions.stripe_fee_fils), so any difference is on the record, never guessed.
export const STRIPE_DOMESTIC_PCT = 0.029;
export const STRIPE_CARD_PCT = 0.039; // international: 2.9% + 1%. The safest rate this account pays.
export const STRIPE_CARD_FIXED_AED = 1.0;
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

/**
 * base = round(rate x quote), charge = ceil_to_fils((base + fixed) / (1 - pct)).
 * Every figure is in AED with two decimals, and base + processing === total exactly, because the
 * invoice prints the two lines and the total and they must add up to the fils.
 */
export function revealCharge(quoteAmount: number, rate: number,
  pct = STRIPE_CARD_PCT, fixed = STRIPE_CARD_FIXED_AED): RevealCharge {
  const amount = Number(quoteAmount), r = Number(rate);
  if (!(amount > 0) || !(r > 0)) return { base_fee: 0, processing_fee: 0, total_charged: 0 };
  const baseF = fils(amount * r);
  // ceil on an integer number of fils; the tiny epsilon stops 1234.0000000002 from rounding up a fils.
  const totalF = Math.ceil((baseF + fils(fixed)) / (1 - pct) - 1e-9);
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
  return revealCharge(quoteAmount, rate, basis === 'domestic' ? STRIPE_DOMESTIC_PCT : STRIPE_CARD_PCT, STRIPE_CARD_FIXED_AED);
}
