// node supabase/functions/quote_compare/deterministic.test.mjs
// The one runnable check for the model-free comparison. No framework: it throws or it prints OK.
import assert from 'node:assert/strict';
import { deterministicCompare, leadTimeDays } from './deterministic.ts';

// --- lead time parsing, including the unstated case that must NOT score as average
assert.equal(leadTimeDays('10 days'), 10);
assert.equal(leadTimeDays('2 weeks'), 14);
assert.equal(leadTimeDays('1 month'), 30);
assert.equal(leadTimeDays('10-14 days'), 10);
assert.equal(leadTimeDays(''), null);
assert.equal(leadTimeDays(null), null);
assert.equal(leadTimeDays('ASAP'), null);

const q = (label, price, extra = {}) => ({
  label, price, lead_time: null, validity: null, warranty: null, payment_terms: null,
  exclusions: null, itemised: false, expired: false, source: 'form', ...extra,
});

// --- a rock-bottom, empty quote must NOT beat a well-specified one at a fair price.
// That is the whole point of the ranking and the thing a "cheapest wins" sort gets wrong.
const r = deterministicCompare([
  q('Supplier A', 10000, { completeness: { score: 20, passed: false, missing_mandatory: 4 } }),
  q('Supplier B', 13000, {
    lead_time: '10 days', warranty: '12 months', payment_terms: '50/50', validity: '30 days',
    itemised: true, completeness: { score: 92, passed: true, missing_mandatory: 0 },
  }),
  q('Supplier C', 21000, {
    lead_time: '6 weeks', warranty: '6 months', itemised: true,
    completeness: { score: 60, passed: true, missing_mandatory: 1 },
  }),
], 'en');

assert.equal(r.degraded, true, 'must announce itself as degraded');
assert.equal(r.engine, 'deterministic');
assert.equal(r.considered, 3);
assert.equal(r.top3.length, 3, 'three quotes in, three ranked out');
assert.deepEqual(r.top3.map(t => t.rank), [1, 2, 3]);
assert.equal(new Set(r.top3.map(t => t.label)).size, 3, 'no duplicate labels');
assert.equal(r.cheapest_label, 'Supplier A', 'cheapest is still reported honestly');
assert.equal(r.top3[0].label, 'Supplier B', 'the complete quote at a fair price wins, not the cheapest');
assert.equal(r.best_value_label, 'Supplier B');
assert.ok(r.overview.includes('10,000') && r.overview.includes('11,000'), 'states cheapest and spread with real numbers');

for (const item of r.quotes) {
  for (const k of ['price_score', 'delivery_score', 'quality_score']) {
    assert.ok(Number.isInteger(item[k]) && item[k] >= 1 && item[k] <= 5, `${item.label}.${k} out of 1..5`);
  }
  // Nothing about the specification may be invented — that needs reading, which is the model's job.
  assert.deepEqual(item.missing_from_request, []);
  assert.deepEqual(item.spec_deviation, []);
}
assert.deepEqual(r.line_findings, [], 'never fabricates line-level findings');

// A quote that states nothing must be flagged, not quietly scored as average.
const a = r.quotes.find(x => x.label === 'Supplier A');
assert.ok(a.flags.some(f => /Warranty not stated/.test(f)));
assert.ok(a.flags.some(f => /Lead time not stated/.test(f)));
assert.ok(a.flags.some(f => /completeness check/.test(f)));
assert.equal(a.delivery_score, 1, 'unstated lead time scores 1, never a middle value');

// --- REGRESSION GUARD for the defect found by running this against four real staging quotes.
// Those prices (862,400 / 985,000 / 1,036,000 / 1,107,400) are all within ~22% of the cheapest.
// Ratio-to-the-cheapest scoring gave EVERY quote 5/5 on price, so price stopped discriminating
// and the whole ranking silently collapsed onto lead time. Real quotes for one job cluster —
// that is the normal case, not the edge case.
const rc = deterministicCompare([
  q('Supplier A', 862400, { lead_time: '30 days' }),
  q('Supplier B', 985000, { lead_time: '45 days' }),
  q('Supplier C', 1036000, { lead_time: '60 days' }),
  q('Supplier D', 1107400, { lead_time: '90 days' }),
], 'en');
const ps = rc.quotes.map(x => x.price_score);
assert.ok(new Set(ps).size > 1, 'clustered prices must still produce different price scores');
assert.equal(Math.max(...ps), 5, 'the cheapest of the shortlist scores 5');
assert.equal(rc.top3[0].label, 'Supplier A');

// An exact tie is a 3 for everyone, never a 5 for everyone.
const rt = deterministicCompare([q('Supplier A', 500), q('Supplier B', 500)], 'en');
assert.deepEqual(rt.quotes.map(x => x.price_score), [3, 3], 'a genuine tie scores 3, not 5');

// --- two quotes, one expired, one with no price at all
const r2 = deterministicCompare([
  q('Supplier A', null, { warranty: '1 year' }),
  q('Supplier B', 5000, { expired: true, lead_time: '3 days', itemised: true }),
], 'en');
assert.equal(r2.top3.length, 2, 'two in, two out');
assert.equal(r2.top3[0].label, 'Supplier B', 'a priced quote outranks one with no price');
assert.ok(r2.watch_outs.some(w => /expired/i.test(w)), 'expiry surfaces as a watch-out');
assert.equal(r2.cheapest_label, 'Supplier B');

// --- Arabic renders in Arabic and still ranks
const r3 = deterministicCompare([q('Supplier A', 100, { itemised: true }), q('Supplier B', 200)], 'ar');
assert.equal(r3.top3.length, 2);
assert.ok(/درهم/.test(r3.overview), 'Arabic output uses Arabic');

// --- customer-journey follow-up, 10 Nov 2026 (each fails on origin/main) ---
// Available now is the fastest lead time, not an unstated one.
for (const s of ['ex-stock', 'Ex stock', 'from stock', 'immediate', 'same day', 'فوري']) assert.equal(leadTimeDays(s), 0, s);
assert.equal(leadTimeDays('ASAP'), null, 'a vague promise still states nothing');
const rn = deterministicCompare([q('Supplier A', 1000, { lead_time: 'ex-stock' }), q('Supplier B', 1000, { lead_time: '3 weeks' })], 'en');
assert.equal(rn.quotes.find((x) => x.label === 'Supplier A').delivery_score, 5, 'ex-stock scores best on delivery');
// An expired quote is never recommended over a valid priced one, however good its figures.
const re = deterministicCompare([
  q('Supplier A', 9000, { expired: true, itemised: true, warranty: '1 year', lead_time: '1 week' }),
  q('Supplier B', 12000, { lead_time: '4 weeks' }),
], 'en');
assert.equal(re.top3[0].label, 'Supplier B', 'a valid quote is recommended before an expired one');
assert.equal(re.top3[1].label, 'Supplier A', 'the expired quote is still shortlisted and listed');
// Each place says which place it is, and a tie says how it was broken.
const rk = deterministicCompare([q('Supplier A', 500), q('Supplier B', 500), q('Supplier C', 800)], 'en');
assert.match(rk.top3[0].why, /^Highest/);
assert.match(rk.top3[1].why, /^Second-highest/);
assert.match(rk.top3[1].why, /level on score with Supplier A/, 'a tie is named');
assert.match(rk.top3[2].why, /^Third-highest/);
const rka = deterministicCompare([q('Supplier A', 500), q('Supplier B', 500)], 'ar');
assert.match(rka.top3[1].why, /^ثاني أعلى/);

console.log('OK — deterministic quote comparison: ranking, scores, flags, EN/AR, no invented specs');
