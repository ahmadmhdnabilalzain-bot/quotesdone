// A REQUEST THAT REACHED SUPPLIERS HAS AN END (sales_engineer, customer-journey follow-up 10 Nov 2026; ruling 1608).
//
// MEASURED on origin/main: only a request that reached NOBODY was ever closed (fn_sales_engineer_closes_unreached_requests).
// One matched and never quoted, one with quotes nobody acted on, and one revealed and never marked hired stayed open for
// good, and their suppliers were never told. The policy (docs/sales-engineer/REQUEST_LIFECYCLE.md) is enforced by
// fn_sales_engineer_request_outcomes on the seat duty sales_engineer.request_outcomes; its _probe.sql proves the
// behaviour rolled back on production. This holds the routine, as the last applied-or-pending file defines it, to it.
//   node --test scripts/checks/a_request_that_reached_suppliers_has_an_end.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, read } from '../lib/canonical_body.mjs';

test('every number of the policy is a decision_policy row, read by the routine', () => {
  const { file, body } = canonicalBody('fn_sales_engineer_request_outcomes');
  for (const k of ['request_no_quote_expiry_days', 'request_quoted_reminder_days', 'request_quoted_lost_days',
    'request_revealed_close_days', 'request_revealed_not_yet_grace_days']) {
    assert.match(body, new RegExp(`fn_seat_clock_policy\\('${k}'`), `${k} is not read from decision_policy`);
    assert.match(read(file), new RegExp(`\\('${k}', '\\d+'::jsonb`), `${k} is not seeded`);
  }
});

test('the three ends are written with their honest reasons, and the customer and the suppliers are told', () => {
  const { file, body } = canonicalBody('fn_sales_engineer_request_outcomes');
  assert.match(body, /'no matched supplier quoted in time'/);
  assert.match(body, /'completed_without_award'/);
  assert.match(body, /when 'lost' then 'lost'/);
  assert.match(body, /'coverage_gap'[\s\S]{0,1200}'coverage_gap:no_quote:'/, 'an expired part files no coverage finding');
  assert.match(body, /fn_customer_support_duty_send\('request\.quoted_reminder', r\.id::text/, 'the reminder is not once per part');
  assert.match(body, /fn_sales_engineer_tells_matched_suppliers\(r\.id, r\.kind/, 'the matched suppliers are not told');
  assert.match(body, /f\.hired = 'not_yet' and f\.answered_at > p_at - make_interval\(days => v_grace\)/, 'a "not yet" answer does not hold a revealed part');
  assert.match(read(file), /\('sales_engineer\.request_outcomes', 'sales_engineer', interval '6 hours', 'fn_sales_engineer_request_outcomes'/, 'the duty is not registered');
});

test('the revealed supplier is never told "no award"', () => {
  assert.match(canonicalBody('fn_sales_engineer_tells_matched_suppliers').body, /p_kind = 'no_award' and exists \(select 1 from public\.transactions t/);
});
