// resilience_ping ticks owned by the platform seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { embedLine } from '../../_shared/gte_embed.ts';
import { notReached } from '../../_shared/not_reached.ts';
import { anotherRound, ARCHIVE_HARD_MS, isolateOffsets, type SliceOut } from '../archive_rounds.ts';
import { heartbeatDeps, replayHeld, REPLAY_BUDGET_MS, REPLAY_CLAIM, REPLAY_MAX_ROWS } from '../../_shared/think.ts';
import { drain as drainRoutineJudgements } from '../../_shared/routine_judgements.ts';
import { distilLessons } from '../../_shared/learning_loop.ts';
import { deliverReasoned, liveDeliveryIO } from '../../_shared/reasoned_delivery.ts';
import { DETACHED_MS, FN, GATEWAY, admin, sec } from '../shared.ts';

// DRAIN THE OUTBOX EVERY TICK, NOT ONLY DURING AN OUTAGE.
//
// 9 September 2026. Until today the ONLY call to send_outbox in this file sat inside the
// scheduler-is-down branch, below an `if (healthy) return`. So on a healthy estate this endpoint —
// the one thing that actually runs every fifteen minutes — never drained the mail queue, and a
// notification left the building only if whatever created it pushed it itself. Every path that
// wrote a row and trusted "the outbox will send it" was wrong, and silently: the row sits at
// status 'pending' with no error, which reads as queued rather than as stuck.
//
// FOUND BY MEASUREMENT, not by reading. The IT engineer's two [RESOLVED] close notices (21252,
// 21253) were written at 08:00:40 and were still 'pending' at 08:35 with send_outbox last having
// run at 07:25:45 — 70 minutes earlier — while resilience_ping itself had ticked at 07:30, 07:45,
// 08:00 and 08:15. Four ticks passed over a queue they were not looking at. Mail that DOES go out
// fast (avg 1.7 min today) goes out because its creator pushed it, which is exactly what disguises
// this: the queue looks healthy right up until something queues without pushing.
//
// WHY HERE AND NOT IN EVERY CALLER. Making each writer push its own row is the same fix repeated at
// N call sites, and the N+1th will forget — this one did. The outbox is the shared choke point and
// the tick is the thing with a heartbeat, so the drain belongs at their intersection.
//
// BEST EFFORT, DELIBERATELY. A failed flush must not change what this endpoint reports about the
// scheduler; the result is returned in the body so a stuck flush is visible rather than assumed.
//
// ── AND IT CALLS UNCONDITIONALLY, WHICH IS THE SECOND HALF OF THIS FIX (15:20 UTC, same day) ──
//
// The first version skipped the call when nothing was pending — an obvious saving, and wrong. The
// run log IS the heartbeat: fn_it_detect's run_silent detector learns each subject's cadence from
// agent_runs, so a send_outbox that runs only when there is mail has no cadence, and an empty
// queue becomes indistinguishable from a dead sender.
//
// It produced a self-feeding alarm within four hours. The founder got three emails:
//   13:00  [HIGH]     send_outbox has not run for 135 minutes; it normally runs every 30 minutes
//   13:15  [RESOLVED] the same finding
//   15:15  [HIGH]     send_outbox has not run for 120 minutes
// and the loop is visible in the run log: quiet queue -> no run -> detector fires -> the ALERT
// itself queues a notification -> the next tick finds something pending -> send_outbox runs ->
// the finding resolves -> the queue goes quiet -> it fires again. Every couple of hours, for ever,
// with nothing wrong. The only thing keeping the sender alive was the alarm about the sender.
//
// So the call is made every tick, mail or none. A no-op flush is one edge invocation that runs a
// SELECT and returns — 96 a day, sending nothing and consuming none of the daily send cap — and in
// exchange `send_outbox has not run` becomes a sentence that is only true when something IS broken.
// A heartbeat that beats only under load is not a heartbeat.
// FOUR SWEEPS AT ONCE (it_engineer, 6 Oct 2026). One sweep of 4 a beat is 16 PDFs an hour; on 5 Oct
// the supplier invitation run sent 106 mails at 18:38 UTC and 27 messages were still without a PDF
// past the 2-hour line every_conversation_is_kept checks. A sweep cannot take more (5 is the
// renderer's per-worker ceiling), so four run in parallel, each in its own worker, over disjoint
// slices of the oldest-first list: 64 an hour for the same wall time. An empty slice is one SELECT.
const ARCHIVE_SWEEPS = 4, ARCHIVE_BATCH = 4;
export async function archiveTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    // A sweep is idempotent (oldest-first, recorded by upsert), so one the platform refused before any worker ran it
    // is asked once more (2 Nov 2026: 7 conversation_archive 503s in a day, each ~10 s with no execution_id and
    // x-served-by base/server - the worker never started). _shared/not_reached.ts decides what "refused" means.
    const signal = AbortSignal.timeout(ARCHIVE_HARD_MS);   // one clock for every call of every round
    const one = async (offset: number, limit = ARCHIVE_BATCH): Promise<SliceOut & { ok?: boolean; error?: string }> => {
      try {
        const ask = () => fetch(FN + '/conversation_archive', {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
          body: JSON.stringify({ __secret: secret, action: 'sweep', limit, offset }), signal: signal,
        });
        let r = await ask();
        if (notReached(r)) { await r.body?.cancel(); r = await ask(); }
        return { offset, status: r.status, result: await r.json().catch(() => null) };
      } catch (e) { return { offset, ok: false, error: String((e as Error)?.message || e) }; }
    };
    // ROUNDS UNTIL THE BACKLOG IS CLEAR, AND A DEAD SLICE RE-RUN ONE MESSAGE PER WORKER (archive_rounds.ts).
    const t0 = Date.now(); const rounds: unknown[] = []; let sweeps: SliceOut[] = [];
    for (let round = 0; ; round++) {
      sweeps = await Promise.all(Array.from({ length: ARCHIVE_SWEEPS }, (_, i) => one(i * ARCHIVE_BATCH)));
      const iso = isolateOffsets(sweeps, ARCHIVE_BATCH);
      const isolated = iso.length ? await Promise.all(iso.map((o) => one(o, 1))) : [];
      rounds.push({ sweeps, isolated });
      if (!anotherRound(sweeps, round, Date.now() - t0)) break;
    }
    return { status: sweeps[0]?.status, result: sweeps[0]?.result, rounds: rounds.length, detail: rounds };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ORG_TASK QUEUE GETS A CONSUMER (18 Sep 2026). Measured that morning: public.org_tasks held 16
