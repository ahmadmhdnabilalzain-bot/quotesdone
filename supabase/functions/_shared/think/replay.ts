// think/replay.ts — held questions are reasoned the moment the hold lifts (moved whole from _shared/think.ts).
import { heldFromGate } from '../llm_hold.ts';
import type { Admin, ThinkContext, ThinkDeps, ThinkRequest, ThinkResult } from './types.ts';
import { think } from './engine.ts';
import { heartbeatDeps, MIN_STEP_MS, withDeadline } from './deps.ts';
import { EASY_DUTY_SURFACE, INTERNAL_DUTY_SURFACE } from './routing.ts';
import { audienceOf, INTERNAL_AUDIENCES } from './settled.ts';

// ── the replay: held questions are reasoned the moment the hold lifts ────────────────────────────
// resilience_ping calls this each tick. fn_reason_held_due claims the oldest held rows (and does
// nothing while the gate refuses); each is re-run through think() and handed to fn_reason_held_resolve,
// which applies the effect the owning surface registered (see the SQL) and records the result.
/** A request as stored: rows queued before audience was required may lack it, and then get the public brief. */
export type StoredThinkRequest = Omit<ThinkRequest, 'context'> & { context?: Partial<ThinkContext> };
// attempts and gateway_timeouts come from the claim (fn_reason_held_due, scripts/sql/a_prompt_that_timed_out_twice_is_not_resent.sql):
// the try this claim counted, and how many earlier tries ended at the model gateway's wall. Absent (a claim from before that
// file) reads as none, so the replay behaves exactly as it did.
export type HeldRow = { id: number; seat: string; surface: string; request: StoredThinkRequest; subject: Record<string, unknown> | null; created_at?: string; attempts?: number; gateway_timeouts?: number };
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
// The answer's share of a row (withDeadline answerReserveMs): an answered internal_judgement call on gpt-6-luna-pro takes
// p95 34.7 s, p99 44.0 s (llm_attempt, 2-10 Nov 2026), and llm.ts lets the gateway run 2 s past the call's own time, so
// 40 s fits about 97 in 100 answers and leaves the plan and retrieval 50 s of the 90 s row (answered rows used p90 49 s).
export const REPLAY_ANSWER_RESERVE_MS = 40_000;
// A PROMPT THAT TIMED OUT TWICE IS NOT SENT AGAIN AS IT WAS (it_engineer, 18 Nov 2026). Measured on production
// (ai_cost_log fn resilience_ping, 48 h to 18 Nov 10:20Z, e2e_run_tag null): 53 of the 55 billed failed calls ended at
// the wall with 0 output tokens - the plan (routine_employee_reasoning) at 51.1-51.4 s of the 51.5-51.8 s the caller declared
// (the 90 s budget less the 40 s kept for the answer), the answer (internal_judgement) at 39.3-41.4 s on the CEO's Opus
// (AED 0.22-0.24 a call) and at 89.6 s for it_engineer - and the same prompt_hash failed again on the next tick: 25 billed
// failures over 19 hashes for ceo, 12 over 12 for marketing, 9 over 9 for it_engineer (0 ever answered), 7 over 7 for
// sales_engineer. Most were the planner (26 calls at 51.2-51.3 s, the CEO's 21 of them), whose timeout the run then fell back
// from to a one-step plan and recorded as 'unparseable plan' (engine.ts now keeps the cause). The held rows read
// 'model_failed: no reply' with the answer's step 'gateway_http_502:gateway_deadline', and the
// claim tried each row three times at the same size and the same high effort, so the third try bought what the first two
// had. Now each try's timeout is counted on the row (p_result.gateway_timeouts, returned by the claim), and a row whose
// earlier tries timed out twice is sent ONCE more, lighter, then closed:
//   - an internal row (no customer, supplier or visitor reads it) is asked at medium effort - the effort internal_judgement
//     ran at before the 11 Nov raise, when marketing's answered 143 of 143 with a max of 41.2 s (tunables.ts) - and a
//     decision with no plan of its own skips the planner for the one-step plan a timed-out planner falls back to anyway
//     (engine.ts), so the answer gets the time the plan spent. A 'low' is never asked: the gateway raises it to high on a
//     class that decides (effort_policy.ts effortFor), which would be heavier, not lighter;
//   - a row a customer, supplier or visitor reads is not asked at a different effort (their replies keep theirs) and not
//     re-sent at the same one: it is closed. Its holding notice is unchanged (fn_reason_held_notice_due reads escalated_at,
//     not this row's status);
//   - three timeouts on a row (the lighter try timed out too) is never sent again.
// The 3-try bound does the closing: two timed-out tries leave at least two counted, so the lighter one is the third and
// fn_reason_held_resolve marks it 'failed' if it does not answer. Every close files a finding for the owning seat
// (owner_seat), never silent; the row keeps its result, never lost.
// prevented by: _shared/a_prompt_that_timed_out_twice_is_not_resent.test.ts
export const REPLAY_TIMEOUTS_BEFORE_LIGHT = 2;
/** A model call that ended at a wall: the gateway's deadline, its wall, or our own client timeout. A turn_deadline is a call
 *  the replay never started (withDeadline), so it bought nothing and is not counted. */
