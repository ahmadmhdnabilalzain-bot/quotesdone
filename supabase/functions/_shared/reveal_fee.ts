// THE REVEAL CHARGE, IN ONE PLACE (14 Sep 2026, agent: accountant).
//
// Founder, 14 Sep 2026: "make sure its 3% plus stripe fees included." The customer pays the 3%
// reveal fee PLUS Stripe's card-processing fee, so QuotesDone nets the full 3%. No VAT: "our
// company is not vat registered so for our reveal fee there is no vat". Refund (same day): the
// customer gets back everything they paid, both lines; QuotesDone absorbs Stripe's fee.
//
// THE RATE, AND WHERE IT CAME FROM. stripe.com/ae/pricing, read 14 Sep 2026: "2.9% + AED1.00 per
// successful transaction for domestic cards", "+ 1% for international cards", "+ 1% if currency
// conversion is required". Card type is only known after payment, so the charge is grossed up at
// the conservative published rate a card can cost us here — international, 3.9% + AED 1.00. The
// currency-conversion 1% does not apply: the session charges AED and the account settles AED.
// The ACTUAL fee is read from the balance transaction after payment and stored on the sale
// (transactions.stripe_fee_fils), so the difference is on the record, never guessed.
// NOT measured against a test-mode balance transaction: app_secrets holds no stripe_secret_key_test
// on 14 Sep 2026, and the live key is never used to create a charge.
export const STRIPE_CARD_PCT = 0.039;
export const STRIPE_CARD_FIXED_AED = 1.0;

export type RevealCharge = { base_fee: number; processing_fee: number; total_charged: number };

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