// rows at status='assigned', every one with last_run_at IS NULL and attempts = 0, the oldest 9 days
// old, carrying real unanswered customer questions (two of them in Arabic), booked expenses and two
// "reached no suppliers" signals. 46 routines mention the table and not one selected 'assigned' to
// execute it: everything wrote, nothing read.
//
// fn_org_task_consume_tick routes each class to the handler that already exists, stamps last_run_at
// and attempts on every attempt, backs off 15 minutes doubling per attempt, and raises ONE
// deduplicated finding per class through fn_it_duty_settle. It is deliberately placed BEFORE the
// 'it' step for the same reason every detector is: itEngineerAlertTick reads the finding ledger, so
// running it after would deliver the previous tick's picture.
//
// p_limit is 4, not the whole queue. Measured against production in a rolled-back transaction:
// all 16 rows take 575 ms under `set local statement_timeout = '8s'`, so 4 is far inside both that
// and the tick's own 110 s deadline, and it leaves the drains untouched on a day the queue is long.
export async function orgTaskTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_org_task_consume_tick', { p_limit: 4 });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// EVERY SEAT DUTY ON ITS OWN CLOCK (23 Sep 2026, it_engineer; founder_instruction 898). public.seat_duty holds each
// seat's registered duties with their interval; fn_seat_duties_tick runs the due ones, each in its own
// sub-transaction, and files a finding for any duty that is overdue or failing
// (every_seat_duty_has_an_owner_a_clock_and_a_check.sql). Duties queue mail, so it runs before the outbox drain.
export async function seatDutiesTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_seat_duties_tick', { p_limit: 8 });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// CUSTOMER SUPPORT'S DUTY UPDATES ARE THE MODEL'S (27 Oct 2026, customer_support; founder_instruction 1339: "the
// engineer and customer support never replies without llm unless the server of open router is down"). The complaint
// update and the incident holding/resolved notices are recorded as owed by their SQL duties; this writes them with the
// model and sends the recorded draft only on an OpenRouter outage (_shared/duty_voice.ts). Three voice groups a run.
// THE HELD REPLAY, IN ITS OWN DETACHED RUN (it_engineer, 27 Oct 2026; review of #1688). Kicked by itlater's
// reasoning_held step. The run is raced at DETACHED_MS, so replayHeld is handed that deadline and keeps
// REPLAY_RESERVE_MS of it for the settle: a run that starts late claims nothing and the rows wait for the next tick.
// At most REPLAY_CLAIM rows are in think() at once and no model call outlives the budget (_shared/think.ts).
// prevented by: _shared/think_replay_concurrency.test.ts, resilience_ping/held_replay_runs_detached.test.ts
export async function heldReplayTick(): Promise<unknown> {
  const deadline = Date.now() + DETACHED_MS;
  return await replayHeld(admin, REPLAY_CLAIM, heartbeatDeps(admin), (row, r) => deliverReasoned(row, r, liveDeliveryIO(admin)),
    { maxRows: REPLAY_MAX_ROWS, budgetMs: REPLAY_BUDGET_MS, deadline });
}

