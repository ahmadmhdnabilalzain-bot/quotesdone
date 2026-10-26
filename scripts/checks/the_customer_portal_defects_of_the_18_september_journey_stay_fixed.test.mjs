// THE CUSTOMER-PORTAL DEFECTS OF THE 18 SEPTEMBER BROWSER JOURNEY STAY FIXED.
//
// it_engineer, 21 Sep 2026. Four browser_journey findings from 18 Sep were still open on
// public.it_engineer_finding although the code had been fixed. Two of the four already had a guard
// (the Arabic-date one: ltr_is_never_forced_onto_a_localised_date.test.mjs; the rating one:
// supabase/functions/customer_api/rating_input.test.ts and the reviews_reason_required probe in
// scripts/sql/a_customer_is_never_blocked_from_rating.sql). The other two had none, so nothing
// would fail if the same cause came back. This file is that guard (founder, 21 Sep 2026: "i dont
// want things to pop up again for the same reasons").
//
//   1. browser_journey:a_revealed_request_still_shows_reveal_as_not_reached
//      The Journey rail lit its last node only from rfqStageIdx, which reaches its top index on a
//      HIRE, not a reveal — so a paid reveal still showed "Reveal" grey. Fixed by lighting the last
//      node from the reveal itself (`revealed ? JOURNEY.length - 1`) and passing `revealed`.
//   2. browser_journey:the_first_request_flashes_the_you_have_none_empty_state_after_it_is_sent
//      The skeleton was gated on `booting` alone (true only before the first load ever), so the
//      refresh after the first post showed "you have no requests" for 0.3-1.5 s. Fixed by a
//      `posting` flag that also holds the skeleton.
//
// Comments are masked before matching so this file's own prose cannot satisfy it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const path = new URL('../../src/components/me/CustomerPortal.tsx', import.meta.url);
const code = readFileSync(path, 'utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, (m) => m.replace(/[^\n]/g, ' '));

// 5 Oct 2026 (sales_engineer, T2): the Journey rail was replaced by the request tracker
// (src/components/me/requestTracker.ts). The property is unchanged and is now EXECUTED: a paid
// reveal, with no hire, lights "Revealed" from the reveal itself.
test('a revealed request lights the Revealed stage of the request tracker', async () => {
  const { trackerOf } = await import('../../src/components/me/requestTracker.ts');
  const tr = trackerOf({ status: 'quoted', rfq_ready: true }, [{ revealed: true }, {}], 'en');
  const rev = tr.stages.find((s) => s.key === 'revealed');
  assert.equal(rev.done, true, 'a paid reveal no longer lights the Revealed stage');
  assert.match(code, /<RequestTracker\b[^>]*\bquotes=\{/, 'no caller passes the quotes to <RequestTracker>');
});

test('the request-list skeleton also covers the refresh after a post', () => {
  assert.match(code, /\{\s*booting\s*\|\|\s*posting\s*\?/, 'the skeleton is gated on `booting` alone again');
  assert.match(code, /setPosting\(true\)/, 'nothing sets `posting` when a request is sent');
  assert.match(code, /\.finally\(\(\)\s*=>\s*setPosting\(false\)\)/, 'the list refresh no longer clears `posting` in .finally');
});
