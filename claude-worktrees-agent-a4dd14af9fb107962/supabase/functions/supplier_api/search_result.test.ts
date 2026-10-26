// deno test --no-lock --node-modules-dir=auto supabase/functions/supplier_api/search_result.test.ts
//
// The 'search' action must never hand one supplier another supplier's account e-mail. Pure function,
// no network, no real row: the addresses below are RFC 2606 .invalid and cannot reach anyone.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { searchResult } from './search_result.ts';

const me = 'zz-demo-me@example.invalid';
const other = 'zz-demo-owner@example.invalid';
const base = { id: 7, company_name: 'ZZ DEMO — Search Co', emirate: 'Dubai', business_role: 'supplier' };

Deno.test('the claiming account e-mail never leaves the function', () => {
  const out = searchResult({ ...base, claimed: true, claimed_by: other }, me);
  assert(!('claimed_by' in out), 'claimed_by must not be in the result');
  assert(!JSON.stringify(out).includes(other), 'the owner address must not appear anywhere in the result');
  assertEquals(Object.keys(out).sort(), ['business_role', 'claimable', 'claimed', 'company_name', 'emirate', 'id']);
});

Deno.test('claimable: unclaimed yes, claimed by someone else no, claimed by me yes', () => {
  assertEquals(searchResult({ ...base, claimed: false, claimed_by: null }, me).claimable, true);
  assertEquals(searchResult({ ...base, claimed: null, claimed_by: null }, me).claimable, true);
  assertEquals(searchResult({ ...base, claimed: true, claimed_by: other }, me).claimable, false);
  assertEquals(searchResult({ ...base, claimed: true, claimed_by: ' ZZ-DEMO-ME@EXAMPLE.INVALID ' }, me).claimable, true);
});

Deno.test('a claimed listing with no recorded owner is not claimable', () => {
  assertEquals(searchResult({ ...base, claimed: true, claimed_by: null }, me).claimable, false);
});
