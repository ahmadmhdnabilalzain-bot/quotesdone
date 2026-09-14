// The customer is promised a full refund on this clock, so the count is executed, not eyeballed.
//
//   node --test src/components/me/workingDays.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { workingDaysSince, guaranteeClock } from './workingDays.ts';

// Monday 14 Sep 2026, 10:00 Dubai (06:00Z).
const PAID = '2026-09-14T06:00:00Z';
const at = (iso) => Date.parse(iso);
const TERMS = { window_days: 5, chase_after_days: 3 };

test('the payment day is day 0', () => {
  assert.equal(workingDaysSince(PAID, at('2026-09-14T19:00:00Z')), 0); // 23:00 Dubai, same day
});
test('Mon-Fri count, the weekend does not', () => {
  assert.equal(workingDaysSince(PAID, at('2026-09-15T06:00:00Z')), 1); // Tue
  assert.equal(workingDaysSince(PAID, at('2026-09-18T06:00:00Z')), 4); // Fri
  assert.equal(workingDaysSince(PAID, at('2026-09-19T06:00:00Z')), 4); // Sat
  assert.equal(workingDaysSince(PAID, at('2026-09-20T06:00:00Z')), 4); // Sun
  assert.equal(workingDaysSince(PAID, at('2026-09-21T06:00:00Z')), 5); // Mon
});
test('Dubai calendar, not UTC: 21:00Z Monday is already Tuesday in Dubai', () => {
  assert.equal(workingDaysSince(PAID, at('2026-09-14T21:00:00Z')), 1);
});
test('unparseable input is unknown, never zero', () => {
  assert.equal(workingDaysSince(null), null);
  assert.equal(workingDaysSince('not a date'), null);
});
test('the ladder: waiting, chased at 3, final call at 5, capped at 5', () => {
  assert.equal(guaranteeClock({ revealed_at: PAID }, TERMS, at('2026-09-16T06:00:00Z')).phase, 'waiting');
  assert.equal(guaranteeClock({ revealed_at: PAID }, TERMS, at('2026-09-17T06:00:00Z')).phase, 'chased');
  const late = guaranteeClock({ revealed_at: PAID }, TERMS, at('2026-09-30T06:00:00Z'));
  assert.equal(late.phase, 'final_call');
  assert.equal(late.day, 5);
  assert.equal(late.of, 5);
});
test('a recorded acknowledgement or refund outranks the clock', () => {
  assert.equal(guaranteeClock({ revealed_at: PAID, supplier_ack_at: PAID }, TERMS, at('2026-09-30T06:00:00Z')).phase, 'acknowledged');
  assert.equal(guaranteeClock({ revealed_at: PAID, refund_status: 'requested' }, TERMS, at('2026-09-16T06:00:00Z')).phase, 'refund');
});
test('a term the server did not serve yields no clock rather than an invented one', () => {
  assert.equal(guaranteeClock({ revealed_at: PAID }, { window_days: null, chase_after_days: 3 }), null);
  assert.equal(guaranteeClock(null, TERMS), null);
});
