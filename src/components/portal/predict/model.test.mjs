// Runnable checks for the two decisions this module makes on the customer's behalf, and both are
// decisions to STAY SILENT: whether a market comparison may be shown at all, and whether a
// next-year projection may be. Production is in exactly the state where both must refuse, so these
// are not edge cases — they are the only state that exists today. Node 24 strips the types:
//
//   node --test src/components/portal/predict/model.test.mjs
//   npm test        (the repository runner discovers *.test.mjs anywhere in the tree)
import test from 'node:test';
import assert from 'node:assert/strict';
import { marketComparison, projection, urgency } from './model.ts';

const guidance = (o) => ({
  quote_id: 'q', inquiry_id: 'i', category: 'Steel', quote_amount: 850000, supplier_id: 1,
  supplier_name: null, market: null, market_median: null, market_sample_n: 0,
  delta_vs_median_pct: null, band: null, policy_scope: 'default', recommended_action: null,
  ask_discount_pct: null, target_price: null, headline: null, suggested_message: null,
  suggested_message_ar: null, empty_reason: null, ...o,
});

const forecast = (o) => ({
  customer_id: 'c', as_of: '', horizon_days: 365, basis: 'history', sufficient_data: true,
  empty_reason: null, observed: { rfqs: 9, months_active: 4, spend_aed: 0, first_rfq: null, last_rfq: null },
  series: [], next_year: { horizon_days: 365, projected_rfqs: 24, projected_spend_aed: 500000, by_category: [] },
  predictions: [], ...o,
});

/* ── §15: the market comparison must refuse a benchmark the backend called insufficient ────── */

test('a band the routine calls insufficient_data is NOT a market comparison, thin sample or not', () => {
  // Production today: no quotes at all, so no median and no band.
  assert.equal(marketComparison(guidance({ band: 'insufficient_data' })), null);
  // The dangerous one: the routine DOES return a median and a delta off a below-min_sample count
  // while withholding the target price. "12% above market" from two quotes is a confident sentence
  // with nothing behind it, so it is refused here too.
  assert.equal(
    marketComparison(guidance({ band: 'insufficient_data', market_median: 760000, market_sample_n: 2, delta_vs_median_pct: 11.8 })),
    null,
  );
  assert.equal(marketComparison(null), null);
  assert.equal(marketComparison(guidance({ band: null })), null);
});

test('a real benchmark is shown, with its direction', () => {
  const above = marketComparison(guidance({ band: 'high', market_median: 790000, market_sample_n: 7, delta_vs_median_pct: 7.6 }));
  assert.deepEqual(above, { median: 790000, sampleN: 7, deltaPct: 7.6, direction: 'above' });
  assert.equal(marketComparison(guidance({ band: 'low', market_median: 790000, market_sample_n: 7, delta_vs_median_pct: -4 })).direction, 'below');
  assert.equal(marketComparison(guidance({ band: 'fair', market_median: 790000, market_sample_n: 7, delta_vs_median_pct: 0 })).direction, 'level');
});

test('a band without the numbers behind it is still no comparison', () => {
  assert.equal(marketComparison(guidance({ band: 'high', market_median: null, market_sample_n: 7, delta_vs_median_pct: 3 })), null);
  assert.equal(marketComparison(guidance({ band: 'high', market_median: 790000, market_sample_n: 0, delta_vs_median_pct: 3 })), null);
  assert.equal(marketComparison(guidance({ band: 'high', market_median: 790000, market_sample_n: 7, delta_vs_median_pct: null })), null);
  assert.equal(marketComparison(guidance({ band: 'high', market_median: 0, market_sample_n: 7, delta_vs_median_pct: 3 })), null);
});

/* ── §20: the projection must refuse a straight line through one point ─────────────────────── */

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
