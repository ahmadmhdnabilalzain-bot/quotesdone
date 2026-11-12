// The two partner rules the callers of fn_match_capability apply (services/REPORT.md 3.7; founder ruling 1647).
//   deno test supabase/functions/_shared/partner_match.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { invitedUnderPartnerRule, partnerOnly, throughPartner, withoutPartnerWhy } from './partner_match.ts';

const own = (id: number, hits: string[]) => ({ id, service_hits: hits, partner_hits: [] as string[] });
const partner = (id: number, hits: string[], via: string[]) => ({ id, service_hits: hits, partner_hits: via });
const P = 'swimming_pools.pool_construction', M = 'swimming_pools.pool_maintenance', L = 'landscaping.softscape';

Deno.test('a partner-only supplier is invited when fewer than 3 own-team suppliers matched', () => {
  const rows = [own(1, [P]), own(2, [P]), partner(9, [P], [P])];
  assertEquals(invitedUnderPartnerRule(rows, [P]).map((r) => r.id), [1, 2, 9]);
});

Deno.test('a partner-only supplier is NOT invited when 3 or more own-team suppliers matched', () => {
  const rows = [own(1, [P]), own(2, [P]), own(3, [P]), partner(9, [P], [P])];
  assertEquals(invitedUnderPartnerRule(rows, [P]).map((r) => r.id), [1, 2, 3]);
});

Deno.test('a request across two trades invites the one who does part himself and the rest through a partner', () => {
  // garden and pool: he plants himself and builds the pool through his partner, so he can take the job whole
  const rows = [own(1, [P]), own(2, [P]), own(3, [L]), partner(9, [L, P], [P])];
  assertEquals(invitedUnderPartnerRule(rows, [L, P]).map((r) => r.id), [1, 2, 3, 9]);
  // the same supplier on a single-trade request with 3 own-team suppliers is not invited
  const one = [own(1, [P, M]), own(2, [P, M]), own(3, [P, M]), partner(9, [M, P], [P])];
  assertEquals(invitedUnderPartnerRule(one, [P, M]).map((r) => r.id), [1, 2, 3]);
  // and a partner-only supplier on a two-trade request does nothing himself: invited only under the count rule
  const far = [own(1, [P]), own(2, [P]), own(3, [L]), partner(9, [P, L], [P, L])];
  assertEquals(invitedUnderPartnerRule(far, [L, P]).map((r) => r.id), [1, 2, 3]);
});

Deno.test('rows from a matcher without partner_hits, and requests naming no service, are invited as before', () => {
  const rows = [{ id: 1, service_hits: [P] }, { id: 2 }, { id: 3, service_hits: [] }, { id: 4 }];
  assertEquals(invitedUnderPartnerRule(rows, []).map((r) => r.id), [1, 2, 3, 4]);
});

Deno.test('partner-only and through-a-partner are told apart', () => {
  assertEquals([partnerOnly(partner(1, [P], [P])), throughPartner(partner(1, [P], [P]))], [true, true]);
  assertEquals([partnerOnly(partner(1, [P, M], [P])), throughPartner(partner(1, [P, M], [P]))], [false, true]);
  assertEquals([partnerOnly(own(1, [P])), throughPartner(own(1, [P]))], [false, false]);
  assertEquals(partnerOnly({ service_hits: [], partner_hits: [] }), false);
});

Deno.test('the customer is not told: the partner segment leaves the reason, everything else stays', () => {
  const why = 'trades swimming_pools · 1/1 services · through a partner: swimming_pools.pool_construction · in Dubai';
  assertEquals(withoutPartnerWhy(why), 'trades swimming_pools · 1/1 services · in Dubai');
  assertEquals(withoutPartnerWhy('through a partner: a.b'), '');
  assertEquals(withoutPartnerWhy('trades hvac · 2/2 services'), 'trades hvac · 2/2 services');
  assertEquals(withoutPartnerWhy(null), '');
});
