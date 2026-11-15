// The charge's facts (_shared/charge_facts.ts): what the accountant reconciles, when the refund clock starts, a dispute's fee.
import { assertEquals } from 'jsr:@std/assert@1';
import { chargeFacts, chargePaidAt, disputeFees } from './charge_facts.ts';

Deno.test('the figures and the paid time are read apart, so a sale that already has paid_at still gets its figures', () => {
  const pi = { amount_received: 77760, latest_charge: { created: 1790242400 } }, bt = { amount: 77760, currency: 'AED', created: 1790242460, fee: 3448 };
  assertEquals(chargeFacts(pi, bt), { stripe_amount_received_fils: 77760, stripe_bt_amount_fils: 77760, stripe_bt_currency: 'aed' });
  assertEquals(chargePaidAt(pi, bt), new Date(1790242400 * 1000).toISOString());
});

Deno.test('the balance transaction\'s time stands in only when the charge gives none', () => {
  assertEquals(chargePaidAt({ amount_received: 100 }, { amount: 100, currency: 'aed', created: 1790242460 }), new Date(1790242460 * 1000).toISOString());
});

Deno.test('a fact Stripe did not give is left out, never guessed', () => {
  assertEquals(chargeFacts({}, null), {});
  assertEquals(chargeFacts({ amount_received: '777' }, { amount: null }), {});
  assertEquals(chargePaidAt({}, null), null);
});

Deno.test('a dispute\'s fee is what its balance transactions charged, and what came back is counted apart', () => {
  assertEquals(disputeFees({ balance_transactions: [{ amount: -77760, fee: 5500 }] }), { fee_fils: 5500, fee_returned_fils: 0 });
  assertEquals(disputeFees({ balance_transactions: [{ amount: -77760, fee: 5500 }, { amount: 77760, fee: -5500 }] }), { fee_fils: 5500, fee_returned_fils: 5500 });
  assertEquals(disputeFees({ id: 'dp_x' }), null);
});
