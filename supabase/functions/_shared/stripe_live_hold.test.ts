// No live card is charged while the Stripe live hold is on (it_engineer, 12 Nov 2026; final audit F4, ledger 1642).
// On main nothing held a live charge: stripe_checkout and supplier_pay chose the live key for every non-demo account and
// went straight to Stripe. These fail if the switch stops failing safe, if test mode becomes held (the e2e reveal runs on the
// Stripe TEST key), or if a function that creates a live charge reaches Stripe before asking.
//   deno test --no-lock --allow-read supabase/functions/_shared/stripe_live_hold.test.ts
import { HELD_FOR_CUSTOMER, HELD_FOR_SUPPLIER, holdApplies, liveChargeHeld, STRIPE_LIVE_HOLD_KEY } from './stripe_live_hold.ts';
import { stripeKeyNames } from './demo_identity.ts';

const eq = (a: unknown, b: unknown, m: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`); };
const ok = (c: boolean, m: string) => { if (!c) throw new Error(m); };

Deno.test('held: absent, empty, on, anything but off', () => {
  for (const v of [undefined, null, '', 'on', 'true', 'held', 'of', 'live']) eq(liveChargeHeld(v), true, `value ${JSON.stringify(v)}`);
});

Deno.test('not held: exactly off (case and spaces ignored)', () => {
  for (const v of ['off', 'OFF', ' Off ']) eq(liveChargeHeld(v), false, `value ${JSON.stringify(v)}`);
});

Deno.test('demo / test mode is never held; a real account in live mode is', () => {
  eq(holdApplies(stripeKeyNames(true).mode, undefined), false, 'a demo account (test key) with the switch absent');
  eq(holdApplies(stripeKeyNames(true).mode, 'on'), false, 'a demo account with the hold on');
  eq(holdApplies(stripeKeyNames(false).mode, undefined), true, 'a real account with the switch absent');
  eq(holdApplies(stripeKeyNames(false).mode, 'off'), false, 'a real account once the founder opens live payments');
});

Deno.test('the person is told plainly, suppliers in English only', () => {
  ok(/opens shortly/.test(HELD_FOR_CUSTOMER.message) && /our team has been told/.test(HELD_FOR_CUSTOMER.message), 'customer message');
  ok(/[؀-ۿ]/.test(HELD_FOR_CUSTOMER.message_ar), 'the customer has the Arabic line');
  ok(!('message_ar' in HELD_FOR_SUPPLIER), 'no Arabic to a supplier (ruling 1008)');
});

Deno.test('every function that creates a live charge asks the hold before its first Stripe call', () => {
  for (const [f, n] of [['../stripe_checkout/index.ts', 1], ['../supplier_pay/index.ts', 2]] as const) {
    const src = Deno.readTextFileSync(new URL(f, import.meta.url));
    const holds = [...src.matchAll(/holdApplies\(\w+\.mode, await secret\(STRIPE_LIVE_HOLD_KEY\)\)/g)].map((m) => m.index!);
    eq(holds.length, n, `${f} asks the hold ${n} time(s)`);
    const keyReads = [...src.matchAll(/await secret\((keys|stripeKeys)\.secret\)/g)].map((m) => m.index!);
    ok(keyReads.length === n && keyReads.every((k, i) => holds[i] < k), `${f}: the hold comes before each live key is read`);
    const firstStripe = src.indexOf('api.stripe.com');
    ok(firstStripe < 0 || firstStripe > holds[0] || /payReveal|element_pay/.test(f), `${f}: no Stripe call before the hold`);
  }
  ok(STRIPE_LIVE_HOLD_KEY === 'stripe_live_hold', 'the switch name');
});
