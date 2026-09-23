// durationLabel.test.mjs — an Arabic day count agrees with its number (review of #818).
// node --test src/lib/durationLabel.test.mjs
// The companion check that no template prints a day count by hand is in
// scripts/checks/every_arabic_message_is_written_not_translated.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arDays, durationLabel } from './durationLabel.ts';
import { AR_NOUN, arCount } from './countedNoun.ts';

test('arDays gives the form Arabic requires for each count', () => {
  const want = { 1: 'يوم واحد', 2: 'يومان', 3: '3 أيام', 10: '10 أيام', 11: '11 يومًا', 15: '15 يومًا', 100: '100 يومًا' };
  for (const [n, s] of Object.entries(want)) assert.equal(arDays(Number(n)), s, n);
});

test('durationLabel and arDays agree on days', () => {
  for (const n of [1, 2, 3, 10, 11, 15, 100]) assert.equal(durationLabel(`${n} days`, 'ar'), arDays(n));
});

// 23 Sep 2026, re-review of #858. arDays is a THIN WRAPPER over src/lib/countedNoun.ts and owns
// exactly two things of its own: the day forms, and that 0 reads "today" rather than "0 days". #858
// had lifted a second four-form counter into this file; countedNoun.ts already owned that rule, with
// the oblique dual AND the zero branch the copy lacked. These cases fail if the wrapper starts
// deciding anything the owner has already decided.
test('arDays is countedNoun.arCount over AR_NOUN.day, and decides nothing else', () => {
  for (const n of [1, 2, 3, 10, 11, 15, 100]) assert.equal(arDays(n), arCount(n, AR_NOUN.day), String(n));
  assert.equal(arDays(0), '\u0627\u0644\u064a\u0648\u0645'); // the one case that is not a count
  assert.notEqual(arDays(0), arCount(0, AR_NOUN.day));
});

// CP-I18N-06 (main): after خلال / قبل / نحو the dual is genitive. It is now the owner's `oblique`,
// so the two spellings of that one rule cannot drift apart.
test('arDays genitive is the owner oblique dual, and changes the dual only', () => {
  assert.equal(arDays(2, { genitive: true }), '\u064a\u0648\u0645\u064a\u0646');
  assert.equal(arDays(2, { genitive: true }), arCount(2, AR_NOUN.day, { oblique: true }));
  for (const n of [0, 1, 3, 10, 11, 15, 100]) assert.equal(arDays(n, { genitive: true }), arDays(n), String(n));
});
