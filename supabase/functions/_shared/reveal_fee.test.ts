// Run: deno test --node-modules-dir=none supabase/functions/_shared/reveal_fee.test.ts
// 24 Sep 2026 (accountant): no buyer is ever charged the card fee. Cabinet Resolution 66/2023 Art. 5(3) forbids
// adding any amount to the price when a card is used, and Federal Law 15/2020 counts a company buying for itself as
// a consumer, so the charge is the 3% reveal fee and nothing else; QuotesDone absorbs every Stripe cost.
import { assertEquals } from 'jsr:@std/assert@1';
import {
  absorbedStripeCost, CARD_FEE_CHARGED_TO_BUYER, feeBasisFromPreview, revealCharge, revealChargeFor, stripeCostFor,
  stripePctFor, STRIPE_CARD_FIXED_AED, STRIPE_CARD_PCT, STRIPE_DOMESTIC_PCT, STRIPE_INVOICING_PCT, VAT_ON_STRIPE_FEES,
} from './reveal_fee.ts';

const fils = (n: number) => Math.round(n * 100);
const QUOTES = [0.5, 10, 99.99, 1000, 12345.67, 250000, 1_000_000];
const card = (country: string | null, wallet: string | null = null, brand = 'visa') =>
  ({ type: 'card', card: { country, brand, wallet: wallet ? { type: wallet } : null } });
const METHODS = [
  ['UAE Visa', card('AE')], ['UAE Amex', card('AE', null, 'amex')], ['Apple Pay (UAE card)', card('AE', 'apple_pay')],
  ['UK Visa', card('GB')], ['US Amex', card('US', null, 'amex')], ['Apple Pay (foreign card)', card('SA', 'apple_pay')],
  ['Link (no card country)', { type: 'link' }], ['unknown', null],
] as const;

// THE GUARD. It fails the moment any path charges a buyer anything on top of the 3% for paying by card.
Deno.test('no buyer is ever charged a card fee: total is exactly the 3% reveal fee, for every card and quote', () => {
  assertEquals(CARD_FEE_CHARGED_TO_BUYER, false);
  for (const [name, preview] of METHODS) for (const q of QUOTES) {
    const basis = feeBasisFromPreview(preview as never).basis;
    for (const c of [revealChargeFor(q, 0.03, basis), revealCharge(q, 0.03)]) {
      assertEquals(c.processing_fee, 0, `${name}, quote ${q}: a card fee was charged`);
      assertEquals(fils(c.total_charged), fils(c.base_fee), `${name}, quote ${q}: total is not the reveal fee`);
      assertEquals(fils(c.base_fee), Math.round(q * 0.03 * 100), `${name}, quote ${q}: base is not 3%`);
    }
  }
});

Deno.test('what QuotesDone absorbs: card + Invoicing, 5% VAT on both, never rounded down', () => {
  assertEquals(stripePctFor('domestic'), (STRIPE_DOMESTIC_PCT + STRIPE_INVOICING_PCT) * (1 + VAT_ON_STRIPE_FEES));
  assertEquals(stripePctFor('international'), (STRIPE_CARD_PCT + STRIPE_INVOICING_PCT) * (1 + VAT_ON_STRIPE_FEES));
  // AED 10,000 quote -> AED 300 charged. Domestic: 300 x 3.57% + 1.05 = 11.76. International: 300 x 4.62% + 1.05 = 14.91.
  assertEquals(stripeCostFor(300, 'domestic'), 11.76);
  assertEquals(stripeCostFor(300, 'international'), 14.91);
});

// MEASURED, test mode, 14 Sep 2026: UAE Visa on 309.99 -> fee 1049 (999 + 50 VAT). Invoicing is billed apart.
Deno.test('absorbed cost after payment = the balance transaction fee + Invoicing and its VAT', () => {
  const invoicingF = Math.ceil(309.99 * 100 * STRIPE_INVOICING_PCT * (1 + VAT_ON_STRIPE_FEES));
  assertEquals(absorbedStripeCost({ total_charged: 309.99, actual_card_fee_fils: 1049 }), (1049 + invoicingF) / 100);
  assertEquals(Math.round((309.99 * STRIPE_DOMESTIC_PCT + STRIPE_CARD_FIXED_AED) * 100), 999, 'card-fee model matches Stripe');
});

Deno.test('Amex and wallets are costed by the card inside them', () => {
  assertEquals(feeBasisFromPreview(card('AE', null, 'amex')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('AE', 'apple_pay')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('GB', 'apple_pay')).basis, 'international');
  assertEquals(feeBasisFromPreview({ type: 'link' }).basis, 'international');
});

Deno.test('zero, negative and missing amounts charge nothing', () => {
  const zero = { base_fee: 0, processing_fee: 0, total_charged: 0 };
  assertEquals(revealCharge(0, 0.03), zero);
  assertEquals(revealCharge(-5, 0.03), zero);
  assertEquals(revealCharge(NaN, 0.03), zero);
  assertEquals(revealCharge(1000, 0), zero);
});

Deno.test('base rounds half-up to the fils like public.reveal_fee()', () => {
  assertEquals(revealCharge(0.5, 0.03).base_fee, 0.02);
  assertEquals(revealCharge(33.33, 0.03).base_fee, 1);
});