// THE ROUTINE JUDGEMENTS, IN THEIR OWN DETACHED RUN (it_engineer, 27 Oct 2026). Kicked by itlater's routine_judgements
// step. Handed this run's deadline, so a claim starts only while a whole judgement fits and no model call outlives it
// (_shared/routine_judgements.ts drain, JUDGE_ROW_MS / JUDGE_RESERVE_MS). heartbeatDeps: gte-small runs in embed_ml.
// prevented by: _shared/routine_judgements_keep_a_deadline.test.ts, resilience_ping/held_replay_runs_detached.test.ts
export async function routineJudgementsTick(): Promise<unknown> {
  const deadline = Date.now() + DETACHED_MS;
  return await drainRoutineJudgements(heartbeatDeps(admin), 5, null, { deadline });
}

export async function outboxTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_outbox', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 20 }), signal: AbortSignal.timeout(20000),
    });
    return { flushed: true, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE EMBEDDING BACKFILL HANGS HERE, AND FOR THE SAME REASON AS THE DROPBOX BACKUP.
// kb_chunks holds 2,686,026 rows and 166,093 embeddings — 6.2%. The backfill that was closing that
// gap at a measured 33.7 rows/minute died on 7 Sep 2026 at 17:51 UTC when pg_cron was emptied on the
// founder's instruction (four jobs: kb_embed_backfill, _boost, _priority_kinds, _ops_knowledge), and
// its worker — supabase/functions/kb_embed — was deleted the next morning by commit 182308b with the
// other 137. Nothing has embedded a row since. Re-registering pg_cron would rebuild machinery he
// removed, so the schedule lives here with every other orphaned tick.
//
// The work itself is entirely inside Postgres and needs NO edge function of its own:
// fn_kb_embed_tick harvests whatever the previous tick's pg_net requests returned, then dispatches
// the next batch — one net.http_post per chunk to ai_gateway {action:'embed'}, which carries the
// FREE in-region gte-small session and short-circuits before routing, budget and the OpenRouter
// hold. So this tick is a single RPC and adds no wall-clock risk to the heartbeat: the HTTP work
// happens asynchronously in pg_net's background worker, not in this invocation.
//
// 400 per tick x 96 ticks a day = ~38,400 rows/day, which drains the 2.52M backlog in ~66 days.
// That is slower than the 33.7/min the 6-second cron achieved, because a 15-minute heartbeat is a
// far coarser clock; raise the batch if pg_net keeps up. Dispatch is ordered by kb_embed_priority,
// so the fit-out trades the marketplace actually quotes embed first and the excluded F&B categories
// embed last — the old job was oldest-first and was pointed at Eurocode 2 concrete bearings.
// THE KNOWLEDGE BACKFILL DOES NOT LIVE HERE, AND THE REASON IS MEASURED.
// A kbEmbedTick was added here and removed the same hour. PostgREST runs RPC as `authenticator`,
// which carries statement_timeout=8s, and fn_kb_embed_dispatch places one net.http_post per chunk
// at ~337ms. Fifty rows took 16.9s and the tick returned "canceling statement due to statement
// timeout" every time. Inside 8s it can place ~23 rows: 96 ticks a day is 2,208 rows, and the
// 2.5M backlog would take over three years. A tick that always fails is not a scheduler, it is a
// recurring error the IT engineer would have to learn to ignore.
// It runs from .github/workflows/kb-embed-backfill.yml instead, which can hold a connection for
// half an hour. Measured there: 401.6 rows/min, 0 failures.

// THE REFUND LADDER HAD NO SCHEDULER. Measured 14 Sep 2026: nothing called fn_refund_ladder_sweep --
// pg_cron went on 7 Sep and no edge function picked it up -- so no day-3 chase and no day-5 final call
// had run since. One RPC: the sales engineer's ladder steps, customer_support's watch for replies, and
// the CEO's review loop (overdue tasks, held charges). The findings stay in the database; this
// endpoint is public, so only counts come back.
// THE CASE MEMORY'S EMBED QUEUE (23 Sep 2026, it_engineer). seat_case_memory rows whose situation
// changed carry no vector until this tick gives them one: claimed with a lease (fn_case_embed_claim),
// embedded HERE with the in-runtime gte-small session — free, in-region, not OpenRouter, no pg_net —
// and written back only if the text is still the one embedded (fn_case_embed_write). Eight per tick
// keeps the CPU bounded (an edge function's CPU cap is not bounded by its deadline); a backlog is
// drained by scripts/kb/embed_seat_case_memory.mjs.
export async function caseMemoryEmbedTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_case_embed_claim', { p_limit: 8 });
    if (error) return { ok: false, error: error.message };
    let embedded = 0, failed = 0;
    for (const row of (data || []) as Array<{ id: number; text: string; hash: string }>) {
      const v = await embedLine(row.text);
      if (!v) { failed++; continue; }
      const { data: ok } = await admin.rpc('fn_case_embed_write', { p_id: row.id, p_embedding: '[' + v.join(',') + ']', p_hash: row.hash });
      if (ok === true) embedded++;
    }
    // A claim that could not embed anything is a failure, never a quiet zero.
    return { ok: failed === 0 || embedded > 0, claimed: (data || []).length, embedded, failed };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MULTILINGUAL SPACE'S TRICKLE (23 Sep 2026, it_engineer). knowledge_vector_ml rows that are new or whose
// text changed are embedded by the embed_ml function (action 'tick'), not here: the model loads only in that
// function's workers. Two rows a tick (ML_TICK_MAX, measured 9 Nov 2026: four died 546 in 22 of ~46 ticks); the backlog is drained by
// .github/workflows/ml-embed-backfill.yml. The gate and the daily cap are fn_ml_embed_claim's.
export async function mlEmbedTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_ai');
    if (!secret) return { ok: false, error: 'cred_fn_ai is not in app_secrets' };
    const r = await fetch(FN + '/embed_ml', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, fn: 'resilience_ping', action: 'tick', limit: 2 }), signal: AbortSignal.timeout(50000),
    });
    const j = await r.json().catch(() => null);
    return { ok: r.ok, status: r.status, result: j };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
// THE LEARNING LOOP (23 Sep 2026, it_engineer; scripts/sql/every_judgement_learns_from_its_outcome.sql).
// Daily: per-seat accuracy against real outcomes into seat_learning_daily (a fall opens a finding).
// Weekly: cases with outcomes, grouped by meaning, distilled into cross-family-verified lessons
// (_shared/learning_loop.ts); held under the model hold, never written from words.
export async function learningMeasureTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_seat_learning_measure', {});
    return error ? { ok: false, error: error.message } : data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
// Hourly, no model: embed + group in SQL. Weekly (learningDistil): reason only what crossed the threshold.
// Both on heartbeatDeps (27 Oct 2026, it_engineer): each unembedded finding (up to 8 a tick) is embedded in embed_ml,
// never in this worker, whose 2 s CPU cap killed the held replay (_shared/think.ts, above defaultDeps).
export async function learningGroupTick(): Promise<unknown> {
  try { return await distilLessons(admin, heartbeatDeps(admin), 2, { reason: false }); } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
export async function learningDistilTick(): Promise<unknown> {
  try { return await distilLessons(admin, heartbeatDeps(admin), 2, { reason: true }); } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
