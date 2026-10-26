// RETIRED 8 September 2026 — its subject was deleted.
//
// Subject: supplier_api
// The supplier API surface. Deleted 8 Sep 2026.
//
// This file reads that source at module top level, so it does not fail an assertion -- it
// cannot start. There is nothing left for it to measure.
//
// RETIRED RATHER THAN SOFTENED. Editing it to pass would leave a check going green while the
// thing it checks does not exist, which converts an absence into confidence.
//
// TO REVIVE: rebuild the subject, then rename back to .test.mjs.
// The companion to supplier_notification_identity.test.mjs, and the reason that one was not enough.
//
// 4 AUG 2026. That guard contains a test named "a failed owner lookup drops the customer free text
// instead of sending it unscrubbed" - and it reads customer_api, whose surfaces are two EMAIL
// bodies. The surface that actually serves buyer free text to every matched supplier before a
// reveal is paid for is the supplier_api inbox, and it had no such concept at all: both owner
// lookups dropped their `error`, so a failed read produced buyerName = null, scrubIdentity skipped
// the name pattern, and summary / spec / boq / budget went out with the buyer named in them. No
// 503, no drop, no log.
//
// The database is not a backstop. On production:
//   select public.mask_contacts('Villa fit-out for Ahmed Khan, call 0501234567 or a@b.com');
//     -> 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]'
// the phone and the address go; the name stays.
//
// Source assertions, like the other checks here: the behaviour lives in a Deno edge function the
// Node runner cannot import, so this asserts the SHAPE that makes the behaviour possible and that
// the old shape is gone. QD_SUPPLIER_API_SRC points the same assertions at an older copy of the
// file, which is how you prove a guard bites instead of trusting that it does.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const target = process.env.QD_SUPPLIER_API_SRC || join(root, 'supabase', 'functions', 'supplier_api', 'index.ts');
const src = readFileSync(target, 'utf8');

// Narrow to the inbox handler, on anchors that are not themselves part of the fix, so no assertion
// can be satisfied by unrelated code elsewhere in a 780-line file.
const start = src.indexOf('const revealedInq = new Set(');
const end = src.indexOf("if (action === 'projects')", start);
assert.ok(start > 0, 'the supplier inbox handler is gone from supplier_api - this guard is now testing nothing');
assert.ok(end > start, 'could not locate the end of the supplier inbox handler');
const inbox = src.slice(start, end);

test('both owner lookups read their error instead of dropping it', () => {
  assert.match(inbox, /let ownerResolved = true;/,
    'the inbox has no ownerResolved discriminator. Without one, "this inquiry has no owner" and "the owner '
    + 'lookup failed" are the same state, and only the first of those is safe to serve free text for.');
  assert.match(inbox, /error:\s*eOwners\s*\}\s*=\s*await admin\.from\('inquiries'\)/,
    'the inquiries owner lookup does not destructure its error, so a failed read is indistinguishable from '
    + 'an inquiry with no customer_id.');
  assert.match(inbox, /if \(eOwners\) ownerResolved = false;/,
    'the inquiries owner lookup destructures its error and then ignores it.');
  assert.match(inbox, /error:\s*eCust\s*\}\s*=\s*await admin\.from\('customers'\)/,
    'the customers name lookup does not destructure its error.');
  assert.match(inbox, /if \(eCust\) ownerResolved = false;/,
    'the customers name lookup destructures its error and then ignores it.');
});

test('every buyer-authored field served pre-reveal is gated on ownerResolved', () => {
  for (const [field, source] of [['sSummary', 'summary'], ['sSpec', 'spec'], ['sBoq', 'boq'], ['sBudget', 'budget']]) {
    assert.match(inbox, new RegExp('const ' + field + ' = revealed \\? i\\.' + source + '[^:]*: \\(ownerResolved \\?'),
      field + ' is not gated on ownerResolved. i.' + source + ' is customer free text and this is a pre-reveal '
      + 'surface: on a failed owner lookup it must be withheld, not scrubbed against a name we could not read.');
  }
});

test('no pre-reveal scrub call survives outside the gate', () => {
  assert.doesNotMatch(inbox, /:\s*scrub(Identity|Deep)\(/,
    'a field still falls straight through to scrubIdentity/scrubDeep with no ownerResolved gate. '
    + 'scrubIdentity(text, null, hits) does not fail - companyRe(null) returns null, the name pattern is never '
    + 'built, and the text is returned with the buyer still named in it.');
});

test('a failed owner lookup is recorded, not merely handled', () => {
  assert.match(inbox, /buyer_identity_unresolved/,
    'the fail-closed path writes no trail. The worst property of the original defect was not that it failed '
    + 'open - it was that it failed open in silence, so the failure had no observable consequence at all.');
});

test('the reveal gate itself is intact', () => {
  assert.match(inbox, /const revealed = revealedInq\.has\(String\(i\.id\)\)/,
    'the paid-reveal check is gone. Everything above is about what happens BEFORE a reveal; if this goes, '
    + 'the distinction it protects goes with it.');
});
