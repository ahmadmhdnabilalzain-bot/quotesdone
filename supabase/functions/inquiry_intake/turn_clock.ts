// turn_clock — an intake interview turn answers inside the portal's wait, with every model step on one clock.
// Assigned: sales_engineer (the intake interview). 27 Oct 2026.
//
// MEASURED (production, read-only). agent_runs fn:inquiry_intake, 24-27 Oct 2026, 53 turns: p50 11.5 s, p95 98.5 s,
// max 130 s. The portal gives up at 30 s (CustomerPortal.tsx CALL_TIMEOUT_MS), so the slow turns reached the customer
// as an error. ai_cost_log fn inquiry_intake splits the clean single-turn cases (27 Oct 10:40, 11:15, 11:33 UTC):
//   - the interview call itself (inquiry_qualification_conversation, claude-sonnet-5.5): 5.0-7.0 s;
//   - then think() for the exact-spec reading (statedSpecs): a plan (routine_employee_reasoning, gpt-6-luna-pro)
//     of 20.0-33.8 s, and one or two answer passes (customer_communication, gpt-6-luna-pro, ~51k prompt tokens) of
//     38.3-47.4 s each. 88.8 s, 120.4 s and 130.0 s in all.
// Over the 3 days: the plan p50 20.0 s / p95 29.8 s, the answer pass p50 25.3 s / p95 41.9 s. Nothing bounded the turn:
// the main call's fetch had no timeout, think() ran unclocked, and the held reply had its own 40 s.
//
// THE RULE. A turn has ONE clock, TURN_BUDGET_MS from the moment the request arrives. The interview call is given what
// is left; every later model step (the exact-spec reading, the trade reasoning, the held reply) starts only with at
// least MIN_STEP_MS left and is cut at the clock, keeping RESERVE_MS for the save. A step that does not finish fills
// nothing: a spec it would have read is simply asked (the exact-specs-or-held gate in index.ts is unchanged), a held
// reply falls back to the open questions listed by code (slots.ts heldReply). So the clock can only make a turn ASK,
// never let a spec through.
// prevented by: inquiry_intake/turn_clock.test.ts (and _shared/think.ts withDeadline, tested there too)
// MIN_STEP_MS: a model step does not start with less than this left; its answer could not arrive in time.
import { MIN_STEP_MS } from '../_shared/think.ts';
export { MIN_STEP_MS };

/** The whole turn, from the request arriving to the response. The portal waits 30 s; 6 s is left for the edge and network. */
export const TURN_BUDGET_MS = 24_000;
/** Kept back for the save, the QA log and the response after the last model step. */
export const RESERVE_MS = 2_500;

export class TurnClock {
  readonly t0: number;
  readonly laps: Record<string, number> = {};
  constructor(t0 = Date.now(), private readonly budgetMs = TURN_BUDGET_MS, private readonly now: () => number = Date.now) { this.t0 = t0; }
  /** Milliseconds since the request arrived, recorded under `name` (the response's `timing`, agent_runs counts.laps). */
  lap(name: string): number { const ms = this.now() - this.t0; this.laps[name] = ms; return ms; }
  /** The epoch ms by which a model step must be done, keeping `reserve` for what follows it. */
  deadline(reserve = RESERVE_MS): number { return this.t0 + this.budgetMs - reserve; }
  /** Milliseconds a model step may still take. */
  left(reserve = RESERVE_MS): number { return this.deadline(reserve) - this.now(); }
  /** Whether a model step may start now. */
  canStart(reserve = RESERVE_MS, min = MIN_STEP_MS): boolean { return this.left(reserve) >= min; }
}

/** Whether `p` settled within `ms`. The timer is always cleared; `p` is never cancelled (its writes land where they land). */
export async function within(p: Promise<unknown>, ms: number): Promise<boolean> {
  let t: ReturnType<typeof setTimeout> | undefined;
  const timer = new Promise<boolean>((r) => { t = setTimeout(() => r(false), Math.max(0, ms)); });
  try { return await Promise.race([p.then(() => true, () => true), timer]); } finally { clearTimeout(t); }
}

/** A value read once per warm worker and kept `ttlMs`; a read that failed or came back empty is not kept. */
export function keptFor<T>(ttlMs: number, load: () => Promise<T[]>, now: () => number = Date.now): () => Promise<T[]> {
  let kept: { at: number; p: Promise<T[]> } | null = null;
  return () => {
    if (kept && now() - kept.at < ttlMs) return kept.p;
    const p: Promise<T[]> = load().then((v) => { if (!v.length && kept?.p === p) kept = null; return v; },
      () => { if (kept?.p === p) kept = null; return [] as T[]; });
    kept = { at: now(), p };
    return p;
  };
}

/** A turn id from the portal: short, plain, or nothing. */
export function turnIdOf(v: unknown): string | null {
  const s = typeof v === 'string' ? v.trim() : '';
  return /^[A-Za-z0-9_-]{6,64}$/.test(s) ? s : null;
}

/**
 * The customer's message goes into the conversation ONCE, even when the portal retries a turn it stopped waiting for.
 * A retry carries the same turn_id. If the server already recorded that message and answered it (the first attempt
 * landed after the portal gave up), nothing is added: 'landed' tells the caller to return the reply it stored
 * (storedReply), because answering again would read the same words as the answer to the NEXT question. A turn_id that
 * is not the latest message changes nothing ('none'). Otherwise the message is added ('added').
 */
export function placeUserTurn(turns: any[], text: string, turnId: string | null): 'added' | 'landed' | 'none' {
  if (!text) return 'none';
  if (turnId) {
    let lastUser = -1;
    for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'user') { lastUser = i; break; }
    if (lastUser >= 0 && turns[lastUser].turn_id === turnId && turns.slice(lastUser + 1).some((t) => t && t.role === 'assistant')) return 'landed';
    if (turns.some((t) => t && t.role === 'user' && t.turn_id === turnId)) return 'none';
  }
  turns.push(turnId ? { role: 'user', text, turn_id: turnId } : { role: 'user', text });
  return 'added';
}

/** What a landed turn answered, from the row it saved: the reply after the latest message and the state stamped on it. */
export function storedReply(row: { id: string; status?: string | null; category?: string | null; readiness?: number | null; missing?: unknown; brief?: any; turns?: any[] }) {
  const turns = Array.isArray(row.turns) ? row.turns : [];
  let a: any = null;
  for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'assistant') { a = turns[i]; break; }
  const s = (a && a.slots) || {};
  const r = (s.reply && typeof s.reply === 'object') ? s.reply : {};
  const status = String(row.status || s.status || 'needs_info');
  const next = r.next_question && typeof r.next_question === 'object' ? r.next_question : null;
  const remaining = Array.isArray(r.remaining_questions) ? r.remaining_questions : (Array.isArray(row.missing) ? row.missing : []);
  return {
    ok: true, replayed: true, intake_id: row.id, status, category: row.category ?? null,
    assistant_message: String(a?.text || ''), next_question: next,
    questions: next ? [String(next.text || '')] : remaining.slice(0, 4), remaining_questions: status === 'ready' ? [] : remaining,
    missing_keys: Array.isArray(s.missing_keys) ? s.missing_keys : [],
    readiness: r.readiness ?? null, readiness_score: Number(row.readiness) || 0,
    brief: status === 'ready' ? (row.brief ?? null) : null,
  };
}
