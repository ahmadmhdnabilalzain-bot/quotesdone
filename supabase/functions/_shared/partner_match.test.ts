// What the callers of fn_match_capability do with a partner match (founder rulings 1647 and 24 Sep 2026).
// Nobody is held back here: the matcher orders a partner-only supplier last, and every row it returns is invited
// (scripts/checks/a_partner_service_is_matched_knowingly.test.mjs and its probe prove that on production).
//   deno test supabase/functions/_shared/partner_match.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import * as partnerMatch from './partner_match.ts';
import { partnerHitsOf, partnerOnly, scoreInMatcherOrder, throughPartner, withoutPartnerWhy } from './partner_match.ts';

const P = 'swimming_pools.pool_construction', M = 'swimming_pools.pool_maintenance';

Deno.test('nothing in the module can hold a matched supplier back (any number may quote, 24 Sep 2026)', () => {
  assertEquals(Object.keys(partnerMatch).sort(), ['partnerHitsOf', 'partnerOnly', 'scoreInMatcherOrder', 'throughPartner', 'withoutPartnerWhy']);
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

Deno.test('3 own-team suppliers and 1 partner-only one who outscores them: all 4 kept, the partner-only one 4th in every number', () => {
  // the matcher's order: own team first (fn_match_capability), the partner-only supplier last although his score is 60
  const rows = [{ id: 1, score: 45, service_hits: [P], partner_hits: [] }, { id: 2, score: 40, service_hits: [P], partner_hits: [] },
                { id: 3, score: 35, service_hits: [P], partner_hits: [] }, { id: 9, score: 60, service_hits: [P], partner_hits: [P] }];
  const ranked = scoreInMatcherOrder(rows);
  assertEquals(ranked, [45, 40, 35, 35]);
  // the percentage a customer reads (inquiry_matches.similarity -> match_pct) ranks him 4th, never above the own team
  const byPct = rows.map((r, i) => ({ id: r.id, pct: Math.round(ranked[i]) })).sort((a, b) => b.pct - a.pct || 0);
  assertEquals(byPct.map((x) => x.id), [1, 2, 3, 9]);
  assertEquals(ranked.length, 4);
});

Deno.test('the cap leaves every other score as it is', () => {
  // no partner service, a mixed supplier (part himself), no own team at all, no service named
  assertEquals(scoreInMatcherOrder([{ score: 50, service_hits: [P] }, { score: 20 }]), [50, 20]);
  assertEquals(scoreInMatcherOrder([{ score: 70, service_hits: [P, M], partner_hits: [P] }, { score: 30, service_hits: [P] }]), [70, 30]);
  assertEquals(scoreInMatcherOrder([{ score: 70, service_hits: [P], partner_hits: [P] }]), [70]);
  assertEquals(scoreInMatcherOrder([]), []);
});
