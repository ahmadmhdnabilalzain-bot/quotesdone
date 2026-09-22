// ============================================================================================
// NO PAID CALL REPEATS ITSELF — the pure rules ai_gateway and its callers apply before a paid
// model call. Measured 22 Sep 2026 against origin/main and production, with the founder's hold in
// force (nothing was called; ai_cost_log's HELD rows are the demand):
//
//   * quote_compare looped 2 attempts over a gateway that itself looped 2 attempts over a 2-model
//     ladder: up to 8 provider calls, each up to 10,000 output tokens, per card view. 1,207
//     requests / 2,382 held attempts in 30 days.
//   * The gateway retried the SAME model after a 401/402/400 — an answer that cannot change on a
//     second asking — and fell back to the next model after a 402 (no credit), which is the same
//     account.
//   * Nearly all measured demand was our own E2E harness (post-merge smoke 94 runs / 30 d, nightly
//     journey), running ZZ DEMO / @example.invalid fixtures through the same paid routes as a
//     customer. The founder, 22 Sep 2026 (instruction 705): a bug or repeated work that costs us
//     something must be fixed before activation; real customer usage is not limited.
//
// Everything here is pure and tested in spend_guards.test.ts. No money cap lives here — ceilings
// are the founder's (instruction 639).
// ============================================================================================

/** The most provider calls one gateway request may make, across the whole model ladder. */
export const MAX_PAID_CALLS_PER_REQUEST = 2;

/**
 * The order of paid attempts for a ladder, bounded at `max` in total. A two-model ladder gets one
 * try on each; a one-model ladder gets its one retry. Never more than `max`, whatever the ladder.
 */
export function attemptPlan(ladder: string[], max = MAX_PAID_CALLS_PER_REQUEST): string[] {
  const models = ladder.filter(Boolean);
  if (!models.length || max <= 0) return [];
  const plan = models.slice(0, max);
  while (plan.length < max) plan.push(models[models.length - 1]);   // spare budget retries the last model
  return plan;
}

/**
 * Walk the plan after a failure on plan[i]: the index of the next attempt, or -1 to stop.
 * 'next' skips every remaining entry for the same model, because it will refuse the same way.
 */
export function nextAttempt(plan: string[], i: number, kind: 'stop' | 'next' | 'retry'): number {
  if (kind === 'stop') return -1;
  let j = i + 1;
  if (kind === 'next') while (j < plan.length && plan[j] === plan[i]) j++;
  return j < plan.length ? j : -1;
}

/**
 * What a failed provider response means for the rest of the ladder.
 *   'stop'  - the account itself refused (bad key, no credit, forbidden): no model on this
 *             account can answer, so another paid attempt is money for nothing.
 *   'next'  - this request is wrong for THIS model (bad payload, too large, unknown model): the
 *             same model will refuse again; the next model on the ladder might not.
 *   'retry' - transient (timeout, rate limit, 5xx, network, empty completion): worth one more try.
 */
export function failureKind(status: number | null): 'stop' | 'next' | 'retry' {
  if (status === 401 || status === 402 || status === 403) return 'stop';
  if (status === 400 || status === 404 || status === 413 || status === 422) return 'next';
  return 'retry';
}

/**
 * Our OWN automated work, named by the calling function. `fn` is declared by an internal caller
 * that already authenticated with a scoped credential; no customer can reach the gateway or set it.
 */
const OWN_WORK_FN = /(^|_)(probe|rehearsal|smoke|e2e|eval|harness|fixture)(_|$)/i;
export function ownWorkByName(fn: string | null | undefined): boolean {
  return OWN_WORK_FN.test(String(fn || ''));
}

/** The subject a caller names so the gateway can ask the database whether it is a fixture. */
export type AiSubject = {
  inquiry_id?: string | null;
  customer_id?: string | null;
  supplier_id?: string | number | null;
  email?: string | null;
  phone?: string | null;
};

/** Keep only the keys the database check reads, as strings; null when nothing is named. */
export function subjectOf(v: unknown): AiSubject | null {
  if (!v || typeof v !== 'object') return null;
  const s = v as Record<string, unknown>;
  const out: Record<string, string> = {};
  for (const k of ['inquiry_id', 'customer_id', 'supplier_id', 'email', 'phone']) {
    const x = s[k];
    if (x !== null && x !== undefined && String(x).trim() !== '') out[k] = String(x).trim().slice(0, 200);
  }
  return Object.keys(out).length ? out as AiSubject : null;
}

/**
 * Read public.fn_ai_subject_is_fixture's answer. ONLY an explicit `fixture === false` lets a named
 * subject through to a paid call: an error, a null or an odd shape is treated as "cannot prove this
 * is a customer", and our own traffic must never be the thing that spends by accident.
 */
export function fixtureVerdict(data: unknown, error: unknown): { stub: boolean; why: string } {
  if (error) return { stub: true, why: 'the fixture check failed (' + String((error as { message?: string })?.message ?? error).slice(0, 120) + '), so no paid call was made' };
  if (!data || typeof data !== 'object') return { stub: true, why: 'the fixture check returned nothing, so no paid call was made' };
  const d = data as { fixture?: unknown; why?: unknown };
  if (d.fixture === false) return { stub: false, why: '' };
  if (d.fixture === true) return { stub: true, why: String(d.why ?? 'fixture subject') };
  return { stub: true, why: 'the fixture check gave no yes/no answer, so no paid call was made' };
}

// ---- quote_compare: a failure is cached too ---------------------------------------------------
// A degraded answer used to be deliberately NOT cached "so the model result wins the moment the
// model works again" — which also meant a failing input re-spent the whole ladder on every card
// view. The failure is now cached with a short retry-after that doubles per consecutive failure.
export const COMPARE_RETRY_BASE_MS = 15 * 60 * 1000;      // 15 minutes after the first failure
export const COMPARE_RETRY_MAX_MS = 24 * 60 * 60 * 1000;  // never longer than a day

export type CompareFailure = { count: number; at: string; retry_after: string; detail: string };

/** The failure marker stored in qd_compare_cache.analysis, carrying the previous count forward. */
export function failureRecord(prev: unknown, detail: string, now = new Date()): { __failed: CompareFailure } {
  const p = (prev && typeof prev === 'object') ? (prev as { __failed?: CompareFailure }).__failed : undefined;
  const count = Math.max(0, Number(p?.count) || 0) + 1;
  const wait = Math.min(COMPARE_RETRY_MAX_MS, COMPARE_RETRY_BASE_MS * 2 ** (count - 1));
  return { __failed: { count, at: now.toISOString(), retry_after: new Date(now.getTime() + wait).toISOString(), detail: String(detail || '').slice(0, 200) } };
}

/** The cached failure that still holds (retry_after in the future), or null. */
export function activeFailure(analysis: unknown, now = new Date()): CompareFailure | null {
  const f = (analysis && typeof analysis === 'object') ? (analysis as { __failed?: CompareFailure }).__failed : undefined;
  if (!f) return null;
  const t = Date.parse(String(f.retry_after || ''));
  return Number.isFinite(t) && t > now.getTime() ? f : null;
}

/** A cached row is a real analysis only when it is an object that is not a failure marker. */
export function isCachedAnalysis(analysis: unknown): boolean {
  return !!analysis && typeof analysis === 'object' && !('__failed' in (analysis as Record<string, unknown>));
}
