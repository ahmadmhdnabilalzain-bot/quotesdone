// THE INSIGHTS TAB AS DATA, NOT AS RENDERED TEXT (15 Sep 2026, sales_engineer).
//
// The founder, 15 Sep 2026: "later this will be a mobile app as well. the structure need to be built
// in already." So every number, band, stage and hint the Insights tab shows is decided HERE and returned
// as typed data; the web portal's charts are one client, a mobile app renders the same payload natively.
// Contract: docs/api/supplier_portal_messages_documents_insights.md.
//
// What it is built from, all of it measured rather than estimated:
//   - fn_supplier_stats (the routine the old overview tab already read): quotes, reveals, hired, lost,
//     response rate, lead time, price positioning against every other quote on the same inquiries, and
//     the 12-month history. Its month labels are English ('Sep 26'); they are returned as 'YYYY-MM'.
//   - inquiry_matches: how many requests reached this supplier ("inquiries received").
//   - transactions on the inquiries this supplier was hired for: "revenue" is the value of the quote
//     the customer revealed on a job this supplier WON, refunded ones excluded. It is not the value of
//     every revealed quote (fn_supplier_stats.deal_value_awarded counts those, won or not).
// Hints are rules over those numbers with a stable code; the words live in the client
// (src/components/portal/supplier/workspaceCopy.ts), EN and AR, so no English sentence is in the payload.
//
// No Supabase client is created here; the caller passes its own (insights_summary.test.ts uses a fake).

// deno-lint-ignore no-explicit-any
type Admin = any;
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

export type PriceBand = 'below' | 'around' | 'above' | 'no_data';
export type PricePosition = {
  band: PriceBand;
  /** Average % your quotes sit above (+) or below (-) the other suppliers' mean on the same inquiries, in 5-point steps. */
  pct_vs_market_avg: number | null;
  /** Average % your quotes sit above the other suppliers' lowest on the same inquiries, in 5-point steps. */
  pct_above_lowest: number | null;
  /** Share of competitive inquiries on which you were the lowest bid, 0-100, in 5-point steps. */
  lowest_rate_pct: number | null;
  /** Inquiries on which at least 3 OTHER suppliers submitted a quote (drafts and withdrawn ones never count). Every
   *  figure above is null until there are 5 of them (fn_supplier_stats, 19 Nov 2026, founder ruling 1686): with one
   *  rival, mine/(1 + pct_above_lowest/100) was that rival's exact price. */
  competitive_rfqs: number;
  times_lowest: number;
  /** pct_vs_market_avg mapped onto -1 (20% or more below) .. +1 (20% or more above); null without data. */
  gauge: number | null;
  /** The band edges fn_supplier_stats uses, in % vs the market average, so a client draws the same bands. */
  band_edges: { below_max: number; above_min: number };
};
export type FunnelKey = 'received' | 'quoted' | 'revealed' | 'won';
export type FunnelStage = { key: FunnelKey; count: number; /** % of the previous stage, null for the first or when it is 0. */ conversion_pct: number | null };
export type SeriesPoint = { month: string; quotes: number; reveals: number };
export type HintAction = 'rfqs' | 'quotes' | 'messages' | 'documents' | 'services' | 'profile';
export type Hint = { code: string; severity: 'high' | 'medium' | 'low'; params: Record<string, number | string>; action: HintAction | null };
export type InsightsSummary = {
  ok: true;
  version: 1;
  currency: 'AED';
  has_data: boolean;
  totals: { inquiries_received: number; quotations_submitted: number; jobs_won: number; revenue_aed: number };
  rates: { win_pct: number | null; reveal_pct: number | null; response_pct: number | null; avg_lead_time_days: number | null; rating: number | null; lost_to_others: number };
  price_position: PricePosition;
  funnel: FunnelStage[];
  series: SeriesPoint[];
  hints: Hint[];
};

const BAND_EDGES = { below_max: -4, above_min: 5 };  // fn_supplier_stats: <= -4 below, < 5 around, else above
const MON: Record<string, string> = { Jan: '01', Feb: '02', Mar: '03', Apr: '04', May: '05', Jun: '06', Jul: '07', Aug: '08', Sep: '09', Oct: '10', Nov: '11', Dec: '12' };
const num = (v: unknown): number | null => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const int = (v: unknown): number => Math.max(0, Math.round(num(v) ?? 0));
const pct = (a: number, b: number): number | null => (b > 0 ? Math.round((100 * a) / b) : null);

/** 'Sep 26' -> '2026-09'. Anything else is kept as it came, so an unexpected label is visible, not dropped. */
export function isoMonth(label: unknown): string {
  const m = /^([A-Z][a-z]{2}) (\d{2})$/.exec(String(label || ''));
  return m && MON[m[1]] ? `20${m[2]}-${MON[m[1]]}` : String(label || '');
}

export function pricePosition(pp: Row | null | undefined): PricePosition {
  const p = pp || {};
  const n = int(p.competitive_rfqs);
  const vsAvg = num(p.avg_pct_vs_average);
  const band: PriceBand = n === 0 || vsAvg == null ? 'no_data'
    : /below/.test(String(p.band)) ? 'below' : /above/.test(String(p.band)) ? 'above' : 'around';
  return {
    band, pct_vs_market_avg: n ? vsAvg : null, pct_above_lowest: n ? num(p.avg_pct_above_lowest) : null,
    lowest_rate_pct: n ? num(p.lowest_rate) : null, competitive_rfqs: n, times_lowest: int(p.times_lowest),
    gauge: n && vsAvg != null ? Math.max(-1, Math.min(1, vsAvg / 20)) : null, band_edges: BAND_EDGES,
  };
}

