// durationLabel.test.mjs — an Arabic day count agrees with its number (review of #818).
// node --test src/lib/durationLabel.test.mjs
// The companion check that no template prints a day count by hand is in
// scripts/checks/every_arabic_message_is_written_not_translated.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arDays, durationLabel } from './durationLabel.ts';

test('arDays gives the form Arabic requires for each count', () => {
  const want = { 1: 'يوم واحد', 2: 'يومان', 3: '3 أيام', 10: '10 أيام', 11: '11 يومًا', 15: '15 يومًا', 100: '100 يومًا' };
  for (const [n, s] of Object.entries(want)) assert.equal(arDays(Number(n)), s, n);
});

test('durationLabel and arDays agree on days', () => {
  for (const n of [1, 2, 3, 10, 11, 15, 100]) assert.equal(durationLabel(`${n} days`, 'ar'), arDays(n));
});

// CP-I18N-06: after خلال / قبل / نحو the dual is genitive. Nothing else moves.
test('arDays genitive changes the dual only', () => {
  assert.equal(arDays(2, { genitive: true }), 'يومين');
  for (const n of [0, 1, 3, 10, 11, 15, 100]) assert.equal(arDays(n, { genitive: true }), arDays(n), String(n));
});
