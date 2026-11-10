// A REQUEST THE MATCHER COULD NOT REACH IS MATCHED AGAIN (sales_engineer, customer-journey follow-up 10 Nov 2026).
//
// MEASURED on origin/main (lib/matching.ts, the !routerAnswered branch): when the sales engineer's `match` call failed
// twice, 1.5 s apart, the request was left with routing.matcher_unavailable = true and no supplier, and NOTHING ever
// asked again. fn_sales_engineer_closes_unreached_requests then closed it after 14 days telling the customer "we are
// still registering suppliers for this trade" — a trade we never searched — and the portal said the same at post time
// (nr_posted_none). The IT finding used one fixed key, so a second outage collapsed onto the first and its evidence
// named only the last inquiry.
//
// What happens now:
//   * matchAndNotify records the failure ON the request: routing.rematch = { attempts, first_failed_at, next_at,
//     exhausted, extra } (extra is the supplier note built at posting, which no column keeps), raises the finding under
//     a key per request (sales_engineer_match_unavailable:<id>), and does not put the request in the stalled-supplier
//     rescue: "none of the suppliers registered for it can take it on" would be just as false.
//   * this sweep, run by resilience_ping's specoffer step (the sales engineer's existing 15-minute beat, no new cron),
//     asks the matcher again for every waiting request whose next_at has come, on the backoff in
//     decision_policy.rematch_backoff_minutes. A request that is matched closes its finding and the customer is told
//     (fn_sales_engineer_rematch_told); one that is still unanswered waits for the next step of the backoff; after the
//     last step it is `exhausted` and only then may the 14-day closer take it, with a reason that says it was our fault.
//   * the customer is told the truth at post time: "we are matching your request; you will hear from us shortly".
// prevented by: supabase/functions/customer_api/rematch.test.ts

// The default schedule, used only when decision_policy.rematch_backoff_minutes cannot be read. It is the row the SQL
// seeds (scripts/sql/a_request_the_matcher_could_not_reach_is_matched_again_and_never_closed_as_unreached.sql): ten
// tries over about six days, so a matcher outage of a working day costs a customer a delay, never a request.
export const DEFAULT_REMATCH_BACKOFF_MINUTES: readonly number[] = [15, 30, 60, 180, 360, 720, 1440, 1440, 1440, 2880];

/** The schedule from decision_policy's value, or the default when it is missing or not a list of positive minutes. */
export function rematchSchedule(value: unknown): number[] {
  const ok = Array.isArray(value) && value.length > 0 && value.every((m) => typeof m === 'number' && Number.isFinite(m) && m > 0);
  return ok ? (value as number[]).slice() : DEFAULT_REMATCH_BACKOFF_MINUTES.slice();
}

export type RematchState = { attempts: number; first_failed_at: string; failed_at: string; next_at: string | null; exhausted: boolean; extra: string };

/** After the `attempts`-th failed match (1 = the one at posting), when to ask again — or that the schedule is spent. */
export function nextRematch(attempts: number, failedAt: Date, schedule: readonly number[]): { next_at: string | null; exhausted: boolean } {
  const step = Math.max(1, Math.floor(attempts)) - 1;
  if (step >= schedule.length) return { next_at: null, exhausted: true };
  return { next_at: new Date(failedAt.getTime() + schedule[step] * 60_000).toISOString(), exhausted: false };
}

/** The record matchAndNotify writes on a request the matcher did not answer. `prior` is the state it carried before. */
export function failedState(prior: Partial<RematchState> | null | undefined, extra: string, failedAt: Date, schedule: readonly number[]): RematchState {
  const attempts = (Number(prior?.attempts) || 0) + 1;
  const { next_at, exhausted } = nextRematch(attempts, failedAt, schedule);
  return { attempts, first_failed_at: String(prior?.first_failed_at || failedAt.toISOString()), failed_at: failedAt.toISOString(), next_at, exhausted, extra };
}

/** True when this request is waiting on the matcher and its next try has come. */
export function rematchDue(routing: unknown, now: Date): boolean {
  const r = (routing && typeof routing === 'object' ? routing : {}) as Record<string, any>;
  if (r.matcher_unavailable !== true) return false;
  const s = r.rematch;
  // A request that failed before this file existed carries no schedule: it is due at once, as attempt 1.
  if (!s || typeof s !== 'object') return true;
  if (s.exhausted === true) return false;
  const at = Date.parse(String(s.next_at || ''));
  return Number.isFinite(at) && at <= now.getTime();
}

/** The issue key of one request's matcher outage: one finding per request, so a second outage cannot hide behind the first. */
export const matcherFindingKey = (inquiryId: string) => 'sales_engineer_match_unavailable:' + inquiryId;

export type WaitingRequest = { id: string; category: string | null; emirate: string | null; summary: string | null; budget: string | null; routing: any };
export type MatchOpts = { category: string; emirate: string | null; summary: string; budget: string | null; extra: string };
export type RematchIO = {
  /** Open requests whose routing says the matcher did not answer (status 'sent', parent not closed). */
  waiting: (limit: number) => Promise<WaitingRequest[]>;
  /** Push next_at forward by a lease, only while it is still `before`: of two sweeps, one takes the request. */
  claim: (id: string, routingBefore: any, leaseUntil: string) => Promise<boolean>;
  /** matchAndNotify again, carrying the state so attempts and the first failure survive. */
  match: (id: string, opts: MatchOpts, prior: Partial<RematchState> | null) => Promise<{ matches: number; routing: any }>;
  /** fn_sales_engineer_rematch_told: the customer hears that the request has reached suppliers. */
  told: (id: string, matches: number) => Promise<unknown>;
  closeFinding: (id: string, note: string) => Promise<void>;
};
export type RematchResult = { waiting: number; due: number; rematched: number; reached: number; still_waiting: number; exhausted: number; errors: string[] };

const LEASE_MS = 10 * 60_000;

export async function rematchWaiting(io: RematchIO, now = new Date(), limit = 10): Promise<RematchResult> {
  const out: RematchResult = { waiting: 0, due: 0, rematched: 0, reached: 0, still_waiting: 0, exhausted: 0, errors: [] };
  let rows: WaitingRequest[] = [];
  try { rows = await io.waiting(50); } catch (e) { out.errors.push('waiting: ' + String((e as Error)?.message || e)); return out; }
  out.waiting = rows.length;
  const due = rows.filter((r) => rematchDue(r.routing, now)).slice(0, Math.max(1, limit));
  out.due = due.length;
  for (const r of due) {
    try {
      if (!(await io.claim(r.id, r.routing, new Date(now.getTime() + LEASE_MS).toISOString()))) continue;
      const prior = (r.routing?.rematch && typeof r.routing.rematch === 'object') ? r.routing.rematch as Partial<RematchState> : null;
      const opts: MatchOpts = { category: String(r.category || ''), emirate: r.emirate ?? null, summary: String(r.summary || ''), budget: r.budget ?? null, extra: String(prior?.extra || '') };
      const res = await io.match(r.id, opts, prior);
      if (res.routing?.matcher_unavailable === true) {
        out.still_waiting++;
        if (res.routing?.rematch?.exhausted === true) out.exhausted++;
        continue;
      }
      out.rematched++;
      if (res.matches > 0) out.reached++;
      await io.closeFinding(r.id, 'the matcher answered on re-match attempt ' + ((Number(prior?.attempts) || 0) + 1) + ': ' + res.matches + ' supplier(s) reached');
      await io.told(r.id, res.matches);
    } catch (e) { out.errors.push(r.id + ': ' + String((e as Error)?.message || e)); }
  }
  return out;
}
