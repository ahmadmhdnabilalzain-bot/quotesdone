// A MAIL HELD BY A MODEL ERROR IS READ AGAIN (customer_support, 19 Nov 2026; ledger 1436: no supplier goes unanswered).
// Agent: customer_support held-mail retrier.
//
// MEASURED (production SELECTs, 19 Nov 2026): inbound_messages 2169, a person at HomeBox (lead 853) replying to our supplier
// invitation on 12 Nov 06:30Z, had no answer 7 days later. Its second reading (16 Nov 05:46Z, asked by the support drive) got
// no model answer: ai_cost_log 106269 and 106270, internal_judgement, ok=false after 48 s, the gateway's 502 gateway_deadline.
// supplier_mailbox_reading.ts recorded that as the FINAL reading 'unclear' (mailbox_reply_decision method 'no_model'), held
// "for review" with no retry and no deadline; the drive asks a second reading only once (reread_requested_at), so nothing
// read it again. It is the only row held so on production (mailbox_reply_decision where method='no_model' and reading='unclear': 1).
//
// NOW: a provider failure is not a reading. The mail stays untriaged and is read again by a later run, with backoff
// (RETRY_AFTER_MIN), up to MAX_MODEL_ATTEMPTS readings in all. Only then is it held as 'unclear', saying so, owned by
// customer_support (needs_review); the support drive's clock (fn_customer_support_unanswered_inbound_tick, SLA
// support_first_reply_sla_hours = 24 h from receipt) hands it to the CEO seat if it is still neither answered nor closed.
// The attempts are kept on the row (raw.model_retry), so the count survives the isolate and the selector skips a mail
// whose next attempt is not due yet.
//
// WHAT IS TRANSIENT is the estate's one test of "the model call failed" (_shared/openrouter_down.ts isOpenRouterDown: a 5xx,
// a timeout or deadline, a network error), MINUS a deliberate hold: an open circuit, the founder's or the model hold, no paid
// AI, a credential refusal. A hold is a decision, not a blip, and keeps today's behaviour (held as unclear at once). An empty
// completion is an answer (isOpenRouterDown says so) and is not retried either.
// prevented by: email_triage/model_retry.test.ts
import { isOpenRouterDown } from '../_shared/openrouter_down.ts';

/** Readings in all (the first and three more). At 48 s a deadline, four cost about 3 min of model time over ~65 min. */
export const MAX_MODEL_ATTEMPTS = 4;
/** Minutes to wait after the Nth failed reading before the next (index N-1). */
export const RETRY_AFTER_MIN = [5, 15, 45] as const;
/** The first-reply SLA the support drive holds a held mail to (seat_clock_policy support_first_reply_sla_hours). */
export const SLA_HOURS = 24;

const HOLD = /circuit_open|open-circuit|founder_hold|model_hold|no_paid_ai|credential|forbidden/i;

/** A provider failure worth asking again: 5xx, timeout, gateway_deadline, network. Never a deliberate hold or a 4xx. */
export function isTransientModelError(error: unknown, http?: number | null): boolean {
  const e = String(error ?? '').trim();
  if (!e || HOLD.test(e)) return false;
  return isOpenRouterDown(e, http);
}

export type ModelRetry = { attempts: number; first_at: string; last_at: string; last_error: string; next_at: string | null; exhausted_at?: string; sla_due_at?: string };

/** What the row already carries (raw.model_retry), or null. */
export function retryOf(raw: unknown): ModelRetry | null {
  const r = (raw && typeof raw === 'object' ? (raw as Record<string, unknown>).model_retry : null) as Record<string, unknown> | null;
  if (!r || typeof r !== 'object') return null;
  const attempts = Number(r.attempts);
  return Number.isFinite(attempts) && attempts > 0 ? r as unknown as ModelRetry : null;
}

/** A mail whose next reading is not due yet is left for a later run. */
export function retryNotDue(raw: unknown, now = Date.now()): boolean {
  const r = retryOf(raw);
  if (!r || r.exhausted_at || !r.next_at) return false;
  const t = Date.parse(r.next_at);
  return Number.isFinite(t) && t > now;
}

/**
 * The failed reading counted. `defer` = read again at next_at; otherwise the attempts are spent and the mail is held.
 * `receivedAt` sets the SLA the hold is held to (24 h from receipt, the drive's clock).
 */
export function afterFailure(raw: unknown, error: string, o: { now?: number; receivedAt?: string | null } = {}): { defer: boolean; retry: ModelRetry } {
  const now = o.now ?? Date.now();
  const at = new Date(now).toISOString();
  const prev = retryOf(raw);
  const attempts = (prev?.attempts ?? 0) + 1;
  const base = { attempts, first_at: prev?.first_at ?? at, last_at: at, last_error: String(error).slice(0, 200) };
  if (attempts < MAX_MODEL_ATTEMPTS) {
    const wait = RETRY_AFTER_MIN[Math.min(attempts - 1, RETRY_AFTER_MIN.length - 1)];
    return { defer: true, retry: { ...base, next_at: new Date(now + wait * 60_000).toISOString() } };
  }
  const received = Date.parse(String(o.receivedAt ?? ''));
  const sla = new Date((Number.isFinite(received) ? received : now) + SLA_HOURS * 3_600_000).toISOString();
  return { defer: false, retry: { ...base, next_at: null, exhausted_at: at, sla_due_at: sla } };
}

/** The reason a held mail carries once the attempts are spent. */
export function exhaustedWhy(r: ModelRetry): string {
  return 'the model gateway failed ' + r.attempts + ' readings in a row (' + r.first_at + ' to ' + r.last_at + '; last: ' + r.last_error.slice(0, 100)
    + '), so it is held for customer_support: answered or closed with its reason by ' + (r.sla_due_at ?? 'its SLA') + ', else the CEO seat is told';
}
