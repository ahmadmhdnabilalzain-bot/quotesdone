// A REQUEST THE MATCHER COULD NOT REACH IS MATCHED AGAIN, AND NO SURFACE CALLS IT "NO SUPPLIER" (sales_engineer,
// customer-journey follow-up 10 Nov 2026; founder ruling 1608).
//
// MEASURED on origin/main: a request the sales engineer's matcher did not answer was never asked again, was told at post
// time and in its first-request letter "we are still registering suppliers for this trade", was put in the stalled-supplier
// rescue ("none of the suppliers registered for it can take it on"), and after 14 days was closed with the same false
// reason. This holds the four database routines (as the last applied-or-pending file defines them) and the portal to the
// fix; customer_api/rematch.test.ts holds the sweep and matchAndNotify, and the file's _probe.sql proves the behaviour
// rolled back on production.
//   node --test scripts/checks/a_request_the_matcher_could_not_reach_is_matched_again.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, read } from '../lib/canonical_body.mjs';

test('the 14-day closer waits for the re-match and, once it is spent, gives our fault as the reason', () => {
  const { body } = canonicalBody('fn_sales_engineer_closes_unreached_requests');
  assert.match(body, /matcher_unavailable[\s\S]{0,200}rematch,exhausted/, 'the closer does not skip a request whose re-match is running');
  assert.match(body, /a fault on our side/, 'a request the matcher never reached is closed as "still registering suppliers"');
});

test('a request waiting on the re-match is not "no reachable supplier", and its letter says "we are matching"', () => {
  assert.match(canonicalBody('fn_stalled_inquiry_flag').body, /matcher_unavailable[\s\S]{0,400}'waiting for the re-match'/, 'the rescue flag takes a request the matcher never searched');
  assert.match(canonicalBody('fn_customer_concierge_held').body, /'matching', true/, 'the concierge reads a waiting request as finding_suppliers');
  assert.match(canonicalBody('fn_customer_concierge_message').body, /We are matching your request/, 'the first-request letter does not say we are matching it');
  assert.match(canonicalBody('fn_sales_engineer_rematch_told').body, /fn_customer_support_duty_send\('rematch\.matched'/, 'the customer is not told the re-match reached suppliers');
});

test('the portal says "we are matching" for a request, or a part, the matcher did not answer', () => {
  const nr = read('src/components/me/NewRequest.tsx');
  assert.match(nr, /posted\.matching \? 'nr_posted_matching' : 'nr_posted_none'/, 'the composer says "no supplier" over a trade never searched');
  assert.match(nr, /!\(c && c\.matching\)/, 'a waiting part is listed as "still registering suppliers"');
  const txt = read('src/components/me/portalText.ts');
  assert.equal((txt.match(/nr_posted_matching:/g) || []).length, 2, 'nr_posted_matching is written in English and Arabic');
  assert.match(read('supabase/functions/_shared/inquiry_posted.ts'), /matching_pending: !!\(routing/, 'the posted answer does not carry matching_pending');
});
