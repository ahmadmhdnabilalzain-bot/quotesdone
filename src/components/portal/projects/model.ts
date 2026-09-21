// The shape of what project_api returns, and the pure derivations the two project surfaces share.
//
// Every type below is transcribed from what supabase/functions/project_api/index.ts ACTUALLY
// selects — nothing is invented:
//   action:'list'   -> public.project_summary (the view's 11 columns, full_schema.sql line 7202)
//   action:'detail' -> a public.projects row + the 10 inquiry columns the handler names
//   action:'create' -> the inserted public.projects row (note: `id`, not the view's `project_id`)
//   action:'update' -> { ok: true } only, no row echoed back
//   action:'link' / 'unlink' -> { ok: true }
// If a field is not here, project_api does not serve it. Do not add one without adding it there.
//
// This module deliberately imports nothing, so the derivations below can be exercised directly by
// selfcheck.ts without a bundler, an alias or a test framework.

export type Lang = 'en' | 'ar';

/** Status values `action:'update'` will accept. Anything else it silently ignores. */
export const PROJECT_STATUSES = ['active', 'completed', 'archived'] as const;
export type ProjectStatus = (typeof PROJECT_STATUSES)[number];

/** One row of public.project_summary — what `action:'list'` returns in `projects`. */
export interface ProjectSummary {
  project_id: string;
  customer_id: string | null;
  name: string;
  status: string;
  target_open_date: string | null;
  budget_total: number | null;
  created_at: string;
  rfq_count: number;
  rfq_open: number;
  rfq_awarded: number;
  pipeline_value: number;
}

/** One row of public.projects — what `action:'detail'` and `action:'create'` return in `project`. */
export interface Project {
  id: string;
  customer_id: string | null;
  name: string;
  description: string | null;
  status: string;
  target_open_date: string | null;
  budget_total: number | null;
  meta: Record<string, unknown> | null;
  created_at: string;
  updated_at: string | null;
}

/** An RFQ linked to a project — exactly the columns `action:'detail'` selects from public.inquiries. */
export interface ProjectRfq {
  id: string;
  category: string | null;
  emirate: string | null;
  summary: string | null;
  status: string | null;
  pipeline_stage: string | null;
  budget: number | null;
  expected_value: number | null;
  /** The quote the customer paid to reveal on this RFQ (transactions.quote_amount), else null. */
  revealed_value?: number | null;
  hired_supplier_id: string | null;
  created_at: string;
}

/** The cost of an RFQ: expected_value when set, else the revealed quote, else null (never 0-for-unknown). */
export const rfqValue = (r: Pick<ProjectRfq, 'expected_value' | 'revealed_value'>): number | null => {
  const e = Number(r.expected_value); if (e > 0) return e;
  const v = Number(r.revealed_value); return v > 0 ? v : null;
};

/**
 * project_summary counts rfq_open as `status <> ALL (ARRAY['completed','cancelled'])`.
 * The detail workspace derives its own counts from the RFQ rows, so it uses the SAME rule here —
 * otherwise a project card and the project it opens would show two different "active RFQs".
 */
const CLOSED_RFQ_STATUSES = ['completed', 'cancelled'];
export const isOpenRfq = (r: ProjectRfq): boolean => !CLOSED_RFQ_STATUSES.includes(String(r.status || ''));

export interface DerivedStats {
  rfqCount: number;
  open: number;
  /** RFQs carrying a hired_supplier_id. */
  awarded: number;
  /** Sum of rfqValue across linked RFQs — the figure project_api's list serves as pipeline_value. */
  pipeline: number;
  /** Distinct non-empty `category` across linked RFQs. NOT a materials list; project_api has none. */
  categories: string[];
  /** Distinct non-null `hired_supplier_id`. Suppliers AWARDED, not suppliers matched — the API
   *  exposes no per-project matched or invited supplier count. */
  awardedSupplierCount: number;
}

export function deriveStats(rfqs: ProjectRfq[]): DerivedStats {
  const categories: string[] = [];
  const suppliers = new Set<string>();
  let open = 0;
  let awarded = 0;
  let pipeline = 0;
  for (const r of rfqs) {
    if (isOpenRfq(r)) open += 1;
    if (r.hired_supplier_id) {
      awarded += 1;
      suppliers.add(r.hired_supplier_id);
    }
    pipeline += rfqValue(r) || 0;
    const c = (r.category || '').trim();
    if (c && !categories.includes(c)) categories.push(c);
  }
  return { rfqCount: rfqs.length, open, awarded, pipeline, categories: categories.sort(), awardedSupplierCount: suppliers.size };
}

/**
 * Share of the window between a project's creation and its target open date that has already
 * passed, clamped to 0-100.
 *
 * This is NOT a completion percentage. project_api serves no progress, milestone or schedule field,
 * so there is nothing to compute one from; the spec's "Timeline: 68%" cannot be answered honestly
 * today. Returns null when no target date is set, or when the target is on or before creation, so
 * the UI can say that plainly instead of drawing a bar out of nothing.
 */
export function elapsedPct(created_at: string, target_open_date: string | null, now: number = Date.now()): number | null {
  if (!target_open_date) return null;
  const start = new Date(created_at).getTime();
  const end = new Date(`${target_open_date}T00:00:00Z`).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
  const pct = ((now - start) / (end - start)) * 100;
  return Math.max(0, Math.min(100, Math.round(pct)));
}

export const aed = (n: number | null | undefined): string =>
  `AED ${Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 })}`;

export const fmtDate = (d: string | null | undefined, lang: Lang = 'en'): string => {
  if (!d) return '—';
  const t = new Date(d.length === 10 ? `${d}T00:00:00Z` : d).getTime();
  if (!Number.isFinite(t)) return '—';
  return new Date(t).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-AE', {
    year: 'numeric', month: 'short', day: 'numeric', timeZone: 'UTC',
  });
};
