// The charge's facts (_shared/charge_facts.ts): what the accountant reconciles and when the refund clock starts.
import { assertEquals } from 'jsr:@std/assert@1';
import { chargeFacts } from './charge_facts.ts';

Deno.test('the paid time is the charge\'s own, not the moment our row was written', () => {
  const f = chargeFacts({ amount_received: 77760, latest_charge: { created: 1790242400 } }, { amount: 77760, currency: 'AED', created: 1790242460, fee: 3448 });
  assertEquals(f, { stripe_amount_received_fils: 77760, stripe_bt_amount_fils: 77760, stripe_bt_currency: 'aed', paid_at: new Date(1790242400 * 1000).toISOString() });
});

Deno.test('the balance transaction\'s time stands in only when the charge gives none', () => {
  assertEquals(chargeFacts({ amount_received: 100 }, { amount: 100, currency: 'aed', created: 1790242460 }).paid_at, new Date(1790242460 * 1000).toISOString());
});

Deno.test('a fact Stripe did not give is left out, never guessed', () => {
  assertEquals(chargeFacts({}, null), {});
  assertEquals(chargeFacts({ amount_received: '777' }, { amount: null }), {});
});
