// otpFailover.test.mjs — a WhatsApp code that is not delivered is followed by an SMS without the user
// having to ask (review of #1432). node --test src/lib/otpFailover.test.mjs
import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { FAILOVER_PINGS_S, scheduleFailover } from './otpFailover.ts';

const flush = () => new Promise((r) => setImmediate(r));

test('the schedule brackets the 45 s deadline and stops once the server sent the SMS', async () => {
  assert.ok(FAILOVER_PINGS_S.some((s) => s >= 45 && s <= 60), 'one ping must land just after 45 s');
  mock.timers.enable({ apis: ['setTimeout'] });
  const answers = [{ state: 'waiting' }, { state: 'waiting' }, { state: 'sent_sms' }, { state: 'waiting' }];
  let pings = 0, sms = 0;
  scheduleFailover(async () => answers[pings++], () => sms++);
  for (const s of FAILOVER_PINGS_S) { mock.timers.tick(1000 * (s - (FAILOVER_PINGS_S[FAILOVER_PINGS_S.indexOf(s) - 1] || 0))); await flush(); }
  assert.equal(sms, 1, 'onSms fires once');
  assert.equal(pings, 3, 'no ping after the SMS went');
  mock.timers.reset();
});

test('a delivered WhatsApp message stops the schedule with no SMS, and cancel stops everything', async () => {
  mock.timers.enable({ apis: ['setTimeout'] });
  let pings = 0, sms = 0;
  scheduleFailover(async () => { pings++; return { state: 'delivered' }; }, () => sms++);
  mock.timers.tick(15_000); await flush(); mock.timers.tick(100_000); await flush();
  assert.equal(sms, 0);
  assert.equal(pings, 1);
  let p2 = 0;
  const cancel = scheduleFailover(async () => { p2++; return {}; });
  cancel(); mock.timers.tick(100_000); await flush();
  assert.equal(p2, 0);
  mock.timers.reset();
});
