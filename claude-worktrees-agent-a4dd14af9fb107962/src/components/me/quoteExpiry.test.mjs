// The customer pays a non-refundable reveal fee off the back of this notice, so the branch that
// decides "expired" from "expires today" from "fine" is executed rather than only rendered.
//
//   node --test src/components/me/quoteExpiry.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { expiryOf } from './quoteExpiry.ts';

const NOW = Date.parse('2026-08-06T12:00:00Z');
const at = (iso, expired) => ({ expires_at: iso, expired });

test('a quote with no expiry says nothing at all', () => {
  assert.equal(expiryOf({ expires_at: null, expired: false }, 'en', NOW), null);
  assert.equal(expiryOf(null, 'en', NOW), null);
  assert.equal(expiryOf(undefined, 'en', NOW), null);
});

test('an unparseable date is silence, never a false warning', () => {
  assert.equal(expiryOf(at('not-a-date', false), 'en', NOW), null);
});

test('the SERVER decides expired — a past date the server has not flagged is not called expired', () => {
  // This is the whole point of trusting `expired` over the browser clock: a device whose date is
  // wrong must not be able to tell the customer their live quote has lapsed.
  const n = expiryOf(at('2026-08-01T00:00:00Z', false), 'en', NOW);
  assert.notEqual(n, null);
  assert.notEqual(n.tone, 'expired');
});

test('and a future date the server HAS flagged is still expired', () => {
  assert.equal(expiryOf(at('2026-09-01T00:00:00Z', true), 'en', NOW).tone, 'expired');
});

// Before the reveal the customer cannot reach a supplier (founder, 14 Sep 2026): the expired copy
// warns BEFORE paying and never tells them to ask or re-confirm anything with the supplier. Until
// 14 Sep 2026 it said "ask the supplier to re-confirm the price", which they had no way to do.
test('expired copy warns BEFORE paying and never sends the customer to the supplier', () => {
  const en = expiryOf(at('2026-08-01T00:00:00Z', true), 'en', NOW);
  const ar = expiryOf(at('2026-08-01T00:00:00Z', true), 'ar', NOW);
  assert.equal(en.tone, 'expired');
  assert.match(en.text, /before you pay/);
  assert.match(ar.text, /قبل أن تدفع/);
  assert.doesNotMatch(en.text, /\bask\b|re-?confirm|contact|with the supplier/i);
  assert.doesNotMatch(ar.text, /اطلب|اسأل|تواصل|تأكيد/);
});

test('inside today reads as today, not as a negative or zero day count', () => {
  const n = expiryOf(at('2026-08-06T18:00:00Z', false), 'en', NOW);
  assert.equal(n.tone, 'soon');
  assert.equal(n.text, 'This quote expires today.');
});

test('three days or fewer is a warning; four is not', () => {
  assert.equal(expiryOf(at('2026-08-09T00:00:00Z', false), 'en', NOW).tone, 'soon');
  assert.equal(expiryOf(at('2026-08-11T00:00:00Z', false), 'en', NOW).tone, 'ok');
});

test('one day left is singular, two is plural', () => {
  assert.match(expiryOf(at('2026-08-07T06:00:00Z', false), 'en', NOW).text, /1 day left/);
  assert.match(expiryOf(at('2026-08-08T06:00:00Z', false), 'en', NOW).text, /2 days left/);
});

test('Arabic gets Arabic in every branch, never a half-translated string', () => {
  const arabic = /[؀-ۿ]/;
  for (const q of [at('2026-08-01T00:00:00Z', true), at('2026-08-06T18:00:00Z', false), at('2026-08-08T00:00:00Z', false), at('2026-09-30T00:00:00Z', false)]) {
    assert.match(expiryOf(q, 'ar', NOW).text, arabic);
  }
});
