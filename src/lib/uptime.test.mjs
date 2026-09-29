// uptime.test.mjs — the 99.9% uptime maths behind it_engineer.uptime_slo.
// node --test src/lib/uptime.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { uptimeVerdict, isUp } from './uptime.ts';

const SLOTS_30D = 30 * 24 * 4; // 2,880 fifteen-minute checks

test('44 failed slots in 30 days is a breach of 99.9%', () => {
  const v = uptimeVerdict(SLOTS_30D - 44, SLOTS_30D);
  assert.equal(v.breach, true);
  assert.ok(v.ratio < 0.999);
});

test('1 failed slot in 30 days is within target', () => {
  assert.equal(uptimeVerdict(SLOTS_30D - 1, SLOTS_30D).breach, false);
});

test('the budget edge: 2 failed slots pass, 3 breach', () => {
  assert.equal(uptimeVerdict(SLOTS_30D - 2, SLOTS_30D).breach, false);
  assert.equal(uptimeVerdict(SLOTS_30D - 3, SLOTS_30D).breach, true);
});

test('under a day of samples gives no verdict', () => {
  assert.deepEqual(uptimeVerdict(0, 95), { ratio: null, breach: false, measured: false });
});

test('status classification', () => {
  assert.equal(isUp(200), true);
  assert.equal(isUp(308), true);
  assert.equal(isUp(503), false);
  assert.equal(isUp(0), false);
});
