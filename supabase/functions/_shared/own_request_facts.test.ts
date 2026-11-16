// own_request_facts.test.ts — every channel tells the model to answer his own request from the facts, and a sealed quote's own
// words pass the code generaliser. Ids and names are ZZ DEMO shapes.
import { assert, assertEquals, assertMatch, assertNotMatch } from 'jsr:@std/assert@1';
import { generaliseOwnRequestFacts, OWN_REQUEST_RULE, withoutDuplicateRequests } from './own_request_facts.ts';

const PACK = { identity: { kind: 'customer', requests: [{ ref: 14, asked: { budget_as_he_stated_it: 'AED 5,000 excluding VAT' }, quotes: [
  { letter: 'A', price_ex_vat_aed: 4600, revealed: false, warranty_as_stated: '2 years Grohe mixer', lead_time_as_stated: '3 days', validity_as_stated: '30 days' },
  { letter: 'B', price_ex_vat_aed: 4900, revealed: true, supplier: 'ZZ DEMO Revealed Co', warranty_as_stated: '2 years Grohe mixer' },
] }] } };

Deno.test('the rule names every fact the scenarios need and forbids invention, identity and a claimed change', () => {
  for (const k of ['asked', 'changes_he_sent_after', 'comparison', 'budget', 'VAT', 'lead time', 'brand', 'AED', '3.6725', 'reveal', 'cancel']) assert(OWN_REQUEST_RULE.includes(k), k);
  assertMatch(OWN_REQUEST_RULE, /Never ask again/);
  assertMatch(OWN_REQUEST_RULE, /Never state a price, date, count or brand the record does not hold/);
  assertMatch(OWN_REQUEST_RULE, /never a supplier's name, contact or brand/);
  assertMatch(OWN_REQUEST_RULE, /never say it is done/);
});

Deno.test('a sealed quote loses a known brand in its own words; a revealed one and the prices do not change', () => {
  const g = generaliseOwnRequestFacts(PACK);
  const [a, b] = g.identity.requests[0].quotes as Record<string, unknown>[];
  assertNotMatch(String(a.warranty_as_stated), /Grohe/);
  assertEquals(a.lead_time_as_stated, '3 days');
  assertEquals(a.validity_as_stated, '30 days');
  assertEquals(a.price_ex_vat_aed, 4600);
  assertEquals(b.warranty_as_stated, '2 years Grohe mixer');
  assertEquals(g.identity.requests[0].asked.budget_as_he_stated_it, 'AED 5,000 excluding VAT');
  assertEquals(PACK.identity.requests[0].quotes[0].warranty_as_stated, '2 years Grohe mixer', 'the input is not changed');
});

Deno.test('the own record points at the fact pack instead of carrying the same requests twice', () => {
  const mine = { known: true, name: 'ZZ DEMO', inquiries: PACK.identity.requests };
  assertEquals(withoutDuplicateRequests(mine, PACK).inquiries, 'the same requests as FACT PACK identity.requests below');
  assertEquals(withoutDuplicateRequests(mine, null).inquiries, mine.inquiries);
  assertEquals(withoutDuplicateRequests(mine, { identity: { kind: 'unknown' } }).inquiries, mine.inquiries);
});
