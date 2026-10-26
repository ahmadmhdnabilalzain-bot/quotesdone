// The shape of what supabase/functions/customer_intelligence returns, and the pure derivations the
// surface in this folder uses.
//
// Every type below is transcribed from what the endpoints ACTUALLY emit — nothing is invented:
//   customer_intelligence action:'forecast' -> fn_customer_forecast(customer, horizon_days)
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

/* ── derivations ──────────────────────────────────────────────────────────────────────────── */

/** A number, or null. '' , null, undefined and NaN are all "not measured", never 0. */
export function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
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
