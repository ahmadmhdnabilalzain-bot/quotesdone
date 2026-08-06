// The shape of what supabase/functions/customer_intelligence and negotiation_assistant return, and
// the pure derivations the two surfaces in this folder share.
//
// Every type below is transcribed from what the endpoints ACTUALLY emit — nothing is invented:
//   customer_intelligence action:'forecast' -> fn_customer_forecast(customer, horizon_days)
//   negotiation_assistant action:'guidance' -> fn_negotiation_guidance(customer, quote)
//   negotiation_assistant action:'market'   -> fn_price_confidence + public.category_price_stats
// If a field is not here, the endpoint does not serve it. Do not add one without adding it there.
//
// This module imports nothing, so model.test.mjs can execute the derivations straight off the repo
// with no bundler, alias or framework.

export type Lang = 'en' | 'ar';

/* ── §20 AI Predictive Intelligence ───────────────────────────────────────────────────────── */

/**
 * One predicted future requirement — the spec's "you will likely need Electrical cables within 45
 * days, contact suppliers now". Derived by fn_customer_forecast from the customer's OWN history:
 * a category they have procured on their other projects, missing from an open project, offset by
 * the lead time they themselves have observed in that category.
 */
export interface Prediction {
  project_id: string;
  project_name: string;
  category: string;
  target_open_date: string | null;
  /** Days from today until this should be raised. 0 means the lead time has already started. */
  within_days: number;
  expected_by: string;
  /** high | medium | low — how much of the customer's own history stands behind it. */
  confidence: string;
  reason: string;
  recommended_action: string;
}

export interface ForecastCategory {
  category: string;
  observed_rfqs: number;
  observed_value_aed: number;
  share_pct: number | null;
  /** null unless the run-rate floor (3 requests across 2 active months) is cleared. */
  projected_rfqs: number | null;
  projected_spend_aed: number | null;
}

export interface Forecast {
  customer_id: string;
  as_of: string;
  horizon_days: number;
  /** 'no_history' when the account has never raised a request; 'history' otherwise. */
  basis: string;
  sufficient_data: boolean;
  /** Set whenever a figure is withheld. Render it INSTEAD of a number, never beside one. */
  empty_reason: string | null;
  observed: {
    rfqs: number;
    months_active: number;
    spend_aed: number;
    first_rfq: string | null;
    last_rfq: string | null;
  };
  /** [] rather than twelve zeroed months — a flat line at zero is a claim, not an absence. */
  series: Array<{ month: string; rfqs: number; value_aed: number }>;
  next_year: {
    horizon_days: number;
    projected_rfqs: number | null;
    projected_spend_aed: number | null;
    by_category: ForecastCategory[];
  };
  predictions: Prediction[];
}

/* ── §15 AI Negotiation Assistant ─────────────────────────────────────────────────────────── */

export interface Negotiation {
  quote_id: string;
  inquiry_id: string;
  category: string | null;
  quote_amount: number | null;
  supplier_id: number | null;
  /** null before the supplier is revealed. */
  supplier_name: string | null;
  market: Record<string, unknown> | null;
  market_median: number | null;
  market_sample_n: number | null;
  delta_vs_median_pct: number | null;
  /** insufficient_data | suspiciously_low | ... — the band fn_price_confidence assigned. */
  band: string | null;
  policy_scope: string | null;
  /** The house policy's verdict, e.g. 'negotiate_hard', 'no_benchmark_yet', 'no_policy'. */
  recommended_action: string | null;
  ask_discount_pct: number | null;
  /** null whenever the policy or the sample refuses to name one. */
  target_price: number | null;
  headline: string | null;
  suggested_message: string | null;
  suggested_message_ar: string | null;
  empty_reason: string | null;
}

/* ── derivations ──────────────────────────────────────────────────────────────────────────── */

/** A number, or null. '' , null, undefined and NaN are all "not measured", never 0. */
export function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

export interface MarketComparison {
  median: number;
  sampleN: number;
  deltaPct: number;
  direction: 'above' | 'below' | 'level';
}

/**
 * The §15 headline — "your quote against the market average" — or null when there is no market to
 * compare against.
 *
 * THE NULL IS THE FEATURE. Production holds zero quotes, so category_price_stats is empty and
 * fn_negotiation_guidance answers band='insufficient_data' on every call. It ALSO still returns a
 * median and a delta when a thin sample exists but is below the policy's min_sample — the routine
 * withholds the target price and says why. Rendering "12% above market" off two quotes would be the
 * same defect as the empty state that claimed suppliers had been matched whether or not any were:
 * a confident sentence with nothing behind it. So a band the backend calls insufficient is no
 * comparison here either, and the surface prints the headline sentence instead.
 */
export function marketComparison(g: Negotiation | null | undefined): MarketComparison | null {
  if (!g) return null;
  if (!g.band || g.band === 'insufficient_data') return null;
  const median = numOrNull(g.market_median);
  const sampleN = numOrNull(g.market_sample_n);
  const deltaPct = numOrNull(g.delta_vs_median_pct);
  if (median === null || median <= 0 || sampleN === null || sampleN <= 0 || deltaPct === null) return null;
  return {
    median,
    sampleN,
    deltaPct,
    direction: deltaPct > 0 ? 'above' : deltaPct < 0 ? 'below' : 'level',
  };
}

export type Urgency = 'now' | 'soon' | 'planned';

/**
 * How a predicted requirement is badged. The thresholds are presentation only — the number the
 * customer reads is always `within_days` itself, and the recommended action is the backend's own
 * sentence, so a change here can never change what they are told to do.
 */
export function urgency(withinDays: unknown): Urgency {
  const d = numOrNull(withinDays);
  if (d === null) return 'planned';
  if (d <= 0) return 'now';
  if (d <= 14) return 'soon';
  return 'planned';
}

export interface Projection {
  rfqs: number;
  spendAed: number;
  horizonDays: number;
}

/**
 * The next-year projection, or null.
 *
 * fn_customer_forecast withholds both figures until the account clears 3 requests across 2 active
 * months and returns `empty_reason` explaining that. This refuses the projection unless the routine
 * says it is sufficient AND both numbers actually arrived — a straight line drawn through one point
 * is not a forecast, it is a doubled number.
 */
export function projection(f: Forecast | null | undefined): Projection | null {
  if (!f || !f.sufficient_data || !f.next_year) return null;
  const rfqs = numOrNull(f.next_year.projected_rfqs);
  const spendAed = numOrNull(f.next_year.projected_spend_aed);
  if (rfqs === null || spendAed === null) return null;
  return { rfqs, spendAed, horizonDays: numOrNull(f.next_year.horizon_days) ?? numOrNull(f.horizon_days) ?? 365 };
}

/* ── formatting ───────────────────────────────────────────────────────────────────────────── */

export const aed = (n: number, lang: Lang = 'en'): string =>
  `AED ${n.toLocaleString(lang === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 0 })}`;

export const fmtDate = (iso: string | null | undefined, lang: Lang = 'en'): string => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
};
