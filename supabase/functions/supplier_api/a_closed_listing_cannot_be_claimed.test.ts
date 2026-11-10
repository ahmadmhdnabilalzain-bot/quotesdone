// A LISTING THE INVITATION PAGE CALLS GONE CANNOT BE CLAIMED BEHIND IT (10 Nov 2026, customer_support, supplier-journey audit).
//
// Two doors read one invitation token and disagreed. claim_lookup (what the page shows) answers not_found for a lead that is
// permanently_closed or banned: a PDPL erasure sets permanently_closed (fn_pdpl_carry_out) and a sanctioned or dues-banned
// company is banned. supplier_api `claim` (what the sign-up does) read only id, claimed and claimed_by, so it attached
// exactly those listings. The portal stores ?t= in sessionStorage BEFORE claim_lookup answers, so a supplier shown "This
// invitation link is not valid or has expired" was, once signed in, silently given the listing anyway. Measured on
// production 10 Nov 2026: 2 permanently_closed leads still hold a claim token, unclaimed.
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/supplier_api/a_closed_listing_cannot_be_claimed.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { listingClosedToClaims } from './create_company.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

Deno.test('the claim refuses exactly what claim_lookup calls not found', () => {
  assertEquals(listingClosedToClaims({ permanently_closed: true, banned: false }), true, 'an erased listing (PDPL) is gone');
  assertEquals(listingClosedToClaims({ permanently_closed: false, banned: true }), true, 'a banned listing is gone');
  assertEquals(listingClosedToClaims({ permanently_closed: false, banned: false }), false);
  assertEquals(listingClosedToClaims({ permanently_closed: null, banned: null }), false, 'unset is open, as claim_lookup reads it');
});

Deno.test('claim reads the two columns and answers not_found before anything is written', () => {
  const src = functionSource('supplier_api');
  const at = src.indexOf("if (action === 'claim')");
  assert(at >= 0, 'claim handler not found');
  const claim = src.slice(at, src.indexOf('\n', at));
  assert(/eq\('claim_token', token\)/.test(claim));
  const sel = claim.match(/select\('([^']*)'\)\.eq\('claim_token', token\)/);
  assert(sel && /permanently_closed/.test(sel[1]) && /banned/.test(sel[1]), 'the token row is read with permanently_closed and banned: ' + (sel && sel[1]));
  const refuse = claim.indexOf('listingClosedToClaims(row)');
  assert(refuse > 0, 'the claim asks listingClosedToClaims');
  assert(refuse < claim.indexOf(".update({ claimed: true"), 'refused before the claim write');
  assert(/listingClosedToClaims\(row\) && row\.claimed_by !== email\) return J\(\{ error: 'not found', code: 'not_found' \}, 404\)/.test(claim), 'answered as claim_lookup answers it, and never taken from the account that already holds it');
});
