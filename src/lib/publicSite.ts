// Client for the public_site edge function (deterministic, no sign-in). See
// supabase/functions/public_site/index.ts for what each action returns and what it never returns.
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';

const FN = fnUrl('public_site');

// Measured 2 Nov 2026 (function_edge_logs, 24 h): of 2,766 public_site POSTs, 22 ended 546 "CPU Time
// exceeded", 12 ended 502 and 5 ended 503 (1.4%); 9 of 1,230 preflights ended 502. A runtime kill or a
// gateway error carries no Access-Control-Allow-Origin, so the browser reports it as a CORS failure
// (net::ERR_FAILED) and fetch() throws. Every action is a read, so ONE retry after a short pause is safe
// and almost always lands on a healthy instance. A second failure still throws; every caller already
// renders its fallback on a throw.
const RETRY_STATUS = new Set([500, 502, 503, 504, 546]);
export async function publicSite<T = any>(action: string, body: Record<string, unknown> = {}): Promise<T & { ok?: boolean; rate_limited?: boolean }> {
  const init: RequestInit = {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPA_ANON, Authorization: `Bearer ${SUPA_ANON}` },
    body: JSON.stringify({ action, ...body }),
  };
  let r: Response;
  try { r = await fetch(FN, init); if (RETRY_STATUS.has(r.status)) throw new Error('retry'); }
  catch (_e) { await new Promise((ok) => setTimeout(ok, 400)); r = await fetch(FN, init); }
  if (r.status === 429) return { ok: false, rate_limited: true } as any;
  return r.json();
}

export type Counters = {
  ok?: boolean;
  licence_verified_suppliers: number | null;
  jobs_this_month: number | null;
  median_hours_to_first_quote: number | null;
  median_basis_jobs: number | null;
  categories_covered: number | null;
  per_trade: Record<string, number>;
};

// One request per page view, shared by every section that shows a count (hero strip, category
// tiles, the CTA median). A failure resolves to null and every consumer renders its fallback.
let countersP: Promise<Counters | null> | null = null;
export function getCounters(): Promise<Counters | null> {
  if (!countersP) {
    countersP = publicSite<Counters>('counters').then((j) => (j && j.ok ? j : null)).catch(() => null);
  }
  return countersP;
}

/** The hand-off the customer portal consumes on /me?draft=1. Exactly this shape. */
export type DraftBrief = { text: string; category: string | null; emirate: string | null; ts: number };
export const DRAFT_KEY = 'qd-draft-brief';
export function saveDraft(d: Omit<DraftBrief, 'ts'>) {
  try { localStorage.setItem(DRAFT_KEY, JSON.stringify({ ...d, ts: Date.now() })); } catch (_e) { /* private mode: /me starts empty */ }
}

/** Numbers in the reader's locale — ar-AE keeps Western digits, as the rest of the site does. */
export const fmtNum = (n: number, locale: string) =>
  new Intl.NumberFormat(locale === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 1 }).format(n);
