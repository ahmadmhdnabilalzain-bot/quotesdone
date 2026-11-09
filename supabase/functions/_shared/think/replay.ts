// think/replay.ts — held questions are reasoned the moment the hold lifts (moved whole from _shared/think.ts).
import { heldFromGate } from '../llm_hold.ts';
import type { Admin, ThinkContext, ThinkDeps, ThinkRequest, ThinkResult } from './types.ts';
import { think } from './engine.ts';
import { heartbeatDeps, MIN_STEP_MS, withDeadline } from './deps.ts';
import { EASY_DUTY_SURFACE, INTERNAL_DUTY_SURFACE } from './routing.ts';

// ── the replay: held questions are reasoned the moment the hold lifts ────────────────────────────
// resilience_ping calls this each tick. fn_reason_held_due claims the oldest held rows (and does
// nothing while the gate refuses); each is re-run through think() and handed to fn_reason_held_resolve,
// which applies the effect the owning surface registered (see the SQL) and records the result.
/** A request as stored: rows queued before audience was required may lack it, and then get the public brief. */
export type StoredThinkRequest = Omit<ThinkRequest, 'context'> & { context?: Partial<ThinkContext> };
export type HeldRow = { id: number; seat: string; surface: string; request: StoredThinkRequest; subject: Record<string, unknown> | null; created_at?: string };
// THE BACKLOG CLEARS IN ABOUT AN HOUR (7 Oct 2026, ledger 1175 lifted the hold). Until then one tick claimed 3 rows, so
// 206 held questions took ~17 hours at the 15-minute tick. Now a tick claims `limit` rows at a time, reasons each claim
// concurrently, and claims again until the claim comes back short, MAX_ROWS are done, or the time budget is spent - so
// the tick stays inside the edge function's wall clock and the spend per tick is bounded by MAX_ROWS answers.
// Only status 'held' rows under 3 tries are claimed (fn_reason_held_due); expired/answered rows are never re-asked, and
// the sweep before it closes what has expired. A STALE answer (question older than STALE_MS) is stored but never sent
// to a person unreviewed: it goes to the owning seat as held_for_review instead of out on the channel.
// 12 Oct 2026 (it_engineer, release operator): measured after #1287 on production, the replay rides the itlater step,
// whose cost rose to ewma 84 s / last 119 s, so the tick plan deferred it on most ticks (5 deferrals in a row) and 6 of
// 32 ticks ended 546 with 10 concurrent think() calls in flight. The held queue fell 253 -> 248 in eight hours.
// A smaller slice that fits every tick drains faster than a large one that rarely runs.
// TWO ROWS AT A TIME, ONE CLAIM A TICK, AND NO MODEL CALL PAST THE BUDGET (it_engineer, 27 Oct 2026). Measured on
// production at 20:30Z: the tick claimed 5 rows (28985-28988, 32248) and reasoned them under one Promise.all. Since
// #1678 every gte-small vector is its own embed_ml invocation, so that was dozens of function-to-function calls in
// about 10 s beside the routine-judgements drain: ai_gateway answered 503 after ~10 s with no execution_id (no worker
// served it), the other fetches threw, and all five rows came back 'model_failed: no reply' - the 12 Oct symptom again.
// Rows are now reasoned at most REPLAY_CLAIM at a time (a claim never asks for more than that), a claim starts only
// while a whole row's measured time (REPLAY_ROW_MS) still fits in the budget, and every model call of the replay is
// cut at the budget's end (withDeadline), so nothing is left in flight when the step returns. Measured per row (13
// rows applied 21-27 Oct, claim to reasoned_at, one or two at a time): 41-80 s for ten, 105/125/162 s for three that
// rode a larger burst; a resilience_ping model call takes p50 24-34 s (ai_cost_log, 3 days), and a row makes two or
// three of them. So budget = row = 90 s: one claim of up to two rows per tick, 8 an hour at the 15-minute tick
// against a held queue of 9. embed_ml takes one text per call (action 'gte'), so the embeddings are not batched.
// prevented by: _shared/think_replay_concurrency.test.ts
export const REPLAY_MAX_ROWS = 20;
export const REPLAY_BUDGET_MS = 90_000;
export const REPLAY_ROW_MS = 90_000;
export const REPLAY_CLAIM = 2;
// The time a caller's own clock keeps after the replay (fn_it_duty_settle, the delivery record): with a `deadline`
// the budget is what is left of it less this reserve, so a replay that starts late claims less, or nothing, and waits
// for the next tick rather than running past its caller (review of #1688: the detached run is raced at 120 s).
export const REPLAY_RESERVE_MS = 25_000;
export const REPLAY_STALE_MS = 24 * 3600_000;
export async function replayHeld(admin: Admin, limit = 3, deps?: ThinkDeps, deliver?: (row: HeldRow, r: ThinkResult) => Promise<unknown>,
  opts: { maxRows?: number; budgetMs?: number; rowMs?: number; staleMs?: number; now?: () => number; deadline?: number } = {}): Promise<unknown> {
  const now = opts.now ?? Date.now;
  const t0 = now();
  const maxRows = opts.maxRows ?? limit;            // a caller that does not opt in keeps the old one-claim behaviour
  const budget = Math.max(0, Math.min(opts.budgetMs ?? REPLAY_BUDGET_MS, opts.deadline === undefined ? Infinity : opts.deadline - t0 - REPLAY_RESERVE_MS));
  const rowMs = opts.rowMs ?? REPLAY_ROW_MS;
  const claimSize = Math.max(1, Math.min(limit, REPLAY_CLAIM));   // the rows reasoned together, never more than REPLAY_CLAIM
  // Every model call of every row ends by the budget: a call with under MIN_STEP_MS left is not started and the row
  // stays held (turn_deadline), so the step never returns over a call still in flight.
  const d = withDeadline(deps ?? heartbeatDeps(admin), t0 + budget, MIN_STEP_MS, now);
  const staleMs = opts.staleMs ?? REPLAY_STALE_MS;
  // The sweep runs on every tick, hold or not (5 Oct 2026): until then it ran inside fn_reason_held_due, which this
  // function never reached while the hold was on, so fixture and stale rows piled up for the day the hold lifts.
  // A failed sweep never stops the replay: it is retried on the next tick, and fn_reason_held_due sweeps again.
  const swept = await d.rpc('fn_reason_held_sweep', {}).then((r) => r?.data ?? r?.error?.message ?? null, (e) => String(e));
  if (heldFromGate(await d.gate().catch(() => null))) return { replayed: 0, reason: 'model_hold', swept };
  const out: unknown[] = [];
  const send = async (row: HeldRow, r: ThinkResult) => {
    let delivery: unknown;
    // fail closed: a row that does not say when it was asked is treated as stale, never sent unreviewed
    const asked = row.created_at ? Date.parse(row.created_at) : NaN;
    const age = Number.isFinite(asked) ? now() - asked : Infinity;
    if (age > staleMs) delivery = { delivered: false, via: 'held_for_review', detail: `stale: asked ${Number.isFinite(age) ? Math.round(age / 3600_000) + ' h ago' : 'at an unknown time'}; the seat reviews before anything reaches a person` };
    else try { delivery = await deliver!(row, r); } catch (err) { delivery = { delivered: false, via: 'error', detail: String((err as Error)?.message || err).slice(0, 200) }; }
    // recording the delivery never aborts the rest of the batch
    await d.rpc('fn_reason_held_delivered', { p_id: row.id, p_delivery: delivery }).then(() => null, () => null);
    return delivery;
  };
  const one = async (row: HeldRow) => {
    // One row's failure never abandons the batch: a throw is resolved as still held, and counted.
    let r: ThinkResult;
    try { r = await think(d, { ...row.request, context: { ...row.request.context } as ThinkContext, queueWhenHeld: false, easy: row.request.easy ?? EASY_DUTY_SURFACE.test(row.surface), internalDuty: INTERNAL_DUTY_SURFACE.test(row.surface) }); }
    catch (err) { r = { status: 'held', answer: '', steps: [], context_used: {}, missing_context: [], sources: [], confidence: 0, reason: 'threw: ' + String((err as Error)?.message || err).slice(0, 200) }; }
    const { data: res, error: e } = await d.rpc('fn_reason_held_resolve', { p_id: row.id, p_result: r });
    // The answer goes back on the channel it came from (_shared/reasoned_delivery.ts) - for this row and for every row
    // that waited on the same question (fn_reason_held_resolve fans one paid answer out to all of them).
    let delivery: unknown = null;
    const fanned = ((res as { fanned?: HeldRow[] } | null)?.fanned ?? []);
    if (!e && r.status === 'answered' && deliver) {
      delivery = await send(row, r);
      for (const f of fanned) await send({ ...f, created_at: f.created_at ?? row.created_at }, r);
    }
    return { id: row.id, status: r.status, effect: (res as { status?: string } | null)?.status ?? null, fanned: fanned.length, delivery, error: e?.message };
  };
  let error: string | undefined;
  // A claim counts a try on every row it returns, so a claim starts only while a whole row's time still fits in the
  // budget: the first against the whole budget (the sweep and gate read before it are not a row's time), each later
  // one against what is left. A budget under one row claims nothing and the rows wait for the next tick.
  if (budget < rowMs) return { replayed: 0, deferred: `budget ${budget} ms is under one row (${rowMs} ms)`, swept };
  while (out.length < maxRows) {
    const spent = now() - t0;
    if (spent >= budget || (out.length > 0 && budget - spent < rowMs)) break;
    const ask = Math.min(claimSize, maxRows - out.length);
    const { data, error: ce } = await d.rpc('fn_reason_held_due', { p_limit: ask });
    if (ce) { error = ce.message; break; }
    // never more than claimSize rows in flight, whatever the claim returned; a claimed row is never dropped unreasoned
    const rows = (data ?? []) as HeldRow[];
    for (let i = 0; i < rows.length; i += claimSize) out.push(...await Promise.all(rows.slice(i, i + claimSize).map(one)));
    if (rows.length < ask) break;                 // the queue is drained (or the claim was short)
  }
  return error && !out.length ? { replayed: 0, error, swept } : { replayed: out.length, rows: out, swept, ...(error ? { error } : {}) };
}
