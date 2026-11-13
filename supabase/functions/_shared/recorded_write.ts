// A WRITE A PERSON DEPENDS ON IS RECORDED, OR ITS CALLER KNOWS IT WAS NOT (it_engineer, 13 Nov 2026).
//
// MEASURED 13 Nov 2026: while rolled-back rehearsals held table locks on production (scripts/lib/replay_guard.mjs), writes
// a person depended on were cancelled by the functions' 8 s statement timeout: a supplier's agreement certificate onto
// leads (compliance_archive, 07:46:10) and a customer's acceptance of the terms (kyc, 08:47), whose result kyc never read.
// Any table lock (an apply, a deploy's migration) can do the same, so these writes are read back and a blip is retried.
//
// The write must come back with the row(s) it wrote (`.select('id')`). A blip (statement or lock timeout, serialization
// failure, deadlock, a dropped connection, a 5xx) is tried again, 3 times in all, 0.8 s then 2 s apart; a caller passes
// only a write that is safe to repeat (the same values, or a compare-and-set). Anything else, or a blip that persists,
// comes back { ok: false } with the reason, and the caller says so to the person and to a seat.
export type WriteResult = { data: unknown[] | null; error: { message?: string; code?: string } | null };
export type Recorded = { ok: true; attempts: number; data: unknown[] } | { ok: false; attempts: number; reason: string; blip: boolean };

const BLIP = /statement timeout|lock timeout|canceling statement|57014|55P03|40001|40P01|fetch failed|connection|ECONNRESET|timed out|\b(?:HTTP|status) 5\d\d\b/i;
export const isBlip = (msg: string) => BLIP.test(msg);

// A PERSON'S PAGE WAITS FOR THIS (13 Nov 2026, review item 8). Each attempt can take up to the live role's 8 s statement_timeout,
// so 3 attempts + the two pauses were up to ~26.8 s, past a portal page's 30 s abort once the request's own reads are added:
// the person saw a timeout instead of the sentence. `budgetMs` stops before an attempt that could end past it (elapsed + the
// pause + one worst-case attempt, `attemptMs`), so a caller a page waits on answers within its budget; without one, unbounded.
export async function writeRecorded(write: () => PromiseLike<WriteResult>, waits: number[] = [800, 2000],
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((r) => setTimeout(r, ms)),
  { emptyIsFinal = true, budgetMs = Infinity, attemptMs = 8000, now = Date.now }:
    { emptyIsFinal?: boolean; budgetMs?: number; attemptMs?: number; now?: () => number } = {}): Promise<Recorded> {
  let reason = ''; let blip = false; const t0 = now();
  for (let attempt = 1; attempt <= waits.length + 1; attempt++) {
    let res: WriteResult;
    try { res = await write(); } catch (e) { res = { data: null, error: { message: String((e as Error)?.message ?? e) } }; }
    if (!res.error && Array.isArray(res.data) && res.data.length > 0) return { ok: true, attempts: attempt, data: res.data };
    reason = res.error ? String(res.error.message ?? res.error.code ?? 'write failed') : 'the write matched no row';
    blip = !!res.error && isBlip(reason);
    if ((!res.error && emptyIsFinal) || (res.error && !blip) || attempt > waits.length) return { ok: false, attempts: attempt, reason: reason.slice(0, 300), blip };
    if (now() - t0 + waits[attempt - 1] + attemptMs > budgetMs) return { ok: false, attempts: attempt, reason: `${reason.slice(0, 260)} (no time left to try again)`, blip };
    await sleep(waits[attempt - 1]);
  }
  return { ok: false, attempts: waits.length + 1, reason, blip };
}

// AN ACCEPTANCE OF THE TERMS (kyc accept_terms for both kinds; supplier_api accept_terms for the supplier portal's own record).
// THE PAGE'S CLOCK (13 Nov 2026, review item 8). ProfileGate and the supplier portal abort at 30 s. Worst case now: an attempt
// cancelled at the 8 s statement_timeout, 0.8 s, a second one cancelled at 8 s = 16.8 s, and a third attempt is not started
// (16.8 + 2 + 8 > 18); with the request's own reads (one round trip, ~0.3 s) the 503 sentence is on his screen by ~17-18 s,
// 12 s inside the abort. A quick blip (a lock timeout, a dropped connection) still gets all three tries. The same values are
// written on every try, so a retry cannot record a second acceptance.
export const ACCEPTANCE_BUDGET_MS = 18_000;
export const recordAcceptance = (write: () => PromiseLike<WriteResult>, waits?: number[], sleep?: (ms: number) => Promise<void>,
  now?: () => number) => writeRecorded(write, waits, sleep, { budgetMs: ACCEPTANCE_BUDGET_MS, now });

/** What the person reads: in both languages, so the portal shows it as it is (portalText errText), and retryable. */
export const TERMS_NOT_RECORDED = {
  error: 'terms_not_recorded', code: 'terms_not_recorded', retryable: true,
  message: 'We could not record your acceptance just now, so your account is not complete yet. Nothing was lost: please press the button again in a moment.',
  message_ar: 'تعذّر علينا تسجيل موافقتك الآن، لذا لم يكتمل حسابك بعد. لم يُفقد شيء: يُرجى الضغط على الزر مرة أخرى بعد لحظة.',
} as const;