export function funnel(received: number, s: Row): FunnelStage[] {
  const counts: [FunnelKey, number][] = [['received', received], ['quoted', int(s.quotes_total)], ['revealed', int(s.reveals)], ['won', int(s.hired)]];
  return counts.map(([key, count], i) => ({ key, count, conversion_pct: i === 0 ? null : pct(count, counts[i - 1][1]) }));
}

// THE HINTS. Each one is a rule a supplier can act on today, ordered by what costs them most. A rule
// fires only on a measured number; with no data the only hint is how to start receiving requests.
export function hints(s: Row, received: number, pp: PricePosition, eligible: boolean | null): Hint[] {
  const out: Hint[] = [];
  const quoted = int(s.quotes_total), revealed = int(s.reveals), won = int(s.hired);
  if (eligible === false) out.push({ code: 'hint_not_eligible', severity: 'high', params: {}, action: 'documents' });
  for (const e of (Array.isArray(s.document_expiries) ? s.document_expiries : []) as Row[]) {
    if (e.status === 'expired' || e.status === 'expiring') {
      out.push({ code: e.status === 'expired' ? 'hint_doc_expired' : 'hint_doc_expiring', severity: e.status === 'expired' ? 'high' : 'medium',
        params: { doc: String(e.doc || ''), days: int(Math.abs(num(e.days_left) ?? 0)) }, action: 'documents' });
    }
  }
  const unquoted = Math.max(0, received - quoted);
  if (received > 0 && unquoted > 0 && quoted / received < 0.5) out.push({ code: 'hint_quote_more', severity: 'medium', params: { unquoted, received }, action: 'rfqs' });
  if (pp.band === 'above') out.push({ code: 'hint_price_above', severity: 'medium', params: { pct: Math.round(pp.pct_vs_market_avg ?? 0) }, action: 'quotes' });
  if (pp.band === 'below' && revealed === 0 && quoted >= 3) out.push({ code: 'hint_price_below_no_reveal', severity: 'low', params: { pct: Math.abs(Math.round(pp.pct_vs_market_avg ?? 0)) }, action: 'quotes' });
  if (revealed >= 2 && won / revealed < 0.3) out.push({ code: 'hint_follow_up', severity: 'medium', params: { revealed, won }, action: 'messages' });
  const resp = num(s.response_rate);
  if (resp != null && resp < 80) out.push({ code: 'hint_response_rate', severity: 'medium', params: { pct: Math.round(resp) }, action: 'messages' });
  const lead = num(s.avg_lead_time_days);
  if (lead != null && lead > 30) out.push({ code: 'hint_lead_time', severity: 'low', params: { days: Math.round(lead) }, action: 'quotes' });
  if (received === 0 && eligible !== false) out.push({ code: 'hint_first_request', severity: 'low', params: {}, action: 'services' });
  if (!out.length) out.push({ code: 'hint_all_good', severity: 'low', params: {}, action: null });
  const rank = { high: 0, medium: 1, low: 2 };
  return out.sort((a, b) => rank[a.severity] - rank[b.severity]);
}

/** Pure: the payload from what the three reads returned. */
export function shapeInsights(stats: Row | null, received: number, revenue: number, eligible: boolean | null): InsightsSummary {
  const s = stats || {};
  const pp = pricePosition(s.price_positioning);
  const f = funnel(received, s);
  const series: SeriesPoint[] = (Array.isArray(s.history_12m) ? s.history_12m : []).map((h: Row) => ({ month: isoMonth(h.month), quotes: int(h.quotes), reveals: int(h.reveals) }));
  return {
    ok: true, version: 1, currency: 'AED',
    has_data: f.some((x) => x.count > 0) || series.some((x) => x.quotes + x.reveals > 0),
    totals: { inquiries_received: received, quotations_submitted: int(s.quotes_total), jobs_won: int(s.hired), revenue_aed: Math.max(0, Math.round(revenue)) },
    rates: { win_pct: num(s.win_ratio), reveal_pct: num(s.reveal_ratio), response_pct: num(s.response_rate), avg_lead_time_days: num(s.avg_lead_time_days), rating: num(s.rating), lost_to_others: int(s.lost_to_others) },
    price_position: pp, funnel: f, series, hints: hints(s, received, pp, eligible),
  };
}

/** The reads, all started together. `eligible` may be a promise (the caller's eligibility read), so it runs in the same wave. */
export async function buildInsightsSummary(admin: Admin, supId: number, eligibleIn: boolean | null | Promise<boolean | null> = null): Promise<{ status: number; body: InsightsSummary | Row }> {
  const [eligible, { data: stats, error }, { count: received }, { data: hired }] = await Promise.all([
    Promise.resolve(eligibleIn).catch(() => null),
    admin.rpc('fn_supplier_stats', { p_supplier_id: supId }),
    admin.from('inquiry_matches').select('id', { count: 'exact', head: true }).eq('supplier_id', supId),
    admin.from('inquiries').select('id').eq('hired_supplier_id', supId).limit(1000),
  ]);
  if (error) return { status: 500, body: { ok: false, error: 'stats_unavailable' } };
  const ids = ((hired || []) as Row[]).map((r) => r.id);
  let revenue = 0;
  if (ids.length) {
    const { data: tx } = await admin.from('transactions').select('quote_amount,refund_status').eq('supplier_id', supId).in('inquiry_id', ids);
    revenue = ((tx || []) as Row[]).filter((t) => String(t.refund_status || '') !== 'approved').reduce((a, t) => a + (num(t.quote_amount) ?? 0), 0);
  }
  return { status: 200, body: shapeInsights(stats as Row, received || 0, revenue, eligible) };
}
