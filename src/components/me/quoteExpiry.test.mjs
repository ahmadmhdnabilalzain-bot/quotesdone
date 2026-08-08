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

test('expired copy tells the customer to re-confirm BEFORE paying', () => {
  const n = expiryOf(at('2026-08-01T00:00:00Z', true), 'en', NOW);
  assert.equal(n.tone, 'expired');
  assert.match(n.text, /before you pay/);
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
