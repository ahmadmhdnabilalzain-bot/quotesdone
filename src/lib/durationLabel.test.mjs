// durationLabel.test.mjs — an Arabic day count agrees with its number (review of #818).
// node --test src/lib/durationLabel.test.mjs
// The companion check that no template prints a day count by hand is in
// scripts/checks/every_arabic_message_is_written_not_translated.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { arCount, arDays, durationLabel } from './durationLabel.ts';

test('arDays gives the form Arabic requires for each count', () => {
  const want = { 1: 'يوم واحد', 2: 'يومان', 3: '3 أيام', 10: '10 أيام', 11: '11 يومًا', 15: '15 يومًا', 100: '100 يومًا' };
  for (const [n, s] of Object.entries(want)) assert.equal(arDays(Number(n)), s, n);
});

test('durationLabel and arDays agree on days', () => {
  for (const n of [1, 2, 3, 10, 11, 15, 100]) assert.equal(durationLabel(`${n} days`, 'ar'), arDays(n));
});

// 22 Sep 2026 (audit SP-I-04): the supplier portal printed "{n} استفسارًا" for every n, so one
// inquiry read "1 استفسارًا" and two read "2 استفساران" was never reached at all. arCount is the one
// rule; arDays is now built on it, so a regression in either fails here.
const INQUIRY = ['استفسار واحد', 'استفساران', 'استفسارات', 'استفسارًا'];

test('arCount gives the form Arabic requires, and writes no digit for 1 or 2', () => {
  const want = { 1: 'استفسار واحد', 2: 'استفساران', 3: '3 استفسارات', 10: '10 استفسارات', 11: '11 استفسارًا', 100: '100 استفسارًا' };
  for (const [n, s] of Object.entries(want)) assert.equal(arCount(Number(n), INQUIRY), s, n);
  for (const n of [1, 2]) assert.ok(!/\d/.test(arCount(n, INQUIRY)), `${n} must not print a digit`);
});

test('arDays is arCount, so the two can never drift', () => {
  const DAY = ['يوم واحد', 'يومان', 'أيام', 'يومًا'];
  for (const n of [1, 2, 3, 10, 11, 100]) assert.equal(arDays(n), arCount(n, DAY), String(n));
  assert.equal(arDays(0), 'اليوم'); // the one case that is not a count
});

// CP-I18N-06: after خلال / قبل / نحو the dual is genitive. Nothing else moves.
test('arDays genitive changes the dual only', () => {
  assert.equal(arDays(2, { genitive: true }), 'يومين');
  for (const n of [0, 1, 3, 10, 11, 15, 100]) assert.equal(arDays(n, { genitive: true }), arDays(n), String(n));
});
