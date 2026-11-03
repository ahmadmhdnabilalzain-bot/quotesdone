// _shared/spend_ceiling.ts — the daily ceiling on model spend that no customer, supplier or visitor ever meets
// (it_engineer, 3 Nov 2026; the founder after the top-up: "i cant risk suppliers going to the portal and registering
// and we lose them. just make sure we dont waste money in a stupid way").
//
// MEASURED (ai_cost_log, 7 days to 3 Nov 13:16 UTC; OpenRouter billed USD 141.20): nearly all of it was our own tests,
// and the internal duties (CEO knowledge refresh on Opus, it_engineer postmortems, knowledge checks) ran on top with no
// bound at all. Two classes of spend are counted against a daily ceiling (it_threshold rows, read by
// public.fn_ai_spend_ceiling, scripts/sql/the_non_customer_model_spend_stops_at_a_daily_ceiling.sql):
//   'test'     - a request that carries a PROVEN sandbox run tag (e2e_run.ts). Only the harness can prove one.
//   'internal' - a request its internal caller DECLARED as an internal duty (think.ts defaultDeps: an internal-audience
//                question asked by a scheduled duty function, INTERNAL_DUTY_FNS).
// Everything else is not counted and never refused. The class is OPT-IN by construction: a request that names neither
// is a customer's, a supplier's or a visitor's, whatever function it came from — so a held customer reply replayed by
// resilience_ping, a supplier's email answered by email_triage, or a portal turn can never be skipped by a ceiling.
// prevented by: _shared/spend_ceiling.test.ts

export type SpendClass = 'test' | 'internal';

/** The functions whose INTERNAL-audience questions are internal duties: the heartbeat that replays the seats' own
 *  queues, the marketing seat's scheduled work, and the seat exams. email_triage is deliberately absent: it answers
 *  real mail from real suppliers and customers. */
export const INTERNAL_DUTY_FNS: ReadonlySet<string> = new Set(['resilience_ping', 'marketing', 'knowledge_exam']);

/** The marker written into ai_cost_log.model_selected_because, which the database sums for the internal ceiling. */
export const INTERNAL_MARKER = ' | spend_class=internal';

/** Which ceiling a request counts against, or null for traffic that is never counted and never refused. */
export function spendClassOf(runTag: string | null | undefined, declared: unknown): SpendClass | null {
  if (runTag) return 'test';
  return declared === 'internal' ? 'internal' : null;
}

/** The database's answer, read fail-OPEN: a ceiling is a cost guard on our own traffic, so a check that cannot answer
 *  lets the call through (and says so) rather than stopping a duty. Only an explicit allowed:false refuses. */
export function ceilingVerdict(data: unknown, err: unknown): { allowed: boolean; reason: string } {
  if (err || !data || typeof data !== 'object') return { allowed: true, reason: 'ceiling check unavailable: ' + String((err as { message?: string })?.message ?? err ?? 'no answer').slice(0, 120) };
  const d = data as { allowed?: unknown; spent_usd?: unknown; ceiling_usd?: unknown; class?: unknown };
  if (d.allowed !== false) return { allowed: true, reason: '' };
  return { allowed: false, reason: `the ${String(d.class ?? 'non-customer')} model spend today is USD ${Number(d.spent_usd ?? 0).toFixed(2)}, at its daily ceiling of USD ${Number(d.ceiling_usd ?? 0).toFixed(2)} (it_threshold)` };
}
