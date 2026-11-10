// A HELD SUPPLIER WHO TRIES TO QUOTE IS TOLD THE REAL REASON, NOT "UPLOAD A LICENCE" (10 Nov 2026, customer_support; the
// supplier-quoting audit after #1901, founder ruling 1608).
//
// submit_quote refuses a supplier who is not approved (code not_verified, params.reason = leads.licence_gate_reason). The
// server's sentence printed the raw code ("not verified yet: services_unconfirmed. Upload a clear, in-date trade licence from
// your Profile tab") and the portal's wording (serverCopy not_verified) appended "Upload a clear, in-date trade licence in
// Documents" after EVERY reason, so a supplier held for unconfirmed services, a document still being read, the terms
// certificate, or our own reader's failure (licence_being_read) was sent to upload a licence. This fails if either comes back.
//   node --test scripts/checks/a_held_supplier_who_tries_to_quote_is_told_the_real_reason.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const COPY = readFileSync('src/components/portal/supplier/serverCopy.ts', 'utf8');
const QUOTES = readFileSync('supabase/functions/supplier_api/actions/quotes.ts', 'utf8');

test('the portal says the hold reason in its own words, and asks for a licence only when there is no reason', () => {
  const line = COPY.split('\n').find((l) => l.trimStart().startsWith('not_verified: s(')) || '';
  assert.ok(line, 'serverCopy has no not_verified wording');
  const withReason = (line.match(/p\.reason \? `([^`]*)`/) || [])[1] || '';
  assert.ok(withReason, 'the wording must branch on the reason');
  assert.doesNotMatch(withReason, /Upload a clear, in-date trade licence/, 'a reason that is not a licence must not be told to upload one');
  assert.match(withReason, /COPY\[p\.reason\]\?\.en\(\{\}\)/, "the reason's own wording must be used");
});

test('the server never prints the reason code into the sentence, and names the Documents tab', () => {
  const at = QUOTES.indexOf("code: 'not_verified'");
  const stmt = QUOTES.slice(QUOTES.lastIndexOf('return J(', at), at);
  assert.doesNotMatch(stmt, /\+ \(why \? ': ' \+ why/, 'the raw hold code is printed to the supplier');
  assert.doesNotMatch(stmt, /Profile tab/, 'the licence is uploaded in Documents, not Profile');
  assert.match(stmt, /why \? '[^']*shown at the top of your supplier portal/);
});
