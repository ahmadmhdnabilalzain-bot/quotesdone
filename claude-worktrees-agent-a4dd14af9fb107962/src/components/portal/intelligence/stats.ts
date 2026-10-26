/**
 * Pure reducers behind the Spending Intelligence charts (customer portal spec §11).
 *
 * They live outside the .tsx on purpose: the quote-spread figure is a money path shown to a paying
 * customer, and logic embedded in a component is logic nothing can execute in isolation. Node 24
 * strips types natively, so spread.test.mjs runs these directly with no framework and no build.
 *
 * Every input field here is one an endpoint already returns — history_12m and inquiries[] from
 * fn_customer_stats (customer_portal action=overview), quotes[].price from customer_api
 * action=my_inquiries. Nothing is estimated or inferred.
 */

/** One point of fn_customer_stats.history_12m — `month` is pre-formatted 'Mon YY' by the RPC. */
export type HistoryPoint = { month?: string | null; inquiries?: number | null };

/** One row of fn_customer_stats.inquiries[]. Only the fields these reducers read are declared. */
export type StatsInquiry = {
  id?: string;
  category?: string | null;
  status?: string | null;
  quotes_count?: number | null;
};

/** A quote row from customer_api my_inquiries. `price` is quotes.quote_amount. */
export type PortalQuote = { price?: number | null };

/** An inquiry row from customer_api my_inquiries. Combined projects carry `children`. */
export type PortalInquiry = {
  id?: string;
  category?: string | null;
  quotes?: PortalQuote[] | null;
  children?: PortalInquiry[] | null;
};

export const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

/** Combined projects hold their quotes on `children`; a flat walk keeps them from being dropped. */
export function flattenInquiries(rows: readonly PortalInquiry[]): PortalInquiry[] {
  const out: PortalInquiry[] = [];
  for (const r of rows) {
    if (!r) continue;
    out.push(r);
    if (Array.isArray(r.children)) out.push(...flattenInquiries(r.children));
  }
  return out;
}

export type TrendSummary = {
  points: { month: string; inquiries: number }[];
  total: number;
  /** 'rising' | 'falling' | 'steady', comparing the later half of the year against the earlier. */
  /** `single`: every request fell in ONE month — a trend needs two (audit 21 Sep 2026, item 18:
   *  "rising over the year" was said of a customer whose whole history was this month). */
  direction: 'rising' | 'falling' | 'steady' | 'single';
  peak: { month: string; inquiries: number };
};

/**
 * Returns null when there is nothing honest to draw: no series at all, or a series that is entirely
 * zero. Twelve zeros is the production state today, and drawing it yields a flat line that reads as
 * a real, quiet year — so the caller is forced to say so in words instead.
 */
export function summariseHistory(history: readonly HistoryPoint[] | null | undefined): TrendSummary | null {
  const points = (Array.isArray(history) ? history : [])
    .filter((p): p is HistoryPoint => !!p)
    .map((p) => ({ month: String(p.month ?? ''), inquiries: num(p.inquiries) }));
  if (!points.length) return null;
  const total = points.reduce((a, p) => a + p.inquiries, 0);
  if (total === 0) return null;
  const half = Math.floor(points.length / 2);
  const early = points.slice(0, half).reduce((a, p) => a + p.inquiries, 0);
  const late = points.slice(half).reduce((a, p) => a + p.inquiries, 0);
  return {
    points,
    total,
    direction: points.filter((p) => p.inquiries > 0).length < 2 ? 'single' : late > early ? 'rising' : late < early ? 'falling' : 'steady',
    peak: points.reduce((best, p) => (p.inquiries > best.inquiries ? p : best), points[0]),
  };
}

/** The RPC pre-formats `month` as English 'Mon YY'; an Arabic reader gets the same month in Arabic
 *  (audit 21 Sep 2026, item 23). Anything that does not parse is returned as served. */
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
export function monthLabel(month: string, lang: string): string {
  if (lang !== 'ar') return month;
  const m = /^([A-Za-z]{3})\s+(\d{2})$/.exec(String(month || '').trim());
  const i = m ? MONTHS.indexOf(m[1].toLowerCase()) : -1;
  if (!m || i < 0) return month;
  return new Date(Date.UTC(2000 + Number(m[2]), i, 1)).toLocaleDateString('ar-AE', { month: 'short', year: '2-digit', timeZone: 'UTC' });
}

/** Requests per category, biggest first. */
export function countByCategory(
  inquiries: readonly StatsInquiry[] | null | undefined,
  uncategorised: string,
): { category: string; requests: number }[] {
  const tally = new Map<string, number>();
  for (const r of Array.isArray(inquiries) ? inquiries : []) {
    if (!r) continue;
    const key = String(r.category ?? '').trim() || uncategorised;
    tally.set(key, (tally.get(key) ?? 0) + 1);
  }
  return [...tally.entries()]
    .map(([category, requests]) => ({ category, requests }))
    .sort((a, b) => b.requests - a.requests);
}

export type SpreadResult = {
  rows: { category: string; spread: number; requests: number }[];
  /** Sum of every per-request gap, in AED. */
  total: number;
  /** How many requests had two or more quotes and therefore contributed. */
  counted: number;
};

/**
 * The gap between the highest and the lowest quote on each request, summed per category.
 *
 * A spread needs TWO quotes on the SAME request — one quote is not a comparison, and a request with
 * one quote must contribute nothing rather than a zero that pads the count. `counted` is what lets
 * the caller tell "you have no requests" apart from "you have requests but none has two quotes";
 * those are different facts and the customer is owed the right one.
 */
export function spreadByCategory(
  inquiries: readonly PortalInquiry[] | null | undefined,
  uncategorised: string,
): SpreadResult {
  const rows = flattenInquiries((Array.isArray(inquiries) ? inquiries : []).filter((r): r is PortalInquiry => !!r));
  const tally = new Map<string, { spread: number; requests: number }>();
  let total = 0;
  let counted = 0;
  for (const r of rows) {
    const prices = (Array.isArray(r.quotes) ? r.quotes : []).map((q) => num(q?.price)).filter((p) => p > 0);
    if (prices.length < 2) continue;
    const gap = Math.max(...prices) - Math.min(...prices);
    const key = String(r.category ?? '').trim() || uncategorised;
    const cur = tally.get(key) ?? { spread: 0, requests: 0 };
    tally.set(key, { spread: cur.spread + gap, requests: cur.requests + 1 });
    total += gap;
    counted += 1;
  }
  return {
    rows: [...tally.entries()]
      .map(([category, v]) => ({ category, spread: Math.round(v.spread), requests: v.requests }))
      .sort((a, b) => b.spread - a.spread),
    total: Math.round(total),
    counted,
  };
}
