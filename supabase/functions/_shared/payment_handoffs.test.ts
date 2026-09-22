// The pure half of the payment handoffs: the shape of the list of conversations the seats have about
// money. The database half (every handoff created and consumed, on ZZ DEMO fixtures, inside a
// rolled-back transaction) is scripts/checks/payments_are_the_accountant.test.mjs, which needs a
// management token; this file needs nothing and runs everywhere.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { HANDOFF_TYPES } from './payment_handoffs.ts';

Deno.test('every conversation is between real seats and listed once', () => {
  const seats = new Set(['accountant', 'sales_engineer', 'customer_support', 'ceo', 'it_engineer', 'marketing']);
  const keys = HANDOFF_TYPES.map((h) => `${h.type}|${h.from}|${h.to}`);
  assertEquals(new Set(keys).size, keys.length);
  // The one conversation a seat has with itself: support's own notice (a receipt, a contact-form
  // alert) is queued and checked like any other (every_send_comes_back_to_whoever_asked.sql).
  // The complaint clock (22 Sep 2026, PR #811) is support's own queue too: it holds each complaint as a
  // complaint.due item until the Complaints Policy's final response is given.
  const selfTalk = (h: { type: string; from: string; to: string }) => h.from === 'customer_support' && h.to === 'customer_support'
    && (h.type === 'delivery.request' || h.type === 'delivery.result' || h.type === 'complaint.due');
  for (const h of HANDOFF_TYPES) assert(seats.has(h.from) && seats.has(h.to) && (h.from !== h.to || selfTalk(h)), JSON.stringify(h));
});

Deno.test('the accountant and the sales engineer talk in both directions', () => {
  assert(HANDOFF_TYPES.some((h) => h.from === 'accountant' && h.to === 'sales_engineer'));
  assert(HANDOFF_TYPES.some((h) => h.from === 'sales_engineer' && h.to === 'accountant'));
});

// Founder, 14 Sep 2026: "nothing literally should ever be a one way communication". Support carries
// every send, and every seat that asks for one hears back what became of it.
Deno.test('only customer_support delivers, and every seat that asks hears back', () => {
  for (const h of HANDOFF_TYPES.filter((x) => x.type === 'delivery.request')) assertEquals(h.to, 'customer_support');
  // what support says to ANOTHER seat is only ever the answer to a send it was asked for
  for (const h of HANDOFF_TYPES.filter((x) => x.from === 'customer_support' && x.to !== 'customer_support')) assertEquals(h.type, 'delivery.result');
  for (const h of HANDOFF_TYPES.filter((x) => x.type === 'delivery.request')) {
    assert(HANDOFF_TYPES.some((r) => r.type === 'delivery.result' && r.from === 'customer_support' && r.to === h.from),
      `${h.from} asks for deliveries and gets no delivery.result back`);
  }
});

Deno.test('the CEO sends back work to the two seats that own it, never to support', () => {
  for (const h of HANDOFF_TYPES.filter((x) => x.type === 'refund.remediate' || x.type === 'incident.fix')) {
    assertEquals(h.from, 'ceo');
    assert(h.to === 'accountant' || h.to === 'sales_engineer', JSON.stringify(h));
  }
});

// THE MARKETING SEAT (founder instruction 721, 22 Sep 2026). It reports the picture to the CEO and nothing
// comes back as an approval; ad spend goes to the accountant and the accountant answers; it reaches people
// by email or WhatsApp only through customer_support, and hears back what became of each send.
Deno.test('marketing reports to the CEO, talks money with the accountant both ways, and sends through support', () => {
  const has = (type: string, from: string, to: string) => HANDOFF_TYPES.some((h) => h.type === type && h.from === from && h.to === to);
  assert(has('marketing.report', 'marketing', 'ceo'));
  assert(has('adspend.recorded', 'marketing', 'accountant') && has('adspend.booked', 'accountant', 'marketing'));
  assert(has('delivery.request', 'marketing', 'customer_support') && has('delivery.result', 'customer_support', 'marketing'));
  // the CEO steers marketing with the daily plan's directive (it owns the demand stage) and approves nothing
  assertEquals(HANDOFF_TYPES.filter((h) => h.from === 'ceo' && h.to === 'marketing').map((h) => h.type), ['ceo.directive']);
  // and marketing asks nobody but these three
  for (const h of HANDOFF_TYPES.filter((x) => x.from === 'marketing')) assert(['ceo', 'accountant', 'customer_support'].includes(h.to), JSON.stringify(h));
});
