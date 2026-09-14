// Run: deno test --node-modules-dir=none supabase/functions/_shared/reveal_fee.test.ts
// Founder, 14 Sep 2026: "make sure any service charge is added to the customer invoice. nothing on us".
import { assertEquals } from 'jsr:@std/assert@1';
import {
  feeBasisFromPreview, revealCharge, revealChargeFor, shortfallAfterPayment, stripeCostFor, stripePctFor,
  STRIPE_CARD_FIXED_AED, STRIPE_CARD_PCT, STRIPE_DOMESTIC_PCT, STRIPE_INVOICING_PCT, VAT_ON_STRIPE_FEES,
} from './reveal_fee.ts';

const fils = (n: number) => Math.round(n * 100);
const QUOTES = [10, 99.99, 1000, 12345.67, 250000, 1_000_000];
const card = (country: string | null, wallet: string | null = null, brand = 'visa') =>
  ({ type: 'card', card: { country, brand, wallet: wallet ? { type: wallet } : null } });

Deno.test('every Stripe cost is in the rate: card + Invoicing, and 5% VAT on both', () => {
  assertEquals(stripePctFor('domestic'), (STRIPE_DOMESTIC_PCT + STRIPE_INVOICING_PCT) * (1 + VAT_ON_STRIPE_FEES));
  assertEquals(stripePctFor('international'), (STRIPE_CARD_PCT + STRIPE_INVOICING_PCT) * (1 + VAT_ON_STRIPE_FEES));
  assertEquals(STRIPE_INVOICING_PCT, 0.005, 'the higher Invoicing plan (Plus), since the plan cannot be read');
});

Deno.test('lines add up to the total exactly, to the fils, for both bases', () => {
  for (let q = 1; q < 200000; q += 997.37) for (const b of ['domestic', 'international'] as const) {
    const c = revealChargeFor(q, 0.03, b);
    assertEquals(fils(c.base_fee) + fils(c.processing_fee), fils(c.total_charged), `quote ${q} ${b}`);
  }
});

Deno.test('QuotesDone nets the full 3% after EVERY Stripe cost, for every method', () => {
  const methods = [
    ['UAE Visa', card('AE')], ['UAE Mastercard', card('AE', null, 'mastercard')], ['UAE Amex', card('AE', null, 'amex')],
    ['Apple Pay (UAE card)', card('AE', 'apple_pay')], ['Google Pay (UAE card)', card('AE', 'google_pay')],
    ['UK Visa', card('GB')], ['US Amex', card('US', null, 'amex')], ['Apple Pay (foreign card)', card('SA', 'apple_pay')],
    ['Link (no card country)', { type: 'link' }], ['unknown', null],
  ] as const;
  for (const [name, preview] of methods) for (const q of QUOTES) {
    const basis = feeBasisFromPreview(preview as never).basis;
    const c = revealChargeFor(q, 0.03, basis);
    const net = c.total_charged - stripeCostFor(c.total_charged, basis);
    assertEquals(net + 1e-9 >= c.base_fee, true, `${name}, quote ${q}: nets ${net.toFixed(2)} < 3% ${c.base_fee}`);
    assertEquals(net - c.base_fee < 0.03, true, `${name}, quote ${q}: over-collects ${(net - c.base_fee).toFixed(2)}`);
  }
});

Deno.test('Amex and wallets are priced by the card inside them, not surcharged separately', () => {
  assertEquals(feeBasisFromPreview(card('AE', null, 'amex')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('AE', 'apple_pay')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('AE', 'google_pay')).basis, 'domestic');
  assertEquals(feeBasisFromPreview(card('GB', 'apple_pay')).basis, 'international');
  assertEquals(feeBasisFromPreview({ type: 'link' }).basis, 'international');
});

