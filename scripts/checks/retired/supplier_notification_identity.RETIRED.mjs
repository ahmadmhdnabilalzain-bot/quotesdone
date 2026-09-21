// RETIRED 8 September 2026 — its subject was deleted.
//
// Subject: customer_api
// The customer API surface. Deleted 8 Sep 2026.
//
// This file reads that source at module top level, so it does not fail an assertion -- it
// cannot start. There is nothing left for it to measure.
//
// RETIRED RATHER THAN SOFTENED. Editing it to pass would leave a check going green while the
// thing it checks does not exist, which converts an absence into confidence.
//
// TO REVIVE: rebuild the subject, then rename back to .test.mjs.
// A supplier must not learn the buyer's NAME from an email before a reveal is paid for.
//
// Audit 1.5. customer_api has two supplier-facing notification bodies - `new_inquiry` (every matched
// supplier, at dispatch) and `job_awarded_other` (every losing supplier, after the award). Both
// called scrubIdentity(text, null, []). companyRe(null) returns null, so the name pattern was never
// added to the loop and only ID_PATTERNS ran: emails, URLs, messenger links, UAE phone numbers.
// The buyer's name went out verbatim to every matched supplier.
//
// Two things made this survive a year of review. The portal is correct - supplier_api resolves
// buyerName from inquiries.customer_id -> customers.full_name and passes it into the SAME function -
// so the rule looked implemented. And the database looked like a backstop but is not: on production,
//   select public.mask_contacts('Villa fit-out for Ahmed Khan, call 0501234567 or a@b.com');
//     -> 'Villa fit-out for Ahmed Khan, call [hidden] or [hidden]'
// the phone and the address go, the name stays.
//
// Source assertions, like the other checks here: the behaviour lives in a Deno edge function the
// Node test runner cannot import, so the guard asserts the SHAPE that makes the behaviour possible
// and asserts the old broken shape is gone. QD_CUSTOMER_API_SRC lets qd-check point these same
// assertions at an older copy of the file to prove they bite.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const target = process.env.QD_CUSTOMER_API_SRC || join(root, 'supabase', 'functions', 'customer_api', 'index.ts');
const src = readFileSync(target, 'utf8');

// Narrow to the two notification bodies, so no assertion can be satisfied by unrelated code.
const losersStart = src.indexOf('async function notifyLosers(');
const losersEnd = src.indexOf('async function flagCoverageGap(') > losersStart
  ? src.indexOf('async function flagCoverageGap(')
  : src.indexOf('async function matchAndNotify(');
assert.ok(losersStart > 0, 'notifyLosers is gone from customer_api - this guard is now testing nothing');
assert.ok(losersEnd > losersStart, 'could not locate the end of notifyLosers');
const losers = src.slice(losersStart, losersEnd);

const dispatchStart = src.indexOf('async function matchAndNotify(');
const dispatchEnd = src.indexOf('type Cfg =', dispatchStart);
assert.ok(dispatchStart > 0, 'matchAndNotify is gone from customer_api - this guard is now testing nothing');
assert.ok(dispatchEnd > dispatchStart, 'could not locate the end of matchAndNotify');
const dispatch = src.slice(dispatchStart, dispatchEnd);

test('the buyer name is resolved before either supplier email is composed', () => {
  assert.match(src, /async function buyerNameOf\(/,
    'buyerNameOf is missing. Without it neither notification body has a name to remove and scrubIdentity ' +
    'falls back to contact patterns only.');
  assert.match(losers, /await buyerNameOf\(inquiryId\)/,
    'notifyLosers does not resolve the buyer name, so the quoted job summary is emailed to every LOSING ' +
    'supplier with the buyer named in it. Those suppliers never paid for a reveal.');
  assert.match(dispatch, /await buyerNameOf\(inqId\)/,
    'matchAndNotify does not resolve the buyer name, so the new_inquiry email - the first supplier-facing ' +
    'surface an inquiry ever reaches - carries the buyer name to every matched supplier.');
});

test('no supplier-facing notification body scrubs with a null owner', () => {
  for (const [name, body] of [['notifyLosers', losers], ['matchAndNotify', dispatch]]) {
    assert.doesNotMatch(body, /scrubIdentity\([^)]*,\s*null\s*,/,
      name + ' still calls scrubIdentity with ownName = null. companyRe(null) returns null, the name pattern ' +
      'is never built, and the buyer name survives into a supplier email.');
  }
});

test('the scrub is fed the resolved name, not a placeholder', () => {
  assert.match(losers, /scrubIdentity\(summary\.trim\(\),\s*bn\.name,/,
    'notifyLosers does not pass the resolved name into scrubIdentity');
  assert.match(dispatch, /scrubIdentity\(String\(t\),\s*bn\.name,/,
    'matchAndNotify does not pass the resolved name into scrubIdentity');
});

test('a failed owner lookup drops the customer free text instead of sending it unscrubbed', () => {
  // The defect being prevented is a fallback that looks safe: returning null on a failed read would
  // put us back on exactly the code path this file exists to forbid.
  assert.match(src, /type BuyerName = \{ resolved: true; name: string \| null \} \| \{ resolved: false \}/,
    'BuyerName no longer distinguishes "no name on record" from "the lookup failed". Those are different ' +
    'situations: only the first one is safe to send free text for.');
  assert.match(losers, /bn\.resolved && summary && summary\.trim\(\)/,
    'notifyLosers does not gate the quoted summary on bn.resolved, so a failed lookup emits the buyer text ' +
    'unscrubbed.');
  assert.match(dispatch, /\(bn\.resolved && t\) \?/,
    'matchAndNotify does not gate the customer free text on bn.resolved, so a failed lookup emits summary, ' +
    'budget and extra unscrubbed.');
  assert.match(dispatch, /const headline = cust\(summary\) \|\| category;/,
    'the new_inquiry headline does not fall back to the platform category. With no fallback a dropped summary ' +
    'would send an empty subject line instead of the trade name.');
});

test('every customer-authored field in the new_inquiry body goes through the scrub', () => {
  const body = dispatch.slice(dispatch.indexOf("subject: 'New job request on QuotesDone'"));
  for (const field of ['budget', 'extra']) {
    assert.match(body, new RegExp('cust\\(' + field + '\\)'),
      'the new_inquiry body emits ' + field + ' without the scrub. budget is an 80-char free-text box and extra ' +
      'is free text; both are places a buyer types their own name.');
  }
  assert.doesNotMatch(body, /\+ budget \+|\+ extra \+|\+ summary \+/,
    'a customer free-text field is concatenated into the new_inquiry body raw.');
});
