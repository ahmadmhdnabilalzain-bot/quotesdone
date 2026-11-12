// What the callers of fn_match_capability do with a partner match (founder rulings 1647 and 24 Sep 2026).
// Nobody is held back here: the matcher orders a partner-only supplier last, and every row it returns is invited
// (scripts/checks/a_partner_service_is_matched_knowingly.test.mjs and its probe prove that on production).
//   deno test supabase/functions/_shared/partner_match.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import * as partnerMatch from './partner_match.ts';
import { partnerHitsOf, partnerOnly, throughPartner, withoutPartnerWhy } from './partner_match.ts';

const P = 'swimming_pools.pool_construction', M = 'swimming_pools.pool_maintenance';

Deno.test('nothing in the module can hold a matched supplier back (any number may quote, 24 Sep 2026)', () => {
  assertEquals(Object.keys(partnerMatch).sort(), ['partnerHitsOf', 'partnerOnly', 'throughPartner', 'withoutPartnerWhy']);
});

Deno.test('partner-only and through-a-partner are told apart', () => {
  assertEquals([partnerOnly({ service_hits: [P], partner_hits: [P] }), throughPartner({ service_hits: [P], partner_hits: [P] })], [true, true]);
  assertEquals([partnerOnly({ service_hits: [P, M], partner_hits: [P] }), throughPartner({ service_hits: [P, M], partner_hits: [P] })], [false, true]);
  assertEquals([partnerOnly({ service_hits: [P], partner_hits: [] }), throughPartner({ service_hits: [P] })], [false, false]);
  assertEquals(partnerOnly({ service_hits: [], partner_hits: [] }), false);
  assertEquals(partnerHitsOf({}), []);
});

Deno.test('the customer is not told: the partner segment leaves the reason, everything else stays', () => {
  const why = 'trades swimming_pools · 1/1 services · through a partner: swimming_pools.pool_construction · in Dubai';
  assertEquals(withoutPartnerWhy(why), 'trades swimming_pools · 1/1 services · in Dubai');
  assertEquals(withoutPartnerWhy('through a partner: a.b'), '');
  assertEquals(withoutPartnerWhy('trades hvac · 2/2 services'), 'trades hvac · 2/2 services');
  assertEquals(withoutPartnerWhy(null), '');
});
