// AN INTAKE LEFT FOR THIRTY DAYS IS EXPIRED QUIETLY (sales_engineer, customer-journey follow-up 10 Nov 2026; ruling 1608).
//
// MEASURED on production: 3 needs_info and 1 ready intake, abandoned since September and October, and nothing in the
// estate ever ended one. This holds the routine, as the last applied-or-pending file defines it, to the rule: the two open
// states only, the day count from decision_policy, no message, updated_at kept, and a seat duty that runs it. The file's
// _probe.sql proves the behaviour rolled back on production.
//   node --test scripts/checks/an_intake_left_for_thirty_days_is_expired_quietly.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, read } from '../lib/canonical_body.mjs';

test('a needs_info or ready intake untouched for intake_abandoned_days is expired, with no message', () => {
  const { file, body } = canonicalBody('fn_sales_engineer_expires_abandoned_intakes');
  assert.match(body, /it\.status in \('needs_info', 'ready'\)/);
  assert.match(body, /fn_seat_clock_policy\('intake_abandoned_days', 30\)/);
  assert.match(body, /set status = 'expired'/);
  assert.doesNotMatch(body, /updated_at\s*=/, 'the expiry rewrites when the customer last spoke');
  assert.doesNotMatch(body, /duty_send|takes_delivery|notifications/, 'an abandoned intake is messaged');
  assert.match(read(file), /\('sales_engineer\.abandoned_intakes', 'sales_engineer', interval '1 day', 'fn_sales_engineer_expires_abandoned_intakes'/);
});
