// deno test --no-lock supabase/functions/supplier_portal/insights_summary.test.ts
//
// The Insights payload (15 Sep 2026). Pure rules over fixed numbers, plus the reads against a fake
// client. No network, no environment, no real row — nothing here can reach a person.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { buildInsightsSummary, funnel, hints, isoMonth, pricePosition, shapeInsights } from './insights_summary.ts';

const STATS = {
  quotes_total: 10, reveals: 4, hired: 1, lost_to_others: 2, win_ratio: 10, reveal_ratio: 40, response_rate: 60, avg_lead_time_days: 45, rating: 4.5,
  price_positioning: { band: 'above market average', competitive_rfqs: 6, times_lowest: 1, lowest_rate: 17, avg_pct_vs_average: 12.4, avg_pct_above_lowest: 20.1 },
  history_12m: [{ month: 'Aug 26', quotes: 3, reveals: 1 }, { month: 'Sep 26', quotes: 7, reveals: 3 }],
  document_expiries: [{ doc: 'Insurance', status: 'expiring', days_left: 12 }, { doc: 'ISO', status: 'valid', days_left: 300 }],
};

Deno.test('months come back as YYYY-MM, an unknown label is kept visible', () => {
  assertEquals(isoMonth('Sep 26'), '2026-09');
  assertEquals(isoMonth('Jan 27'), '2027-01');
  assertEquals(isoMonth('weird'), 'weird');
});

Deno.test('price position: band, gauge clamped to -1..1, and no_data without competitive inquiries', () => {
  const p = pricePosition(STATS.price_positioning);
  assertEquals(p.band, 'above');
  assertEquals(p.gauge, 12.4 / 20);
  assertEquals(pricePosition({ ...STATS.price_positioning, avg_pct_vs_average: -80, band: 'below market average' }).gauge, -1);
  const none = pricePosition({ band: 'not enough data', competitive_rfqs: 0, avg_pct_vs_average: null });
  assertEquals(none.band, 'no_data');
  assertEquals(none.gauge, null);
  assertEquals(none.pct_vs_market_avg, null);
});

// NOT ENOUGH COMPARISONS YET (19 Nov 2026, founder ruling 1686): fn_supplier_stats now sends ready:false and no percentage until 5
// inquiries each carry 3+ other suppliers' submitted quotes. The panel must read that as no_data, not as 0% or "around".
Deno.test('price position: fewer than five comparisons is no_data with no figure, even with some comparisons counted', () => {
  const thin = pricePosition({ ready: false, band: 'not enough comparisons yet', competitive_rfqs: 4, times_lowest: null, lowest_rate: null,
    avg_pct_vs_average: null, avg_pct_above_lowest: null, min_comparisons: 5, min_other_suppliers: 3, step_pct: 5 });
  assertEquals(thin.band, 'no_data');
  assertEquals([thin.pct_vs_market_avg, thin.pct_above_lowest, thin.lowest_rate_pct, thin.gauge], [null, null, null, null]);
  assertEquals(thin.times_lowest, null);
  const ready = pricePosition({ ready: true, band: 'below market average', competitive_rfqs: 5, times_lowest: 0, lowest_rate: 0,
    avg_pct_vs_average: -5, avg_pct_above_lowest: 10 });
  assertEquals([ready.band, ready.pct_vs_market_avg, ready.pct_above_lowest, ready.gauge], ['below', -5, 10, -0.25]);
  // times_lowest is never passed on, even from an old payload that still carries it (review of c1d1fd657).
  assertEquals(pricePosition({ ...STATS.price_positioning, times_lowest: 3 }).times_lowest, null);
});

Deno.test('funnel: conversion is of the previous stage, null where the previous is zero', () => {
  const f = funnel(20, STATS);
  assertEquals(f.map((x) => x.count), [20, 10, 4, 1]);
  assertEquals(f.map((x) => x.conversion_pct), [null, 50, 40, 25]);
  assertEquals(funnel(0, {}).map((x) => x.conversion_pct), [null, null, null, null]);
});

Deno.test('hints: measured rules only, most costly first', () => {
  const pp = pricePosition(STATS.price_positioning);
  const h = hints(STATS, 40, pp, true);
  const codes = h.map((x) => x.code);
  assertEquals(codes[0], 'hint_doc_expiring', 'an expiring document outranks pricing');
  for (const c of ['hint_quote_more', 'hint_price_above', 'hint_follow_up', 'hint_response_rate', 'hint_lead_time']) assert(codes.includes(c), c);
  assert(!codes.includes('hint_all_good'));
  assertEquals(h.find((x) => x.code === 'hint_price_above')!.params.pct, 12);
});

Deno.test('a new supplier: honest zeros and one hint on how to start', () => {
  const s = shapeInsights({ history_12m: [{ month: 'Sep 26', quotes: 0, reveals: 0 }], price_positioning: { band: 'not enough data', competitive_rfqs: 0 } }, 0, 0, null);
  assertEquals(s.has_data, false);
  assertEquals(s.totals, { inquiries_received: 0, quotations_submitted: 0, jobs_won: 0, revenue_aed: 0 });
  assertEquals(s.hints.map((x) => x.code), ['hint_first_request']);
  const blocked = shapeInsights({}, 0, 0, false);
  assertEquals(blocked.hints[0].code, 'hint_not_eligible');
  assert(!blocked.hints.some((x) => x.code === 'hint_first_request'), 'an ineligible supplier is sent to fix eligibility, not to wait');
});

// A fake client: every read answers from `answers` by table or rpc name.
function fakeAdmin(answers: Record<string, unknown>) {
  const reads: string[] = [];
  const table = (name: string) => {
    const q: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'in', 'not', 'order', 'limit']) q[m] = () => q;
    q.then = (ok: (v: unknown) => unknown) => { reads.push(name); return Promise.resolve(answers[name] ?? { data: null, count: 0 }).then(ok); };
    return q;
  };
  return { reads, from: table, rpc: (fn: string) => { reads.push('rpc:' + fn); return Promise.resolve(answers['rpc:' + fn] ?? { data: null }); } };
}

Deno.test('revenue is the revealed value of WON jobs, refunded ones excluded', async () => {
  const admin = fakeAdmin({
    'rpc:fn_supplier_stats': { data: STATS },
    inquiry_matches: { count: 40 },
    inquiries: { data: [{ id: 'a' }, { id: 'b' }] },
    transactions: { data: [{ quote_amount: 12000, refund_status: null }, { quote_amount: 5000, refund_status: 'approved' }] },
  });
  const r = await buildInsightsSummary(admin, 7, Promise.resolve(true));
  assertEquals(r.status, 200);
  const body = r.body as ReturnType<typeof shapeInsights>;
  assertEquals(body.totals, { inquiries_received: 40, quotations_submitted: 10, jobs_won: 1, revenue_aed: 12000 });
  assertEquals(body.series.map((x) => x.month), ['2026-08', '2026-09']);
});

Deno.test('a stats failure is an error, never a page of zeros', async () => {
  const admin = fakeAdmin({ 'rpc:fn_supplier_stats': { data: null, error: { message: 'boom' } } });
  const r = await buildInsightsSummary(admin, 7);
  assertEquals(r.status, 500);
});
