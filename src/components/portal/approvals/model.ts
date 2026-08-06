// The shape of what supabase/functions/procurement_api returns, and the pure derivations the two
// surfaces in this folder share.
//
// Every type below is transcribed from what the endpoint ACTUALLY emits — nothing is invented:
//   action:'approvals' -> fn_approval_list(customer)   { organizations[], policies[], requests[] }
//                         each request carries steps[] already projected by public.v_approval_trace
//   action:'trace'     -> { request, steps[] }         the same step shape, one request
//   action:'decide'    -> fn_approval_decide(...)      { ok, status, decided_step, current_step, ... }
//   action:'orders'    -> fn_customer_orders(customer) po_orders scoped to this customer, with lines[]
// If a field is not here, procurement_api does not serve it. Do not add one without adding it there.
//
// This module imports nothing, so orders.test.mjs can execute the derivations straight off the repo
// with no bundler, alias or framework.

export type Lang = 'en' | 'ar';

/* ── §12 Purchase Approval System ─────────────────────────────────────────────────────────── */

/**
 * The five states public.v_approval_trace can put a step in.
 *  approved / rejected — a decision was recorded against THIS step
 *  pending            — this is the step the chain is waiting on right now
 *  waiting            — a later step that has not been reached
 *  blocked            — an earlier rejection stopped the chain before this step
 */
export const STEP_STATUSES = ['approved', 'rejected', 'pending', 'waiting', 'blocked'] as const;
export type StepStatus = (typeof STEP_STATUSES)[number];

/** One row of public.v_approval_trace, as fn_approval_list nests it under a request. */
export interface ApprovalStep {
  step: number;
  key: string | null;
  label: string;
  role: string | null;
  /** One of STEP_STATUSES. Typed wide because the view is the authority, not this file. */
  status: string;
  decided_by: string | null;
  decided_at: string | null;
  note: string | null;
}

/** One public.procurement_approval_request, with its chain already projected. */
export interface ApprovalRequest {
  id: string;
  organization_id: string;
  entity_type: string | null;
  entity_id: string | null;
  policy_id: string | null;
  /** pending | approved | rejected */
  status: string;
  current_step: number;
  created_at: string;
  steps: ApprovalStep[];
}

/** One public.procurement_approval_policy — the named chain, before anything has run through it. */
export interface ApprovalPolicy {
  id: string;
  organization_id: string;
  name: string | null;
  active: boolean | null;
  conditions: Record<string, unknown> | null;
  steps: Array<{ key?: string; label?: string; role?: string }> | null;
}

export interface Organization {
  id: string;
  name: string | null;
}

export interface ApprovalsPayload {
  organizations: Organization[];
  policies: ApprovalPolicy[];
  requests: ApprovalRequest[];
}

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

export interface ChainProgress {
  total: number;
  approved: number;
  rejected: number;
  /** The step the chain is waiting on, or null when it is finished or stopped. */
  pending: ApprovalStep | null;
}

export function chainProgress(steps: ApprovalStep[] | null | undefined): ChainProgress {
  const rows = Array.isArray(steps) ? steps : [];
  return {
    total: rows.length,
    approved: rows.filter((s) => s.status === 'approved').length,
    rejected: rows.filter((s) => s.status === 'rejected').length,
    pending: rows.find((s) => s.status === 'pending') ?? null,
  };
}

/**
 * May this customer act on this step right now?
 *
 * Both halves are checked even though v_approval_trace only ever marks the current step 'pending':
 * a decide button that appears against a closed request would let a customer fire a call the
 * database will refuse, and an error toast is a worse answer than not offering the control.
 * The authority is still fn_approval_decide — it re-checks membership and the step's role in SQL.
 */
export function canDecide(request: ApprovalRequest, step: ApprovalStep): boolean {
  return request.status === 'pending' && step.status === 'pending' && step.step === request.current_step;
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
