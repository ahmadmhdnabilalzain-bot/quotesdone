// The pure half of the payment handoffs: the shape of the list of conversations the seats have about
// money. The database half (every handoff created and consumed, on ZZ DEMO fixtures, inside a
// rolled-back transaction) is scripts/checks/payments_are_the_accountant.test.mjs, which needs a
// management token; this file needs nothing and runs everywhere.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { HANDOFF_TYPES } from './payment_handoffs.ts';

Deno.test('every conversation is between real seats and listed once', () => {
  const seats = new Set(['accountant', 'sales_engineer', 'customer_support', 'ceo', 'it_engineer']);
  const keys = HANDOFF_TYPES.map((h) => `${h.type}|${h.from}|${h.to}`);
  assertEquals(new Set(keys).size, keys.length);
  for (const h of HANDOFF_TYPES) assert(seats.has(h.from) && seats.has(h.to) && h.from !== h.to, JSON.stringify(h));
});

Deno.test('the accountant and the sales engineer talk in both directions', () => {
  assert(HANDOFF_TYPES.some((h) => h.from === 'accountant' && h.to === 'sales_engineer'));
  assert(HANDOFF_TYPES.some((h) => h.from === 'sales_engineer' && h.to === 'accountant'));
});

Deno.test('only customer_support delivers, and it answers only the sales engineer', () => {
  for (const h of HANDOFF_TYPES.filter((x) => x.type === 'delivery.request')) assertEquals(h.to, 'customer_support');
  for (const h of HANDOFF_TYPES.filter((x) => x.from === 'customer_support')) assertEquals(h.to, 'sales_engineer');
});

Deno.test('the CEO sends back work to the two seats that own it, never to support', () => {
  for (const h of HANDOFF_TYPES.filter((x) => x.type === 'refund.remediate' || x.type === 'incident.fix')) {
    assertEquals(h.from, 'ceo');
    assert(h.to === 'accountant' || h.to === 'sales_engineer', JSON.stringify(h));
  }
});
