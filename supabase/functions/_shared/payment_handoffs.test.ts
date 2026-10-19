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
    && (h.type === 'delivery.request' || h.type === 'delivery.result' || h.type === 'complaint.due' || h.type === 'support.case_open' || h.type === 'support.human_requested');
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
  // — and one named exception (#904): a post-reveal dispute's fault finding goes to the CEO, who decides disputes,
  // on the cross-family review machine. It asks for a decision; it delivers nothing.
  // — and a second named exception (founder instruction 1009, #1066): a support cause recurring past the weekly
  // threshold goes to the seat that owns it as support.root_cause; support measures the weekly volume afterwards and
  // closes it when it falls. It asks the owner to change what produces the cause; it delivers nothing.
  const ROOT_CAUSE_OWNERS = ['sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'];
  for (const h of HANDOFF_TYPES.filter((x) => x.from === 'customer_support' && x.to !== 'customer_support')) {
    if (h.type === 'deliberation.review' && h.to === 'ceo') continue;
    if (h.type === 'support.root_cause' && ROOT_CAUSE_OWNERS.includes(h.to)) continue;
    // — and a third (#1186, 5 Oct 2026): a customer's "not sure" on a held spec goes to the sales engineer, who owns
    // specs, as spec.not_sure; it asks for his answer on that spec (handler fn_sales_engineer_spec_handoff_waits) and
    // delivers nothing.
    if (h.type === 'spec.not_sure' && h.to === 'sales_engineer') continue;
    // — and a fourth (founder_instruction 1059, MANIFEST 1894): when a submission support made was sent back 4 times
    // or its revision stalled, the CEO is owed a final decision as ceo.decision_owed; it asks for that decision and
    // delivers nothing.
    if (h.type === 'ceo.decision_owed' && h.to === 'ceo') continue;
    // — and a fifth (legal finding 1, #1512): an objection to an automated decision that support did not resolve goes
    // to the CEO as support.decision_objection; it asks for the CEO's reply and delivers nothing.
    if (h.type === 'support.decision_objection' && h.to === 'ceo') continue;
    assertEquals(h.type, 'delivery.result');
  }
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
  // the CEO steers marketing (the daily plan's directive, the month directive, a root-cause question on a missed
  // target, an assigned improvement) and approves nothing; since founder_instruction 1059 it also returns its reasons
  // on a submission (ceo.revise) and its final decision on one (ceo.decision_closed) — reasons, not approval
  assertEquals(HANDOFF_TYPES.filter((h) => h.from === 'ceo' && h.to === 'marketing').map((h) => h.type).sort(),
    ['ceo.decision_closed', 'ceo.directive', 'ceo.improvement', 'ceo.month_directive', 'ceo.revise', 'ceo.root_cause']);
  // marketing's month plan reaches the CEO for judgement as a review on another model family (866, 873); the quarterly
  // brand review and the monthly GEO report are read by the CEO as marketing.review (ledger 983, gap 8); a submission
  // sent back 4 times or stalled owes the CEO a final decision as ceo.decision_owed (founder_instruction 1059)
  // and the daily lead-sourcing report (counts by trade, no company names) as marketing.lead_sourcing (#1304, 12 Oct)
  assertEquals(HANDOFF_TYPES.filter((h) => h.from === 'marketing' && h.to === 'ceo').map((h) => h.type).sort(), ['ceo.decision_owed', 'deliberation.review', 'marketing.lead_sourcing', 'marketing.report', 'marketing.review']);
  // and marketing asks nobody else; the one exception is a public comment's lead, handed to sales_engineer
  // (instruction 866, 23 Sep 2026), and the escalation of a comment that must not be answered in public
  assert(has('social.lead', 'marketing', 'sales_engineer') && has('social.escalation', 'marketing', 'customer_support'));
  for (const h of HANDOFF_TYPES.filter((x) => x.from === 'marketing')) {
    assert(['ceo', 'accountant', 'customer_support'].includes(h.to) || (h.type === 'social.lead' && h.to === 'sales_engineer'), JSON.stringify(h));
  }
  assertEquals(HANDOFF_TYPES.filter((h) => h.from === 'marketing').map((h) => h.type + '>' + h.to).sort(),
    ['adspend.recorded>accountant', 'ceo.decision_owed>ceo', 'deliberation.review>ceo', 'delivery.request>customer_support', 'marketing.lead_sourcing>ceo', 'marketing.report>ceo', 'marketing.review>ceo', 'social.escalation>customer_support', 'social.lead>sales_engineer']);
});
