// Runnable checks for the two decisions this module makes on the customer's behalf, and both are
// decisions to STAY SILENT: whether a market comparison may be shown at all, and whether a
// next-year projection may be. Production is in exactly the state where both must refuse, so these
// are not edge cases — they are the only state that exists today. Node 24 strips the types:
//
//   node --test src/components/portal/predict/model.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { projection, urgency } from './model.ts';

const forecast = (o) => ({
  customer_id: 'c', as_of: '', horizon_days: 365, basis: 'history', sufficient_data: true,
  empty_reason: null, observed: { rfqs: 9, months_active: 4, spend_aed: 0, first_rfq: null, last_rfq: null },
  series: [], next_year: { horizon_days: 365, projected_rfqs: 24, projected_spend_aed: 500000, by_category: [] },
  predictions: [], ...o,
});

test('the projection is shown only when the routine says the account clears its own floor', () => {
  assert.deepEqual(projection(forecast()), { rfqs: 24, spendAed: 500000, horizonDays: 365 });
  // Production today: no history at all.
  assert.equal(projection(forecast({ basis: 'no_history', sufficient_data: false, next_year: { horizon_days: 365, projected_rfqs: null, projected_spend_aed: null, by_category: [] } })), null);
  // Some history, below the floor: the routine nulls the figures AND says why. Neither is rendered.
  assert.equal(projection(forecast({ sufficient_data: false })), null);
  // A flag saying sufficient with a figure missing is still not a projection.
  assert.equal(projection(forecast({ next_year: { horizon_days: 365, projected_rfqs: 24, projected_spend_aed: null, by_category: [] } })), null);
  assert.equal(projection(null), null);
});

test('the horizon falls back through the payload rather than being invented', () => {
  assert.equal(projection(forecast({ next_year: { projected_rfqs: 3, projected_spend_aed: 10, by_category: [] } })).horizonDays, 365);
  assert.equal(projection(forecast({ horizon_days: 180, next_year: { horizon_days: 180, projected_rfqs: 3, projected_spend_aed: 10, by_category: [] } })).horizonDays, 180);
});

/* ── the urgency badge is presentation only; within_days is what the customer reads ────────── */

test('urgency bands', () => {
  assert.equal(urgency(0), 'now');
  assert.equal(urgency(-3), 'now', 'a deadline already passed is not "planned"');
  assert.equal(urgency(14), 'soon');
  assert.equal(urgency(45), 'planned');
  assert.equal(urgency(null), 'planned');
  assert.equal(urgency('nope'), 'planned');
});