export const GATEWAY_TIMEOUT = /gateway_deadline|gateway_wall|timed? ?out|timeout/i;
const NOT_SENT = /^turn_deadline/i;
/** The steps that are a model call. A retrieval step's detail (an embedding that timed out) is not a prompt sent again. */
export const MODEL_STEP_KINDS: ReadonlySet<string> = new Set(['decompose', 'synthesise', 'verify']);
/** Whether a replay result ended at the model's wall: not answered, and a model step that failed on a timeout - the
 *  answer, or the planner whose timeout the run fell back from (engine.ts keeps that cause in the step's detail). */
export function timedOutAtGateway(r: Pick<ThinkResult, 'status' | 'steps'>): boolean {
  if (r.status === 'answered') return false;
  return (r.steps ?? []).some((s) => {
    const d = typeof s.detail === 'string' ? s.detail : '';
    return s.status === 'failed' && MODEL_STEP_KINDS.has(s.kind) && GATEWAY_TIMEOUT.test(d) && !NOT_SENT.test(d);
  });
}
export type ReplayShape = { send: 'as_asked' } | { send: 'lighter'; request: StoredThinkRequest; why: string } | { send: 'not_again'; why: string };
/** How a claimed row is sent: as asked, once lighter after two timeouts, or not again. */
export function replayShape(row: Pick<HeldRow, 'request' | 'gateway_timeouts'>): ReplayShape {
  const prior = Math.max(0, Math.floor(Number(row.gateway_timeouts) || 0));
  if (prior < REPLAY_TIMEOUTS_BEFORE_LIGHT) return { send: 'as_asked' };
  if (prior > REPLAY_TIMEOUTS_BEFORE_LIGHT) return { send: 'not_again', why: `timed out at the model gateway ${prior} times, the lighter try included` };
  const req = row.request;
  if (!INTERNAL_AUDIENCES.has(audienceOf(req.context?.audience))) {
    return { send: 'not_again', why: `timed out at the model gateway ${prior} times; a reply a customer, supplier or visitor reads keeps its effort, so it is not sent again` };
  }
  const skipPlan = !!req.decision && !req.plan;
  const lighterEffort = req.effort !== 'medium' && req.effort !== 'low';
  if (!skipPlan && !lighterEffort) return { send: 'not_again', why: `timed out at the model gateway ${prior} times and nothing lighter is left to ask (effort ${req.effort}, its own plan)` };
  const request: StoredThinkRequest = {
    ...req,
    ...(lighterEffort ? { effort: 'medium' as const } : {}),
    ...(skipPlan ? { plan: { steps: [{ id: 's1', goal: 'answer the question', query: String(req.question ?? '').slice(0, 500), needs_knowledge: true }] } } : {}),
  };
  return { send: 'lighter', request, why: [lighterEffort ? 'effort medium' : null, skipPlan ? 'the one-step plan' : null].filter(Boolean).join(', ') };
}
export async function replayHeld(admin: Admin, limit = 3, deps?: ThinkDeps, deliver?: (row: HeldRow, r: ThinkResult) => Promise<unknown>,
  opts: { maxRows?: number; budgetMs?: number; rowMs?: number; staleMs?: number; now?: () => number; deadline?: number } = {}): Promise<unknown> {
  const now = opts.now ?? Date.now;
  const t0 = now();
  const maxRows = opts.maxRows ?? limit;            // a caller that does not opt in keeps the old one-claim behaviour
  const budget = Math.max(0, Math.min(opts.budgetMs ?? REPLAY_BUDGET_MS, opts.deadline === undefined ? Infinity : opts.deadline - t0 - REPLAY_RESERVE_MS));
  const rowMs = opts.rowMs ?? REPLAY_ROW_MS;
  const claimSize = Math.max(1, Math.min(limit, REPLAY_CLAIM));   // the rows reasoned together, never more than REPLAY_CLAIM
  // Every model call of every row ends by the budget: a call with under MIN_STEP_MS left is not started and the row
  // stays held (turn_deadline), so the step never returns over a call still in flight. The plan and retrieval stop
  // REPLAY_ANSWER_RESERVE_MS before the budget's end, so the answer is never the call left with the scraps.
  const d = withDeadline(deps ?? heartbeatDeps(admin), t0 + budget, MIN_STEP_MS, now, REPLAY_ANSWER_RESERVE_MS);
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
  // A close is said to the owning seat: one finding per surface, its evidence naming the row. Best effort: a finding that
  // fails never costs the row its resolve.
  const closed = async (row: HeldRow, why: string, extra: Record<string, unknown>) => {
    const external = !INTERNAL_AUDIENCES.has(audienceOf(row.request.context?.audience));
    await d.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: 'held_question_timed_out:' + row.surface,
      p_title: `held question ${row.id} (${row.surface}) timed out at the model gateway and is closed, not sent again`,
      p_where: 'held-question replay (_shared/think/replay.ts)', p_blast: external ? 'customer_facing' : 'internal', p_affected: 1,
      p_evidence: { held_id: row.id, seat: row.seat, surface: row.surface, owner_seat: row.seat, attempts: row.attempts ?? null, why, ...extra },
      p_ruled_out: [], p_undetermined: ['whether the question is still needed, and at what size it can be answered'], p_raised_by: row.seat,
    }).then(() => null, () => null);
  };
  const one = async (row: HeldRow) => {
    // One row's failure never abandons the batch: a throw is resolved as still held, and counted.
    const prior = Math.max(0, Math.floor(Number(row.gateway_timeouts) || 0));
    const shape = replayShape(row);
    const ask = shape.send === 'lighter' ? shape.request : row.request;
    let r: ThinkResult;
    if (shape.send === 'not_again') r = { status: 'held', answer: '', steps: [{ id: 'replay', kind: 'hold', goal: 'a prompt that timed out twice is not sent again as it was', status: 'skipped', detail: shape.why }], context_used: {}, missing_context: [], sources: [], confidence: 0, reason: 'not_sent_again: ' + shape.why };
    else try { r = await think(d, { ...ask, context: { ...ask.context } as ThinkContext, queueWhenHeld: false, easy: ask.easy ?? EASY_DUTY_SURFACE.test(row.surface), internalDuty: INTERNAL_DUTY_SURFACE.test(row.surface) }); }
    catch (err) { r = { status: 'held', answer: '', steps: [], context_used: {}, missing_context: [], sources: [], confidence: 0, reason: 'threw: ' + String((err as Error)?.message || err).slice(0, 200) }; }
    // the count rides on the row's result, so the next claim knows it (fn_reason_held_due returns it)
    const timeouts = prior + (shape.send !== 'not_again' && timedOutAtGateway(r) ? 1 : 0);
    const recorded = { ...r, gateway_timeouts: timeouts, ...(shape.send === 'as_asked' ? {} : { replay_shape: shape.send === 'lighter' ? 'lighter: ' + shape.why : 'not_again' }) } as ThinkResult;
    const { data: res, error: e } = await d.rpc('fn_reason_held_resolve', { p_id: row.id, p_result: recorded });
    if (shape.send === 'not_again') await closed(row, shape.why, { gateway_timeouts: timeouts });
    else if (shape.send === 'lighter' && r.status !== 'answered') await closed(row, `the lighter try (${shape.why}) did not answer either: ${String(r.reason ?? r.status).slice(0, 200)}`, { gateway_timeouts: timeouts, lighter: shape.why });
    // The answer goes back on the channel it came from (_shared/reasoned_delivery.ts) - for this row and for every row
    // that waited on the same question (fn_reason_held_resolve fans one paid answer out to all of them).
    let delivery: unknown = null;
    const fanned = ((res as { fanned?: HeldRow[] } | null)?.fanned ?? []);
    if (!e && r.status === 'answered' && deliver) {
      delivery = await send(row, r);
      for (const f of fanned) await send({ ...f, created_at: f.created_at ?? row.created_at }, r);
    }
    return { id: row.id, status: r.status, effect: (res as { status?: string } | null)?.status ?? null, fanned: fanned.length, delivery, error: e?.message, ...(shape.send === 'as_asked' ? {} : { shape: shape.send }) };
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
