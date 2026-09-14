// The shape of what supabase/functions/procurement_api returns, and the pure order derivations.
//
// Every type below is transcribed from what the endpoint ACTUALLY emits — nothing is invented:
//   action:'orders'    -> fn_customer_orders(customer) po_orders scoped to this customer, with lines[]
// If a field is not here, procurement_api does not serve it. Do not add one without adding it there.
//
// 14 Sep 2026: the §12 approval types (steps, requests, policies, organisations) and their two
// derivations were removed with the Approvals tab — see ./index.ts for the founder's ruling.
//
// This module imports nothing, so model.test.mjs can execute the derivations straight off the repo
// with no bundler, alias or framework.

export type Lang = 'en' | 'ar';

/* ── §22 Orders ───────────────────────────────────────────────────────────────────────────── */

export interface OrderLine {
  line_no: number | null;
  description: string | null;
  qty: number | null;
  unit_price: number | null;
  qty_received: number | null;
}

/** One public.po_orders row scoped to this customer. vendor_id is deliberately not served. */
export interface CustomerOrder {
  id: string;
  po_no: string | null;
  status: string | null;
  order_date: string | null;
  expected_date: string | null;
  currency: string | null;
  subtotal: number | null;
  memo: string | null;
  inquiry_id: string | null;
  quote_id: string | null;
  project_id: string | null;
  approved_at: string | null;
  lines: OrderLine[];
}

/* ── derivations ──────────────────────────────────────────────────────────────────────────── */

/** A number, or null. '' , null, undefined and NaN are all "not measured", never 0. */
export function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * What an order is worth.
 *
 * po_orders.subtotal is the authority. Lines are summed ONLY when subtotal is absent and EVERY line
 * carries both a quantity and a price — a sum over the priced half of an order is a smaller number
 * than the order, and presenting it as the total is a lie with a decimal point on it.
 */
export function orderValue(o: CustomerOrder): number | null {
  const sub = numOrNull(o.subtotal);
  if (sub !== null) return sub;
  const lines = Array.isArray(o.lines) ? o.lines : [];
  if (!lines.length) return null;
  let total = 0;
  for (const l of lines) {
    const qty = numOrNull(l.qty);
    const price = numOrNull(l.unit_price);
    if (qty === null || price === null) return null;
    total += qty * price;
  }
  return total;
}

/**
 * Percent of the ordered quantity that has been received, or null when nothing has been recorded.
 *
 * A line with qty_received null has not been counted, which is NOT the same fact as a line with
 * zero received — so an order where nothing was ever recorded returns null and the surface says so,
 * rather than showing a confident 0% delivered. Over-receipt is returned as it is (>100) instead of
 * being clamped, because a clamped number hides a real discrepancy.
 */
export function receivedPct(lines: OrderLine[] | null | undefined): number | null {
  const rows = (Array.isArray(lines) ? lines : []).filter((l) => (numOrNull(l.qty) ?? 0) > 0);
  if (!rows.length) return null;
  if (!rows.some((l) => numOrNull(l.qty_received) !== null)) return null;
  const ordered = rows.reduce((s, l) => s + (numOrNull(l.qty) ?? 0), 0);
  if (ordered <= 0) return null;
  const got = rows.reduce((s, l) => s + Math.max(0, numOrNull(l.qty_received) ?? 0), 0);
  return Math.round((100 * got) / ordered);
}

/* ── formatting ───────────────────────────────────────────────────────────────────────────── */

export const money = (n: number, currency = 'AED', lang: Lang = 'en'): string =>
  `${currency || 'AED'} ${n.toLocaleString(lang === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 2 })}`;

export const fmtDate = (iso: string | null | undefined, lang: Lang = 'en'): string => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
};
