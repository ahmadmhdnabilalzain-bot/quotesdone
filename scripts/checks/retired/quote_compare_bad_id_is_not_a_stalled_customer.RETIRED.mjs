// RETIRED 8 September 2026 — its subject was deleted.
//
// Subject: supabase/functions/quote_compare  —  Quote comparison. Part of the RFQ pipeline, which the founder is rebuilding per agent.
//
// Deleted under the founder's rule of 8 Sep 2026: "if they dont belong to the CEO nor the
// customer support agent then delete". Every function this check reads is gone, so it could
// only ever fail on ENOENT from here.
//
// RETIRED RATHER THAN SOFTENED, deliberately. Editing it to pass would leave a check that goes
// green while the thing it checks does not exist -- which is worse than no check at all,
// because it converts an absence into confidence. Renaming it out of the .test.mjs glob keeps
// the reasoning on disk for whoever rebuilds the surface, and brings nothing green with it.
//
// TO REVIVE: rebuild the subject, then rename this back to .test.mjs and re-point the paths.
// A CALLER'S TYPO WAS RECORDED AS A CUSTOMER LEFT UNABLE TO CHOOSE A SUPPLIER.
//
// 13 Aug 2026. quote_compare logged status='error' for ANY failure to load the inquiry, with one
// fixed narrative: "the customer requested a comparison of their quotes and received a not_found
// instead — they cannot act on the quotes they already paid attention to."
//
// In the 24 hours before this was written the only callers were the platform's own harnesses —
// fx-1 and fx-2 at 01:59, bbbbbbbb-2222-4bbb-8bbb-bbbbbbbbbbbb at 07:14 and 07:21. `fx-1` is not a
// UUID, so Postgres refuses it with 22P02 before any row is looked for. There are 0 inquiries in
// the estate; there was no customer to strand. Those rows are then aggregated by the `it` watcher
// into "N agent run(s) failed in last 24h" — 459 of those incidents in 30 days, the single largest
// source of recommendations in the founder's queue, driven entirely by his own fixtures.
//
// The RESPONSE was never wrong: 404 not_found is right for both. Only the run classification is
// the defect, and this check pins the distinction rather than the status code.
//
//   node --test scripts/checks/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const SRC = readFileSync('supabase/functions/quote_compare/index.ts', 'utf8');

// The not-found branch only; the file has a dozen other logRun sites.
const branch = (() => {
  const at = SRC.indexOf('if (!inq) {');
  assert.ok(at > 0, 'quote_compare no longer has an `if (!inq)` branch this check can read');
  return SRC.slice(at, at + 1800);
})();

test('a malformed inquiry id is not classified as a failure', () => {
  assert.match(branch, /invalid input syntax for type uuid/i,
    'the not-found branch does not distinguish a malformed id from a missing row, so every harness '
    + 'call with a non-UUID is recorded as a customer who could not compare their quotes');
  assert.match(branch, /malformed \? 'ok' : 'error'/,
    "the classification must turn on whether the id was even a UUID — 'ok' for a caller mistake, "
    + "'error' for a well-formed id whose row is genuinely gone");
  assert.match(branch, /bad_request:\s*1/,
    'a caller mistake must be countable in agent_runs.counts, or it cannot be excluded from a watcher');
});

test('a well-formed id with no row is still an error', () => {
  // The direction that matters most: do not quiet a real customer whose inquiry has vanished.
  assert.match(branch, /they cannot act on the quotes they already paid attention to/,
    'the genuine case lost its note — a valid UUID with no row really can be a stranded customer '
    + 'and must stay an error');
});

test('the customer-facing response is unchanged', () => {
  // The API contract was never the defect. A 400 here would be defensible and is NOT what shipped;
  // changing it later should be a deliberate decision, not a side effect of tidying a log.
  const returns = branch.match(/return J\(\{ error: 'not_found' \}, 404\);/g) || [];
  assert.equal(returns.length, 1,
    'the branch must return exactly one 404 not_found for both cases; found ' + returns.length);
  assert.doesNotMatch(branch, /\b400\b/,
    'the not-found branch now returns a 400 for malformed ids — that is an API contract change, '
    + 'not a logging fix, and callers expecting 404 will break');
});