Deno.test('worked example, AED 10,000 quote: UAE card 312.20, international 315.64', () => {
  assertEquals(revealChargeFor(10000, 0.03, 'domestic'), { base_fee: 300, processing_fee: 12.2, total_charged: 312.2 });
  assertEquals(revealChargeFor(10000, 0.03, 'international'), { base_fee: 300, processing_fee: 15.64, total_charged: 315.64 });
  assertEquals(revealCharge(10000, 0.03), revealChargeFor(10000, 0.03, 'international'), 'the default is the safest rate');
});

Deno.test('shortfall: zero when the actual card fee is what we priced, positive when Stripe took more', () => {
  const c = revealChargeFor(10000, 0.03, 'domestic');
  // Stripe's own domestic card fee on 312.20 with VAT: (312.20 x 2.9% + 1.00) x 1.05 = 10.56
  const cardFeeF = Math.ceil((c.total_charged * STRIPE_DOMESTIC_PCT + STRIPE_CARD_FIXED_AED) * (1 + VAT_ON_STRIPE_FEES) * 100);
  assertEquals(shortfallAfterPayment({ ...c, actual_card_fee_fils: cardFeeF }) <= 0, true);
  // A UAE-priced charge that Stripe actually billed as international comes up short, and says by how much.
  const intlFeeF = Math.ceil((c.total_charged * STRIPE_CARD_PCT + STRIPE_CARD_FIXED_AED) * (1 + VAT_ON_STRIPE_FEES) * 100);
  assertEquals(shortfallAfterPayment({ ...c, actual_card_fee_fils: intlFeeF }) > 0, true);
});

// MEASURED, test mode of acct_1To5DvC45SqX5pVb, 14 Sep 2026. Two invoices built at the #615 rates
// (card processing only) and collected by Stripe. Balance transactions:
//   YKYNMRDZ-0001, UAE Visa, 309.99: fee 1049 = "Stripe processing fees" 999 + "VAT" 50
//   X5GCOETZ-0001, UK Visa,  313.22: fee 1388 = "Stripe processing fees" 1322 + "VAT" 66
// So the card rates are exactly as published, Stripe DOES charge 5% VAT on its fee, and the old line
// (999 / 1322) under-collected by that VAT - before the Invoicing fee, which is billed separately.
Deno.test('measured: the old line fell short by the VAT on the fee; the new line covers it and Invoicing', () => {
  const measured = [
    { basis: 'domestic' as const, charged: 309.99, oldProcessing: 9.99, stripeFeeF: 999, vatF: 50 },
    { basis: 'international' as const, charged: 313.22, oldProcessing: 13.22, stripeFeeF: 1322, vatF: 66 },
  ];
  for (const m of measured) {
    const pct = m.basis === 'domestic' ? STRIPE_DOMESTIC_PCT : STRIPE_CARD_PCT;
    // our card-fee model reproduces what Stripe took, to the fils
    assertEquals(Math.round((m.charged * pct + STRIPE_CARD_FIXED_AED) * 100), m.stripeFeeF, `${m.basis} card fee`);
    assertEquals(Math.round(m.stripeFeeF * VAT_ON_STRIPE_FEES), m.vatF, `${m.basis} VAT on the fee`);
    // the old line: short by the VAT (and by Invoicing on top)
    assertEquals(shortfallAfterPayment({ processing_fee: m.oldProcessing, total_charged: m.charged, actual_card_fee_fils: m.stripeFeeF + m.vatF }) > 0, true);
    // the new line on the same AED 10,000 quote covers card fee + VAT + Invoicing + its VAT, each rounded as Stripe rounds
    const c = revealChargeFor(10000, 0.03, m.basis);
    const cardF = Math.round((c.total_charged * pct + STRIPE_CARD_FIXED_AED) * 100);
    const actualF = cardF + Math.round(cardF * VAT_ON_STRIPE_FEES);
    assertEquals(shortfallAfterPayment({ ...c, actual_card_fee_fils: actualF }) <= 0, true, `${m.basis}: new line short`);
  }
});

Deno.test('an exact division is not rounded up a fils', () => {
  assertEquals(revealCharge(100, 0.03, 0.5, 0), { base_fee: 3, processing_fee: 3, total_charged: 6 });
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
