// Run: deno test --node-modules-dir=none supabase/functions/_shared/reveal_fee.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { revealCharge, revealChargeFor, STRIPE_CARD_FIXED_AED, STRIPE_CARD_PCT, STRIPE_DOMESTIC_PCT } from './reveal_fee.ts';

const fils = (n: number) => Math.round(n * 100);

Deno.test('lines add up to the total exactly, to the fils, across many quotes', () => {
  for (let q = 1; q < 200000; q += 997.37) {
    const c = revealCharge(q, 0.03);
    assertEquals(fils(c.base_fee) + fils(c.processing_fee), fils(c.total_charged), `quote ${q}`);
  }
});

Deno.test('QuotesDone nets at least the full 3% after the published fee', () => {
  for (const q of [10, 99.99, 1000, 12345.67, 250000]) {
    const c = revealCharge(q, 0.03);
    const stripeFee = c.total_charged * STRIPE_CARD_PCT + STRIPE_CARD_FIXED_AED;
    const net = c.total_charged - stripeFee;
    // net >= base, and never more than one fils over (ceil rounding only).
    assertEquals(net + 1e-9 >= c.base_fee, true, `quote ${q}: net ${net} < base ${c.base_fee}`);
    assertEquals(net - c.base_fee < 0.011, true, `quote ${q}: overcharged by ${net - c.base_fee}`);
  }
});

Deno.test('the domestic (UAE card) rate also nets the full 3%, and costs the customer less', () => {
  for (const q of [10, 99.99, 1000, 12345.67, 250000]) {
    const d = revealChargeFor(q, 0.03, 'domestic');
    const net = d.total_charged - (d.total_charged * STRIPE_DOMESTIC_PCT + STRIPE_CARD_FIXED_AED);
    assertEquals(net + 1e-9 >= d.base_fee && net - d.base_fee < 0.011, true, `quote ${q}`);
    assertEquals(d.total_charged <= revealChargeFor(q, 0.03, 'international').total_charged, true);
  }
  assertEquals(revealChargeFor(10000, 0.03, 'domestic'), { base_fee: 300, processing_fee: 9.99, total_charged: 309.99 });
});

Deno.test('worked example: AED 10,000 quote', () => {
  // base 300.00; (300 + 1) / 0.961 = 313.2154 -> ceil 313.22
  assertEquals(revealCharge(10000, 0.03), { base_fee: 300, processing_fee: 13.22, total_charged: 313.22 });
});

Deno.test('an exact division is not rounded up a fils', () => {
  // pct 0.5, fixed 0: (base) / 0.5 is exact
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
  assertEquals(revealCharge(0.5, 0.03).base_fee, 0.02); // 0.015 -> 0.02
  assertEquals(revealCharge(33.33, 0.03).base_fee, 1); // 0.9999 -> 1.00
});
