// Client for the public_site edge function (deterministic, no sign-in). See
// supabase/functions/public_site/index.ts for what each action returns and what it never returns.
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';

const FN = fnUrl('public_site');

export async function publicSite<T = any>(action: string, body: Record<string, unknown> = {}): Promise<T & { ok?: boolean; rate_limited?: boolean }> {
  const r = await fetch(FN, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: SUPA_ANON, Authorization: `Bearer ${SUPA_ANON}` },
    body: JSON.stringify({ action, ...body }),
  });
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
