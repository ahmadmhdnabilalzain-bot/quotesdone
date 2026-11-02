// resilience_ping — the EXTERNAL watchdog target that survives a total pg_cron outage.
// An external scheduler (GitHub Action / uptime service) hits this every ~15min. Because it is an
// HTTP-invoked edge function, it keeps working even if the Supabase pg_cron scheduler has stopped.
// If the previous heartbeat is over 45 minutes old (fn_cron_liveness), it pages the founder through
// fn_notify_founder (kind platform_down, one delivery a day) and drains the outbox so the page leaves now.
// AUTHENTICATED SINCE 6 OCT 2026 (pre-launch security pass, M2). It used to be public and secretless,
// so ANY caller could run the whole sweep: the outbox and WhatsApp drains, execute_refunds, the
// sanctions sweep and the steps that call a model, as often as it liked. Now an unauthenticated call
// gets a liveness answer and nothing runs; the sweep runs only for the service key (the Vercel cron
// route src/app/api/resilience-ping, and the GitHub daily cross-check, which reads the key through the
// management API) or an internal credential in x-qd-internal (requireInternal). Unauthenticated calls
// are rate limited per IP. See tickCaller() below.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { embedLine } from '../_shared/gte_embed.ts';
import { carriedFailures, detachedItems, type Failure, failureOf, httpHopError, runSteps, type Step, type StepClock, stepClock, type StepState, stepRows } from './steps.ts';
import { takeDutyReadings } from '../_shared/it_duty_readings.ts';
import { takeScheduledReadings } from '../_shared/it_scheduled_readings.ts';
import { takeProviderReadings } from '../_shared/it_provider_readings.ts';
import { runPostmasterStep, takePostmasterReading } from '../_shared/it_postmaster_readings.ts';
import { takeUsageReadings, verifyRevisions } from '../_shared/it_duty_readings.ts';
import { runRestoreTable } from '../_shared/it_restore_drill.ts';
import { rotateAndSettle } from '../_shared/it_rotate_by_api.ts';
import { PAUSED, pausedDuties } from '../_shared/duty_pause.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { notReached } from '../_shared/not_reached.ts';
import { integrationItems } from '../_shared/integration_watch.ts';
import { placementTick } from '../_shared/inbox_placement.ts';
import { pollReplyInbox, pollTenantMailboxes, PROOF_LABEL, type SenderKind } from '../_shared/m365_reply_inbox.ts';
import { launchPathAction, launchPathItem, probeLaunchPath } from '../_shared/launch_path.ts';
import { advanceOpenDeliberations } from '../_shared/seat_deliberation.ts';
import { heartbeatDeps, replayHeld, REPLAY_BUDGET_MS, REPLAY_CLAIM, REPLAY_MAX_ROWS } from '../_shared/think.ts';
import { drain as drainRoutineJudgements } from '../_shared/routine_judgements.ts';
import { distilLessons } from '../_shared/learning_loop.ts';
import { deliverReasoned, liveDeliveryIO, sendHeldNotices } from '../_shared/reasoned_delivery.ts';
import { customerReplyGate } from '../_shared/ai_reply.ts';
import { envCoverage as vercelEnvCoverage, snapshot as vercelSnapshot } from '../_shared/vercel_snapshot.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
async function sec(k: string): Promise<string> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// A SEAT DEPLOYED WITH verify_jwt ON IS REFUSED AT THE PLATFORM GATEWAY BEFORE ITS OWN CODE RUNS, unless a
// signed JWT travels with the call. Measured 15 Sep 2026: accountant is verify_jwt=true, and in 24 hours the
// gateway answered 151 calls to it with HTTP 401 — the refund and duties ticks, which sent no Authorization.
// So no accountant duty run had ever been recorded. The service key only opens the gateway; inside, the
// seat still decides the caller from __secret (whoami in accountant/index.ts), as sales_engineer does.
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GATEWAY = { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY };

// THE CEO END-OF-DAY DIGEST HANGS HERE, AND NOT ON pg_cron.
// cron.job holds ONE row (wa_flush, active=false). 234 jobs were deleted on the founder's 7 Sep
// instruction and 110 cron.schedule statements were stripped from 66 repo files, so a pg_cron job
// registered for the digest would simply never fire — and reactivating pg_cron to make it fire
// would restart machinery he removed. This path, by contrast, is demonstrably alive: send_outbox
// has run 52 times down it since the crons died.
// All the timezone and once-per-day logic lives in fn_ceo_daily_digest_tick, because Postgres knows
// what Asia/Dubai means and a cron string does not. The tick is idempotent, so calling it every 15
// minutes is correct: it returns fired:false until the configured local time and then generates
// exactly one report for that local date. A failure here is logged and swallowed — the digest is
// informational and must never take the watchdog down with it.
// 21 Sep 2026 (instruction 587): a day with new customers carries their names and mobiles AS A PDF.
// Postgres cannot draw one, so the tick hands back pdf_blocks, this renders them on the template
// (pdf_native) and fn_ceo_daily_digest_attach_pdf sends the brief with the file. A render failure is
// passed back as p_error and the brief waits for the next tick -- never sent without its document.
async function digestTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_daily_digest_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    let path: string | null = null, err: string | null = null;
    try {
      const r = await fetch(FN + '/pdf_native', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({
          __secret: await sec('cred_fn_resilience_ping'), title: t.pdf_title, blocks: t.pdf_blocks,
          bucket: 'agent-docs', folder: 'ceo/daily_brief',
          name: String(t.report_key || 'daily_brief').replace(/[^\w.-]+/g, '_') + '_customers',
          options: { letterhead: true, strict_glyphs: true },
        }), signal: AbortSignal.timeout(55000),
      });
      const j = await r.json().catch(() => null);
      if (r.ok && j?.ok && j?.path) path = j.path;
      else err = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
    } catch (e) { err = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
    const { data: att, error: aerr } = await admin.rpc('fn_ceo_daily_digest_attach_pdf', {
      p_id: t.id, p_bucket: 'agent-docs', p_path: path, p_error: err,
    });
    if (aerr) return { ...t, pdf_blocks: undefined, ok: false, error: 'attach: ' + aerr.message };
    return { ...t, pdf_blocks: undefined, delivery: att, ...(err ? { ok: false, error: err } : {}) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// SUPPORT'S RATING REQUEST HANGS HERE FOR THE SAME REASON THE DIGEST DOES.
// The founder, 9 Sep 2026: "support should send an email after 3 weeks from the reveal date."
// fn_support_request_ratings_due is idempotent on notifications_rating_request_uidx, so calling it
// every 15 minutes enqueues each reveal's ask exactly once and returns asked:0 the rest of the time.
// Swallowed the same way: a rating survey must never take the watchdog down.
async function ratingTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_support_request_ratings_due');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

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
async function archiveTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    // A sweep is idempotent (oldest-first, recorded by upsert), so one the platform refused before any worker ran it
    // is asked once more (2 Nov 2026: 7 conversation_archive 503s in a day, each ~10 s with no execution_id and
    // x-served-by base/server - the worker never started). _shared/not_reached.ts decides what "refused" means.
    const one = async (offset: number) => {
      try {
        const signal = AbortSignal.timeout(50000);
        const ask = () => fetch(FN + '/conversation_archive', {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
          body: JSON.stringify({ __secret: secret, action: 'sweep', limit: ARCHIVE_BATCH, offset }), signal: signal,
        });
        let r = await ask();
        if (notReached(r)) { await r.body?.cancel(); r = await ask(); }
        return { offset, status: r.status, result: await r.json().catch(() => null) };
      } catch (e) { return { offset, ok: false, error: String((e as Error)?.message || e) }; }
    };
    const sweeps = await Promise.all(Array.from({ length: ARCHIVE_SWEEPS }, (_, i) => one(i * ARCHIVE_BATCH)));
    return { status: (sweeps[0] as { status?: number }).status, result: (sweeps[0] as { result?: unknown }).result, sweeps };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// NO SUPPLIER QUOTED THE EXACT SPEC (founder_instruction #321). Once a pass, sales_engineer checks
// the inquiries whose quote window closed (or whose invited suppliers all quoted), opens an offer
// where no eligible quote matches a mandatory requested value, and sends the due reminders and
// lapses through customer_support. The loop's state and timing live in Postgres
// (fn_spec_offer_candidates / fn_spec_offer_due), so calling it every pass is correct. sales_engineer
// is deployed with verify_jwt on, so the service key goes to the gateway; __secret decides the caller.
async function specOfferTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const r = await fetch(FN + '/sales_engineer', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}`, apikey: key },
      body: JSON.stringify({ __secret: secret, action: 'spec_offer_sweep', limit: 20 }), signal: AbortSignal.timeout(55000),
    });
    return { status: r.status, result: await r.json().catch(() => null) };
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
async function orgTaskTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_org_task_consume_tick', { p_limit: 4 });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE SALES ENGINEER'S DAILY SUPPLIER OUTREACH LEFT THIS TICK ON 28 OCT 2026 (sales_engineer). It ran here as the step
// `supplierOutreach` from 21 Sep, through PostgREST, where the authenticator's statement_timeout is 8 s. The held path
// fits; an open day does not (measured 28 Oct: enqueue_supplier_invites alone took 13.4 s), so on the first open day
// every beat from 09:16 Dubai was cancelled and nothing was invited. fn_sales_engineer_supplier_outreach_tick is now the
// seat duty sales_engineer.supplier_outreach on its own 60 s pg_cron job
// (the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql). Do not bring it back here.

// A BOUNCE REPORT IS PROVEN TO ARRIVE EVERY DAY (21 Sep 2026, customer_support). Before the supplier
// campaign the last bounce resend_webhook had recorded was 15 Aug, and nothing could tell "no bounces"
// from "reports stopped arriving" -- the campaign's 5% brake reads zero either way. Once a day, while real
// mail is going out, this queues one mail to Resend's bounce test sink (the outbox drain later in the same
// tick sends it) and judges the previous one: silence 30 minutes after sending is the IT finding
// delivery_feedback:bounce_reports_silent (a_bounce_report_is_proven_to_arrive_every_day_or_it_is_a_finding.sql).
async function deliveryCanaryTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_delivery_feedback_canary_tick');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE SEAT CLOCKS (22 Sep 2026, ceo; founder instruction 583). Complaint deadlines, requests short of
// 3 quotes, the 7-day reveal outcome check and time to first support reply, each on its owning seat
// (complaints_quotes_reveals_and_support_replies_each_run_on_a_clock.sql). It queues mail, so it must
// run before the outbox drain, which is place=last.
async function seatClocksTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_seat_clocks_tick');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// EVERY SEAT DUTY ON ITS OWN CLOCK (23 Sep 2026, it_engineer; founder_instruction 898). public.seat_duty holds each
// seat's registered duties with their interval; fn_seat_duties_tick runs the due ones, each in its own
// sub-transaction, and files a finding for any duty that is overdue or failing
// (every_seat_duty_has_an_owner_a_clock_and_a_check.sql). Duties queue mail, so it runs before the outbox drain.
async function seatDutiesTick(): Promise<unknown> {
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
async function heldReplayTick(): Promise<unknown> {
  const deadline = Date.now() + DETACHED_MS;
  return await replayHeld(admin, REPLAY_CLAIM, heartbeatDeps(admin), (row, r) => deliverReasoned(row, r, liveDeliveryIO(admin)),
    { maxRows: REPLAY_MAX_ROWS, budgetMs: REPLAY_BUDGET_MS, deadline });
}

// THE ROUTINE JUDGEMENTS, IN THEIR OWN DETACHED RUN (it_engineer, 27 Oct 2026). Kicked by itlater's routine_judgements
// step. Handed this run's deadline, so a claim starts only while a whole judgement fits and no model call outlives it
// (_shared/routine_judgements.ts drain, JUDGE_ROW_MS / JUDGE_RESERVE_MS). heartbeatDeps: gte-small runs in embed_ml.
// prevented by: _shared/routine_judgements_keep_a_deadline.test.ts, resilience_ping/held_replay_runs_detached.test.ts
async function routineJudgementsTick(): Promise<unknown> {
  const deadline = Date.now() + DETACHED_MS;
  return await drainRoutineJudgements(heartbeatDeps(admin), 5, null, { deadline });
}

async function supportVoiceTick(): Promise<unknown> {
  const { writeOwedDutyMessages, liveVoiceIO } = await import('../_shared/duty_voice.ts');
  // heartbeatDeps: any embedding this step ever asks for runs in embed_ml, never in this worker (2 s CPU cap, #1678)
  return await writeOwedDutyMessages(liveVoiceIO(admin, heartbeatDeps(admin)), 3);
}

async function outboxTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_outbox', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 20 }), signal: AbortSignal.timeout(20000),
    });
    return { flushed: true, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE DROPBOX BACKUP HANGS HERE FOR THE THIRD TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: the sales engineer "is responsible about the organized folders back up in
// dropbox". A daily backup needs a schedule, and pg_cron is not one any more — cron.job holds a
// single inactive row. So the daily-ness lives in Postgres, where Asia/Dubai is a real timezone:
// fn_dropbox_backup_due returns due:true at most once per local day, plus whenever a previous sweep
// left rows in the queue, so a backlog drains instead of waiting for tomorrow.
// dropbox_backup itself is idempotent — fn_enqueue_doc_backups is ON CONFLICT DO NOTHING and only
// pending/error rows are uploaded — so a duplicate call costs one wasted invocation, never a
// duplicate file. Swallowed like the other two: a backup must never take the watchdog down.
// THE VAT THRESHOLD, WATCHED ON THE ONLY CLOCK THIS COMPANY HAS.
// The founder, 9 Sep 2026: "the threshold, which is the three hundred seventy five, that is when he
// notifies the CEO that we are supposed to register over that." A routine that decides a tax
// obligation and is never called decides nothing, so it hangs here beside the other seat ticks.
// fn_accountant_vat_threshold_check is idempotent by band and month: it files at most one report
// per band per month, so running it every fifteen minutes costs a SELECT and nothing else.
// Swallowed like its neighbours — a tax watch must never take the watchdog down.
// THE CEO'S WEEKLY WHOLE-COMPANY REPORT, ON THE SAME HEARTBEAT.
// The founder, 9 Sep 2026: "the CEO is supposed to email me once a week for a report... about the
// whole company". fn_ceo_weekly_report_tick is idempotent by ISO week and gated on a configured
// local day and hour (app_secrets.ceo_weekly_report_local_dow / _local_time, Asia/Dubai), so it
// returns fired:false roughly 670 of the 672 times it runs in a week and sends exactly once.
// 21 Sep 2026 (ceo): it failed on 14 and 21 Sep with the same fault — the delivery stored
// fn_notify_founder's jsonb answer in a bigint — and this step still read as healthy, because the
// failure sat one level down. The report now goes out AS A PDF on the company template, rendered here
// exactly as the accountant's weekly report is, and the tick answers ok:false at the top level when
// delivery fails. See scripts/sql/the_weekly_report_arrives_and_the_rules_decide.sql.
async function ceoWeeklyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_weekly_report_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    // strict_glyphs false: this is a narrative report whose figures are ASCII digits from format(); a
    // dash the font lacks must not hold the whole week's report back. The financial statement keeps true.
    return await renderPdfAndAttach(t, 'ceo/weekly', 'weekly_company_report', false, 'fn_ceo_weekly_report_attach_pdf');
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE CEO WEEKLY REVIEW THAT ACTS (29 Sep 2026, ceo, founder instruction 1009). fn_ceo_weekly_review_tick measures the
// five targets by code, closes, escalates and opens the seats' tracked improvements, and hands back one page; this
// renders it and fn_ceo_weekly_review_attach_pdf sends it through fn_notify_founder (kind ceo_weekly_review) with the
// PDF attached. scripts/sql/the_ceo_weekly_review_acts_on_every_missed_target.sql
async function ceoWeeklyReviewTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_weekly_review_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    return await renderPdfAndAttach(t, 'ceo/weekly_review', 'ceo_weekly_review', false, 'fn_ceo_weekly_review_attach_pdf');
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE FOUNDER'S 18:00 SUPPLIER LIST (24 Sep 2026, customer_support). fn_customer_support_campaign_list_tick
// builds, by code, the list of suppliers the campaign invites on the next sending day from the sender's own
// fn_supplier_invite_candidates, with the day's counts; this renders it on the company template and
// fn_customer_support_campaign_list_attach mails it (founder_mail_policy supplier_campaign_daily_list). A failed
// render is retained and retried next beat. scripts/sql/the_founder_sees_tomorrows_supplier_invitations_at_six.sql
async function supportCampaignListTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_customer_support_campaign_list_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    return await renderPdfAndAttach(t, 'customer_support/supplier_list', 'supplier_list', false, 'fn_customer_support_campaign_list_attach');
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE CEO'S TEN DECISION RULES, EVALUATED ON THE SAME HEARTBEAT (21 Sep 2026, ceo).
// public.ceo_decision held ten active rules and ceo_decision_log had never held a row: nothing in the
// database evaluated a rule. fn_ceo_decisions_evaluate is deterministic, writes one evidenced row per
// firing (deduplicated), emails nobody, and answers ok:false naming any active rule it cannot evaluate.
async function ceoDecisionsTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_decisions_evaluate', { p_dry_run: false });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE CEO'S DAILY PLAN (22 Sep 2026, ceo, founder instruction 638). fn_ceo_plan_tick measures the live
// funnel against the twelve-month plan, names the binding constraint, directs the seat that can move it
// through a ceo.directive handoff, and re-measures and closes every open directive on each call. That is
// plan C, the coded path, and it has already ACTED before anything below runs.
// Plan A/B is the model (instruction 643: the CEO will run on one, not yet chosen). It runs in the CEO's
// own function, ceo_agent action 'judgement', and ONLY when the tick says call_model --
// app_secrets.ceo_model_slot = 'on', which the founder sets. This heartbeat never imports the model
// client. The slot is off today, so that branch has never reached the gateway.
// scripts/sql/the_ceo_plans_every_day_and_directs_the_seats.sql.
async function ceoPlanTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_plan_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.judgement?.call_model || !t?.plan_id) return t;
    const r = await fetch(FN + '/ceo_agent', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_ceo_agent'), action: 'judgement', plan_id: t.plan_id }),
      signal: AbortSignal.timeout(45000),
    });
    const j = await r.json().catch(() => null);
    // A rejected answer is plan C working, not a failing step; only an unreachable seat is.
    return { ...t, judgement: { ...t.judgement, answer: j }, ...(r.ok ? {} : { ok: false, error: 'ceo_agent judgement ' + r.status }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// Postgres cannot draw a PDF, so a weekly tick hands back its block list and this renders it on the
// company template (pdf_native, letterhead) and hands the result — or the failure, as p_error — to the
// report's own attach routine. The report is RETAINED on a failed render and the next tick re-renders.
// deno-lint-ignore no-explicit-any
async function renderPdfAndAttach(t: any, folder: string, fallbackName: string, strictGlyphs: boolean, attachRpc: string): Promise<unknown> {
  let path: string | null = null, url: string | null = null, bytes: number | null = null, err: string | null = null;
  try {
    const r = await fetch(FN + '/pdf_native', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({
        __secret: await sec('cred_fn_resilience_ping'), title: t.subject, blocks: t.pdf_blocks,
        bucket: 'agent-docs', folder,
        name: String(t.report_key || fallbackName).replace(/[^\w.-]+/g, '_'),
        options: { letterhead: true, strict_glyphs: strictGlyphs },
      }), signal: AbortSignal.timeout(55000),
    });
    const j = await r.json().catch(() => null);
    if (r.ok && j?.ok && j?.path) { path = j.path; url = j.url ?? null; bytes = j.bytes ?? null; }
    else err = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
  } catch (e) { err = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
  const { data: att, error: aerr } = await admin.rpc(attachRpc, {
    p_id: t.id, p_bucket: 'agent-docs', p_path: path, p_url: url, p_bytes: bytes, p_error: err,
  });
  if (aerr) return { ...t, pdf_blocks: undefined, pdf_error: err, ok: false, error: 'attach: ' + aerr.message };
  // deno-lint-ignore no-explicit-any
  const a = att as any;
  const failed = err ?? (a && a.ok === false ? (a.error ?? a.reason ?? 'delivery refused') : null);
  return { ...t, pdf_blocks: undefined, delivery: att, ...(failed ? { ok: false, error: String(failed) } : {}) };
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
async function caseMemoryEmbedTick(): Promise<unknown> {
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
// function's workers. Four rows a tick (ML_TICK_MAX, measured); the backlog is drained by
// .github/workflows/ml-embed-backfill.yml. The gate and the daily cap are fn_ml_embed_claim's.
async function mlEmbedTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_ai');
    if (!secret) return { ok: false, error: 'cred_fn_ai is not in app_secrets' };
    const r = await fetch(FN + '/embed_ml', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, fn: 'resilience_ping', action: 'tick', limit: 4 }), signal: AbortSignal.timeout(50000),
    });
    const j = await r.json().catch(() => null);
    return { ok: r.ok, status: r.status, result: j };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
// THE LEARNING LOOP (23 Sep 2026, it_engineer; scripts/sql/every_judgement_learns_from_its_outcome.sql).
// Daily: per-seat accuracy against real outcomes into seat_learning_daily (a fall opens a finding).
// Weekly: cases with outcomes, grouped by meaning, distilled into cross-family-verified lessons
// (_shared/learning_loop.ts); held under the model hold, never written from words.
async function learningMeasureTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_seat_learning_measure', {});
    return error ? { ok: false, error: error.message } : data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
// Hourly, no model: embed + group in SQL. Weekly (learningDistil): reason only what crossed the threshold.
// Both on heartbeatDeps (27 Oct 2026, it_engineer): each unembedded finding (up to 8 a tick) is embedded in embed_ml,
// never in this worker, whose 2 s CPU cap killed the held replay (_shared/think.ts, above defaultDeps).
async function learningGroupTick(): Promise<unknown> {
  try { return await distilLessons(admin, heartbeatDeps(admin), 2, { reason: false }); } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
async function learningDistilTick(): Promise<unknown> {
  try { return await distilLessons(admin, heartbeatDeps(admin), 2, { reason: true }); } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

async function refundLadderTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_refund_ladder_sweep');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    return { seen: d?.seen, chased: d?.chased, final_calls: d?.final_calls, support_watch: d?.support_watch, ceo_loop: d?.ceo_loop };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT PAYS WHAT THE CEO APPROVED. The seat acts under its own credential
// (cred_fn_accountant -> fn.accountant), so the run is the accountant's, not this watchdog's.
async function accountantRefundTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_accountant');
    if (!secret) return { ok: false, error: 'cred_fn_accountant is not in app_secrets' };
    const r = await fetch(FN + '/accountant', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'execute_refunds' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, paused: j?.paused ?? null, executed: Array.isArray(j?.results) ? j.results.length : null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S DUTIES (14 Sep 2026, founder: "yea add them all" / "yea add them"). Called every
// tick; fn_accountant_duties_due inside the seat makes it hourly. Under the seat's own credential, so
// the run is the accountant's. The result names only counts: this endpoint is public and secretless.
async function accountantDutiesTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_accountant');
    if (!secret) return { ok: false, error: 'cred_fn_accountant is not in app_secrets' };
    const r = await fetch(FN + '/accountant', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, skipped: j?.skipped ? true : false, ok: j?.ok ?? null,
             errors: Array.isArray(j?.result?.errors) ? j.result.errors.length : null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MARKETING SEAT'S CHANNELS (22 Sep 2026, marketing). Every beat: publish what is due (a dry run while
// app_secrets.marketing_golive is not 'true'), then the once-a-Dubai-day reads fn_marketing_duties_due names
// (access check, insights, ad spend -> the accountant). Under the seat's own credential, so the run is the
// marketing seat's. The result names only counts: this endpoint is public and secretless.
async function marketingChannelsTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing_channels');
    if (!secret) return { ok: false, error: 'cred_fn_marketing_channels is not in app_secrets' };
    const r = await fetch(FN + '/marketing_channels', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: j?.ok ?? null, due: j?.publish?.due ?? null, published: j?.publish?.published ?? null,
             dry_run: j?.publish?.dry_run ?? null, daily: j?.daily ? Object.keys(j.daily) : [] };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MARKETING SEAT'S DUTIES (founder instruction 721, 22 Sep 2026): its own duty list, then fn_marketing_tick
// (the daily report the CEO reads, and the ad-spend loops with the accountant). Presented as the seat, exactly
// as the accountant's duties are; resilience_step 'marketing' sets the cadence.
async function marketingTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing');
    if (!secret) return { ok: false, error: 'cred_fn_marketing is not in app_secrets' };
    const r = await fetch(FN + '/marketing', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(DETACHED_MS),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: r.ok && j?.ok !== false, duties: j?.result?.duties ?? null,
             failing: j?.result?.failing ?? null, report: j?.result?.tick?.report ?? null,
             ...(r.ok ? {} : { error: 'marketing ' + r.status }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

async function vatThresholdTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_accountant_vat_threshold_check', { p_notify: true });
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE MARKETING SEAT'S BUSINESS DEVELOPMENT (22 Sep 2026, marketing; founder instruction 722). Every beat:
// the morning LinkedIn list once a Dubai day (emailed to the founder only while marketing_golive is 'true'),
// the weekly article cadence and the live check. Under the seat's own credential; the result names only counts.
async function marketingOutreachTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_marketing_outreach');
    if (!secret) return { ok: false, error: 'cred_fn_marketing_outreach is not in app_secrets' };
    const r = await fetch(FN + '/marketing_outreach', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, action: 'duties' }), signal: AbortSignal.timeout(55000),
    });
    // deno-lint-ignore no-explicit-any
    const j = await r.json().catch(() => null) as any;
    return { status: r.status, ok: j?.ok ?? null, listed: j?.outreach?.listed ?? null, delivery: j?.outreach?.delivery ?? null,
             released: j?.articles?.release?.released ?? null, live: j?.articles?.live?.length ?? null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// The IT engineer's half of the backup (founder, 14 Sep 2026: "i think the IT agent need to check
// such details yea?"): close verified refiles, run the 48-hour coverage watch, file the daily line
// to the CEO, and once a Dubai week re-check a random sample of Dropbox files.
// deno-lint-ignore no-explicit-any
async function dropboxVerifyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_it_backup_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    if (!(data as any)?.reconcile?.due) return data;
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/dropbox_backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, mode: 'reconcile', limit: 20 }), signal: AbortSignal.timeout(55000),
    });
    const reconcile_run = { status: r.status, result: await r.json().catch(() => null) };
    // deno-lint-ignore no-explicit-any
    return { ...(data as any), reconcile_run, ...(r.ok ? {} : { ok: false, error: httpHopError('dropbox_backup reconcile', r.status, reconcile_run.result) }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// DROPBOX IS CHECKED EVERY DAY (it_engineer, 15 Sep 2026): the login, a write/read/delete probe and
// the space used, once a Dubai day and two hours after a failed reading (fn_it_dropbox_health_due).
// Its own tick, never behind fn_it_backup_tick, so neither can stop the other. dropbox_backup records
// the reading itself; if the call never got that far (timeout, a 5xx from our own function), this
// records it as an internal failure so a silent probe is still a finding. Only the verdict comes back:
// this endpoint is public.
// THE VERCEL CONFIGURATION, ONCE A DAY (it_engineer, 12 Oct 2026; the_vercel_configuration_is_backed_up_every_day.sql).
// Read only: the project, its domains, its env var NAMES (never decrypted, and vercel_snapshot.ts drops every value
// again) and its crons. The JSON goes to the private backups bucket and is filed for Dropbox under Company/Vercel/.
// The env vars the site reads are the names in the site's own code (src/: process.env.*), listed here.
// 27 Oct 2026: the site reads the new keys first (NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEY) and the legacy
// ones only as the temporary fallback; drop the two legacy names with that fallback.
const SITE_ENV_NAMES = ['CRON_SECRET', 'NEXT_PUBLIC_SUPABASE_ANON_KEY', 'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'NEXT_PUBLIC_SUPABASE_URL', 'SITE_ERROR_INGEST_SECRET', 'SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY'];
async function vercelSnapshotTick(): Promise<unknown> {
  try {
    const [token, pid, team] = await Promise.all([sec('vercel_token'), sec('vercel_project_id'), sec('vercel_team_id')]);
    if (!token || !pid) return { ok: false, error: 'vercel_token or vercel_project_id is not in app_secrets' };
    const q = team ? `?teamId=${encodeURIComponent(team)}` : '';
    const get = async (p: string) => {
      const r = await fetch('https://api.vercel.com' + p + q, { headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(15000) });
      if (!r.ok) throw new Error('vercel ' + p.split('/').slice(0, 3).join('/') + ' ' + r.status);
      return await r.json();
    };
    const [project, domains, env] = await Promise.all([get(`/v9/projects/${pid}`), get(`/v9/projects/${pid}/domains`), get(`/v10/projects/${pid}/env`)]);
    const day = new Date().toISOString().slice(0, 10);
    const snap = vercelSnapshot(project, domains, env, new Date().toISOString());
    const { data: keys } = await admin.from('app_secrets').select('key');
    const cov = vercelEnvCoverage(SITE_ENV_NAMES, snap.env, (keys || []).map((k: { key: string }) => k.key));
    const path = `engineering/vercel/${day}.json`;
    const up = await admin.storage.from('backups').upload(path, new TextEncoder().encode(JSON.stringify({ ...snap, env_sources: cov.sources }, null, 1)),
      { contentType: 'application/json', upsert: true });
    if (up.error) return { ok: false, error: 'backups upload ' + up.error.message };
    const summary = { domains: snap.domains.length, env_names: snap.env.length, missing_in_vercel: cov.missing_in_vercel, no_recoverable_source: cov.no_recoverable_source };
    const { error } = await admin.rpc('fn_vercel_snapshot_filed', { p_path: path, p_summary: summary });
    if (error) return { ok: false, error: error.message };
    return { ok: true, path, ...summary };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
}

async function dropboxHealthTick(): Promise<unknown> {
  try {
    const { data: due, error } = await admin.rpc('fn_it_dropbox_health_due');
    if (error) return { ok: false, error: error.message };
    if (due !== true) return { due: false };
    let status = 0; let recorded: string | null = null; let why = '';
    try {
      const r = await fetch(FN + '/dropbox_backup', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), op: 'health' }), signal: AbortSignal.timeout(55000),
      });
      status = r.status;
      // deno-lint-ignore no-explicit-any
      const j: any = await r.json().catch(() => null);
      recorded = j?.recorded?.status ?? null;
      if (!recorded) why = 'dropbox_backup op health answered ' + r.status + ' ' + String(j?.error ?? '').slice(0, 200);
    } catch (e) { why = 'dropbox_backup op health did not answer: ' + String((e as Error)?.message || e).slice(0, 200); }
    if (!recorded) {
      const { data: rec, error: re } = await admin.rpc('fn_it_dropbox_health_record', { p: { error: why, class: 'internal' } });
      if (re) return { due: true, status, ok: false, error: re.message };
      // deno-lint-ignore no-explicit-any
      recorded = (rec as any)?.status ?? null;
    }
    return { due: true, status, recorded };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

async function backupTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_dropbox_backup_due');
    if (error) return { ok: false, error: error.message };
    if (!(data as any)?.due) return { due: false, ran_today: (data as any)?.ran_today, queued: (data as any)?.queued };
    const secret = await sec('cred_fn_resilience_ping');
    // STARTED, NOT AWAITED (18 Sep 2026, it_engineer) — the same shape as tableExportTick above, and for
    // the same reason. dropbox_backup v8 "calls itself again (process_only, up to 20 links) so a backlog
    // drains without waiting for the next tick": the chain runs in its OWN invocations whatever this tick
    // does, so awaiting the first pass bought nothing and cost everything. Measured 18 Sep: 2,006
    // documents queued, dropbox_backup averaging 33.8 s a call over 306 calls in 6 hours — of which only
    // ~4 an hour are this step; the rest are the chain draining itself. Awaiting it was ~25 s of a 110 s
    // tick spent watching a worker that did not need watching, and it is where the finding
    // duty:heartbeat:backup, "Signal timed out", seen 34 times by 07:17Z, came from: the 55 s timeout
    // fired on a pass that was working perfectly.
    // The pass still reports itself — dropbox_backup writes its own agent_runs rows, fn_it_backup_tick
    // and fn_dropbox_backup_due both read them, so a chain that stops is still a finding.
    const started = fetch(FN + '/dropbox_backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 25 }),
    }).then((r) => r.body?.cancel()).catch(() => {});
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(started);
    return { due: true, started: true, queued: (data as any)?.queued };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// TWO FUNCTIONS THAT NOTHING CALLED (17 Sep 2026, it_engineer). email_cron and wa_templates_watch are
// deployed, owned and instrumented, and pg_cron — which used to call them — has been empty since
// 7 Sep. agent_runs held ONE row for each, both 9 Sep 07:10. email_cron reports the one thing
// send_outbox structurally cannot (a disabled mail system: nothing would invoke send_outbox to tell
// you it is off) and auto-detects Resend domain verification; wa_templates_watch flips
// wa_templates_ready when Meta approves, and WhatsApp is the founder's command channel.
//
// GATED IN POSTGRES, like backupTick: one RPC answers for all of them, so a tick where none is due costs
// one round trip and no HTTP. email_cron is due only while email is NOT enabled (when it is, outboxTick
// below already drains every tick and email_cron would add nothing but a second flush);
// wa_templates_watch only while wa_templates_ready is not 'true', so it stops polling Twilio the moment
// approval lands. Measured 18 Sep: both flags are 'true', so both gates are shut and this step is the
// RPC alone. Each swallows its own error — a step that throws is a step the whole tick pays for.
//
// FOUR MORE JOINED ON 18 Sep 2026 (it_engineer, orphan audit). Every one is deployed, owned and live, and
// had no caller at all since pg_cron emptied on 7 Sep. Gates and measured backlogs are in
// scripts/sql/four_live_functions_had_no_clock_and_the_sanctions_screen_had_no_producer.sql:
//   doc_extract   the ONLY writer of documents.extracted and the only OCR path. 12 documents sat
//                 pending, the last extraction was 12 Aug. It CALLS ai_gateway on every document, so
//                 wiring it starts real model spend and OpenRouter is on hold: the gate also requires
//                 app_secrets.doc_extract_drain_enabled = 'true', a key that does not exist, so it ships
//                 SHUT. Flipping that one key is the whole switch-on.
//   email_triage  the only writer of inbound_messages.triaged_at; LLM per message, same flag treatment
//                 (email_triage_enabled). Measured drainable backlog: 0.
//   send_sms      drains channel='sms' notifications, which send_outbox deliberately refuses. NO flag —
//                 no model, and the gate is the queue itself, exactly like whatsappTick below.
//   sanctions_screen  downloads the UN and UAE sanctions lists and hands them to
//                 fn_supplier_sanctions_screen. Weekly, gated on the age of the newest screening_run.
// THE WHOLE STEP IS BOUNDED, NOT EACH CALL. Six gates, each with its own timeout, add to more than the
// 110 s the entire tick is allowed (30+20+20+25+40+55 = 190 s). So the step carries ONE budget, the gates
// run in priority order, and a job is only STARTED if what is left of the budget covers its own worst
// case — so ORPHAN_BUDGET_MS is a real ceiling and not a suggestion. Every one of these consumers is a
// queue drainer or an idempotent poller, so being deferred costs a beat and never a message. And a
// deferral is returned as a FAILURE, so a step that keeps running out of budget raises an IT finding
// instead of silently starving its tail — that failure has already been paid for once in this estate
// (outbox starvation, #691).
const ORPHAN_BUDGET_MS = 60_000;
// doc_extract extracts ONE document per call, so a queue of 12 would take three hours at one a tick.
// ponytail: up to 3 a tick, ~96 documents/day; raise DOC_MAX (and the budget) if a real upload queue
// outruns it.
const DOC_MAX = 3;

async function orphanTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_resilience_orphan_steps_due');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const due = data as any;
    if (!due || !Object.values(due).some(Boolean)) return { due: false };
    const secret = await sec('cred_fn_resilience_ping');
    // THE SANCTIONS SCREEN TAKES A DIFFERENT CREDENTIAL, AND THIS STEP COULD NEVER HAVE REACHED IT
    // (18 Sep 2026). Internal credentials are SCOPED — fn_internal_auth refuses one that is not scoped
    // to the callee — and this function's is not scoped to sanctions_screen. Measured in production:
    //   fn_internal_auth(cred_fn_resilience_ping, 'send_outbox')      -> ok:true (credential 49)
    //   fn_internal_auth(cred_fn_resilience_ping, 'sanctions_screen') -> out_of_scope
    //   fn_internal_auth(cred_cron_compliance,    'sanctions_screen') -> ok:true (credential 175,
    //                                              context cron.compliance, scope ['sanctions_screen'])
    // Exactly ONE credential in the table is scoped to sanctions_screen, and it is not this one. Proved
    // over HTTP as well: presenting this function's credential past the platform gateway answered
    // 403 {"error":"forbidden"}. So the step presents the credential the scope model already says owns
    // that call, rather than widening fn.resilience_ping's scope — widening it would make scoped
    // credentials decorative, which is the one thing audit 9.5 exists to prevent.
    const complianceSecret = await sec('cred_cron_compliance');
    // THE SAME RULE FOR THE OTHER FIVE (28 Sep 2026, it_engineer). wa_templates_watch answered 403 on
    // every hourly run: internal_credential_audit, 137 rows in 48 h, context fn.resilience_ping,
    // reason out_of_scope. send_sms, email_cron, email_triage and doc_extract were out of scope the
    // same way and only silent because their gates were shut. Each presents its owning context's
    // credential (scripts/sql/the_template_watcher_is_called_with_a_credential_scoped_to_it.sql);
    // prevented by scripts/checks/resilience_orphan_jobs_present_a_scoped_credential.test.mjs.
    const notificationsSecret = await sec('cred_cron_notifications');
    const documentsSecret = await sec('cred_cron_documents');
    // The accountant's own credential for its expense_sweep (reasoned_books.ts presents the same one):
    // this function's credential is not scoped to the accountant, and widening it is what audit 9.5 forbids.
    const accountantSecret = await sec('cred_fn_accountant');
    // A 200 CARRYING A FAILED BODY IS A FAILURE, AND failureOf CANNOT SEE INSIDE `body` (third finding
    // from independent review). Returning {status, body} meant only a fetch exception or a 4xx/5xx was
    // ever counted: a callee answering HTTP 200 {ok:false, error:'…'} — which is how every one of these
    // reports a refusal — was recorded in `results` and never pushed onto `failing`, so it raised no IT
    // finding. That is quote_compare's {ok:false} at HTTP 200, and it is in this repo's own skill as the
    // reason to assert on the effect and not the status. The failure is lifted to the top of the entry so
    // failureOf reads it. A bare {ok:false} with NO error string is deliberately left alone: by steps.ts's
    // convention that is a seat that has already staged its own finding, and counting it twice is noise.
    const call = async (slug: string, ms = 20000, body: Record<string, unknown> = {}, cred: string = secret) => {
      try {
        const r = await fetch(FN + '/' + slug, {
          method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
          body: JSON.stringify({ __secret: cred, ...body }), signal: AbortSignal.timeout(ms),
        });
        const b = await r.json().catch(() => null);
        const inner = r.status < 400 ? failureOf(b) : null;   // a 4xx/5xx is already read off `status`
        return inner
          ? { ok: false, error: slug + ' answered HTTP ' + r.status + ' with: ' + inner, status: r.status, body: b }
          : { status: r.status, body: b };
      } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
    };
    const t0 = Date.now();
    const left = () => ORPHAN_BUDGET_MS - (Date.now() - t0);
    // Order is priority: a queued SMS has a person at the end of it; the sanctions download is weekly
    // and the least urgent thing here, so it goes last and is the one that gets deferred.
    // The third element is that job's OWN worst case, and the loop below will not start a job it cannot
    // afford to finish. Gating on "any time left at all" would make ORPHAN_BUDGET_MS a suggestion: 500 ms
    // left is enough to start a 55 s download, and the step would overrun the whole tick's 110 s.
    const jobs: Array<[string, string, number, () => Promise<unknown>]> = [
      ['send_sms', 'send_sms', 30000, () => call('send_sms', 30000, { limit: 25 }, notificationsSecret)],
      ['email_cron', 'email_cron', 20000, () => call('email_cron', 20000, {}, notificationsSecret)],
      ['wa_templates', 'wa_templates_watch', 20000, () => call('wa_templates_watch', 20000, {}, notificationsSecret)],
      ['doc_extract', 'doc_extract', 25000, async () => {
        const d0 = Date.now();
        const runs: unknown[] = [];
        for (let i = 0; i < DOC_MAX && left() > 25_000; i++) {
          const r = await call('doc_extract', 25000, {}, documentsSecret);
          runs.push(r);
          // deno-lint-ignore no-explicit-any
          if ((r as any)?.body?.note === 'no pending documents' || (r as any)?.error) break;
        }
        // runSteps judges this step per ENTRY, and an entry it cannot read is a failure it cannot see.
        // {calls, ms, runs} has neither `ok` nor `status`, so a 500 from doc_extract would vanish inside
        // `runs` — the same shape of blindness the nested flag exists to end. Lift the first failure to
        // the top of this entry so failureOf reads it.
        const bad = runs.map((r) => failureOf(r)).find(Boolean) ?? null;
        return bad
          ? { ok: false, error: bad, calls: runs.length, ms: Date.now() - d0, runs }
          : { calls: runs.length, ms: Date.now() - d0, runs };
      }],
      ['email_triage', 'email_triage', 40000, () => call('email_triage', 40000, {}, notificationsSecret)],
      // 28 Sep 2026: held expense mail is swept daily, so a receipt from a sender the books know is booked
      // without a model (scripts/sql/the_books_catch_up_under_the_model_hold_from_known_senders.sql).
      ['expense_sweep', 'accountant.expense_sweep', 55000, () => call('accountant', 55000, { action: 'expense_sweep' }, accountantSecret)],
      ['sanctions', 'sanctions_screen', 55000, () => call('sanctions_screen', 55000, {}, complianceSecret)],
    ];
    const out: Record<string, unknown> = {};
    for (const [gate, key, need, run] of jobs) {
      if (!due[gate]) continue;
      // A DEFERRED JOB IS A FAILURE, NOT A NOTE (found in independent review before this shipped).
      // Written as {deferred:true}, failureOf reads neither `ok` nor `status`, so runSteps would skip it
      // and the IT engineer would never hear about it — and `sanctions` is last in this list, so the one
      // thing here that is a compliance obligation is exactly the one a busy tick would starve in
      // silence, for ever. That is outbox starvation (#691) rebuilt one level down. So it is shaped as
      // {ok:false, error}: fn_it_duty_settle raises ONE finding per step and counts the repeats, which is
      // the difference between "deferred once, 15 minutes late" and "never runs".
      if (left() < need) {
        out[key] = { ok: false, error: 'deferred: only ' + Math.max(0, left()) + ' ms of the orphan step budget left, this call needs ' + need + ' ms' };
        continue;
      }
      out[key] = await run();
    }
    out.ms = Date.now() - t0;
    return out;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE DAILY TABLE EXPORT HANGS HERE, FOR THE SAME REASON AS THE DROPBOX BACKUP (14 Sep 2026).
// Its pg_cron job (109) went on 7 Sep and its worker (supabase/functions/backup) on 8 Sep; the last
// export in the backups bucket is 2026-09-07. fn_table_export_due claims the Asia/Dubai day once
// after 03:00, resumes a chain whose heartbeat stopped, and retries a failed day. The chain runs on
// in its own invocations, so this tick only starts it and does not wait for it. Public endpoint:
// counts and dates only.
async function tableExportTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_table_export_due');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    if (!d?.due) return { due: false, stamp: d?.stamp, status: d?.status ?? null };
    const secret = await sec('cred_fn_resilience_ping');
    const started = fetch(FN + '/backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, stamp: d.stamp, kind: d.kind, since: d.since ?? null, state: d.resume ?? null }),
    }).then((r) => r.body?.cancel()).catch(() => {});
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil?.(started);
    return { due: true, stamp: d.stamp, attempt: d.attempt, resumed: d.resume != null };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// BACKUP RETENTION (15 Sep 2026, it_engineer): 90 days for every export day, 12 months for Friday full
// copies. fn_backup_prune_tick runs its pass once per Dubai day after that day's export finished, and
// in dry-run mode (the default) only logs what it would delete. In delete mode the two workers below
// remove what it logged: backup op 'prune' (storage) and dropbox_backup op 'prune' (Dropbox). Public
// endpoint: counts only.
async function backupPruneTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_backup_prune_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const d = data as any;
    const out: Record<string, unknown> = { mode: d?.mode, pass: d?.pass ?? null, storage_pending: d?.storage_pending,
                                           dropbox_pending: d?.dropbox_pending, findings: d?.findings };
    if (!d?.storage_pending && !d?.dropbox_pending) return out;
    const secret = await sec('cred_fn_resilience_ping');
    const call = async (fn: string) => {
      const r = await fetch(FN + '/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: secret, op: 'prune' }), signal: AbortSignal.timeout(55000) });
      await r.body?.cancel().catch(() => {});
      return r.status;
    };
    if (d.storage_pending) out.storage_run = await call('backup').catch((e) => String((e as Error)?.message || e));
    if (d.dropbox_pending) out.dropbox_run = await call('dropbox_backup').catch((e) => String((e as Error)?.message || e));
    // A prune worker that answered 4xx/5xx or threw is a failed step, not a number in a field.
    const bad = [out.storage_run, out.dropbox_run].find((v) => typeof v === 'string' || (typeof v === 'number' && v >= 400));
    if (bad !== undefined) { out.ok = false; out.error = 'a prune worker answered ' + bad; }
    return out;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE FOUNDER'S WHATSAPP QUEUE HAD NO CONSUMER AT ALL. Measured 9 Sep 2026: public.notifications
// held a channel='whatsapp' founder alert queued since 7 Sep 18:15 with attempts = 0, and
// public.agent_runs held ZERO rows for send_whatsapp — it has never run. Nothing in the repository
// calls it. It used to be drained by the pg_cron job wa_flush, and pg_cron was removed on 7 Sep by
// the founder's instruction, which is the same day the message stopped moving.
//
// WhatsApp is his command channel, so a queue with no consumer there is not a cosmetic gap: every
// alert routed to it since 7 Sep has been written and never delivered, and nothing reported that,
// because a queued row looks identical to one that is simply waiting its turn.
//
// Swallowed like the other ticks — the founder's WhatsApp must never take the watchdog down — and
// deliberately run on EVERY tick rather than only the unhealthy branch, because the messages this
// drains are mostly written while the system is healthy.
async function whatsappTick(): Promise<unknown> {
  try {
    const { count } = await admin.from('notifications')
      // 'sending' is counted (22 Sep 2026, CONN-03): a claimed row is mail that has not gone, and only
      // a sender requeues an expired claim, so counting 'queued' alone would report an empty queue in
      // the one case that matters — the sender being down.
      .select('id', { count: 'exact', head: true }).eq('channel', 'whatsapp').in('status', ['queued', 'sending']);
    // A HEARTBEAT THAT BEATS ONLY UNDER LOAD IS NOT A HEARTBEAT (21 Sep 2026). This used to return
    // here when nothing was queued, so send_whatsapp ran only when there was mail: 26 runs in the
    // 3.4 days to 21 Sep against a tick every 15 minutes. fn_it_detect's run_silent arm reads that
    // subject's own rhythm (p50 13 min over 7 days, from the weeks it drained every two minutes) and
    // raised "send_whatsapp has not run for 60/99/150 minutes" — seen 290 times, emailed to the
    // founder on 18 Sep — about a function that had nothing to do. The call is ~0.8 s (resilience_step
    // ewma 1654 ms) and the function's own queue read is its first statement, so it is made on every
    // tick and the subject has a real pulse to be measured against.
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: secret, limit: 25 }), signal: AbortSignal.timeout(30000),
    });
    const sent = { queued: count ?? 0, status: r.status, result: await r.json().catch(() => null) };
    // THE STATUS BACKSTOP (22 Sep 2026). Twilio does not retry a lost status callback, so every tick
    // wa_status asks Twilio directly about any WhatsApp/SMS sent 30+ minutes ago with no final status
    // (bounded: 20 a call, each row once per 30 minutes). Its own try, so it can never stop the drain.
    let backstop: unknown;
    try {
      const b = await fetch(FN + '/wa_status', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({ __secret: secret, poll: true }), signal: AbortSignal.timeout(30000),
      });
      backstop = { status: b.status, result: await b.json().catch(() => null) };
    } catch (e) { backstop = { ok: false, error: String((e as Error)?.message || e) }; }
    return { ...sent, status_backstop: backstop };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE WHATSAPP SENDER'S RATING, READ WITHOUT A MESSAGE (2 Nov 2026, ceo). The supplier invitation gate needs a reading
// under 26 hours old, and until now only a queued invitation caused one, so the channel could never open.
async function waSenderQualityTick(): Promise<unknown> {
  try {
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), read_sender_quality: true }), signal: AbortSignal.timeout(8500),
    });
    return { ok: r.ok, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S WEEKLY FINANCIAL REPORT HANGS HERE FOR THE FOURTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: the accountant must "create weekly report as pdf and share it with me and
// the CEO". A weekly report needs a schedule and pg_cron is not one any more, so the once-per-ISO-week
// decision lives in fn_accountant_weekly_report_tick where Asia/Dubai is a real timezone.
// It differs from the other three in ONE way: Postgres cannot render a PDF. The tick returns the
// pdf_native block list it stored at generation, this function renders it, and
// fn_accountant_weekly_report_attach_pdf takes the result and delivers to both recipients. A render
// failure is handed back as p_error, the report row is RETAINED with the reason, and the next tick
// re-renders from the same stored blocks -- so an unavailable PDF service delays a report and never
// loses one. strict_glyphs is true because this document is a financial statement: a character the
// fonts cannot draw would vanish out of a money figure with nothing saying so, and nobody re-reads
// this against a source. Swallowed like the other three: a report must never take the watchdog down.
async function accountantWeeklyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_accountant_weekly_report_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    const secret = await sec('cred_fn_resilience_ping');
    let path: string | null = null, url: string | null = null, bytes: number | null = null, err: string | null = null;
    try {
      const r = await fetch(FN + '/pdf_native', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
        body: JSON.stringify({
          __secret: secret, title: t.subject, blocks: t.pdf_blocks,
          bucket: 'agent-docs', folder: 'accountant/weekly',
          name: String(t.report_key || 'weekly_financial_report').replace(/[^\w.-]+/g, '_'),
          options: { letterhead: true, strict_glyphs: true },
        }), signal: AbortSignal.timeout(55000),
      });
      const j = await r.json().catch(() => null);
      if (r.ok && j?.ok && j?.path) { path = j.path; url = j.url ?? null; bytes = j.bytes ?? null; }
      else err = 'pdf_native ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 400);
    } catch (e) { err = 'pdf_native unreachable: ' + String((e as Error)?.message || e); }
    const { data: att, error: aerr } = await admin.rpc('fn_accountant_weekly_report_attach_pdf', {
      p_id: t.id, p_bucket: 'agent-docs', p_path: path, p_url: url, p_bytes: bytes, p_error: err,
    });
    // A render or attach failure keeps the report for the next tick AND is a failed step until it heals.
    if (aerr) return { ...t, pdf_blocks: undefined, pdf_error: err, ok: false, error: 'attach: ' + aerr.message };
    return { ...t, pdf_blocks: undefined, delivery: att, ...(err ? { ok: false, error: err } : {}) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE ACCOUNTANT'S DAILY OPENROUTER METER HANGS HERE FOR THE FIFTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: "the accountant need to be tracking open router daily expense with a
// breakdown of where it was used. which agent used it and for what, like a proper log."
//
// WHY A METER AND NOT A DAILY ENDPOINT. Probed with the real key on 9 Sep 2026:
//   GET /api/v1/credits  -> 200  {"data":{"total_credits":210,"total_usage":195.92587941}}
//   GET /api/v1/key      -> 200  usage_daily 0, usage_monthly 0, limit_remaining 4.07412059
//   GET /api/v1/activity -> 403  "Only management keys can fetch activity for an account"
// The endpoint that would hand us a day's spend directly is refused to the key we hold, and this
// function does not ask the founder to mint a management key. So the day is read the way a utility
// bill is read: /api/v1/credits returns a MONOTONIC lifetime total_usage, and two readings either
// side of a day differ by exactly what that day cost. Every ~15 minutes is the sampling rate that
// makes "the last reading of the day" a tight bound on midnight.
//
// A FAILED READING IS STILL RECORDED, with ok:false and the error. That is deliberate and it is
// the whole reason the reconciliation can be honest: a gap in the meter is what turns a day's
// basis from 'measured' to 'unknown', and a dropped failure would let a gap look like a quiet day.
// Swallowed like the other four: bookkeeping must never take the watchdog down.
async function openrouterMeterTick(): Promise<unknown> {
  const reading: Record<string, unknown> = { ok: false };
  try {
    const key = await sec('openrouter_api_key');
    if (!key) {
      reading.err = 'app_secrets.openrouter_api_key is missing or empty, so the meter cannot be read';
    } else {
      const H = { Authorization: 'Bearer ' + key };
      const [cr, kr] = await Promise.all([
        fetch('https://openrouter.ai/api/v1/credits', { headers: H, signal: AbortSignal.timeout(15000) })
          .then(r => r.json()).catch((e) => ({ __err: String((e as Error)?.message || e) })),
        fetch('https://openrouter.ai/api/v1/key', { headers: H, signal: AbortSignal.timeout(15000) })
          .then(r => r.json()).catch((e) => ({ __err: String((e as Error)?.message || e) })),
      ]);
      // deno-lint-ignore no-explicit-any
      const c = (cr as any)?.data, k = (kr as any)?.data;
      // total_usage from /credits is THE meter. Everything else is corroborating. If it is absent
      // the reading is not ok, even when /key answered — half a reading cannot close a day.
      if (c && typeof c.total_usage === 'number') {
        reading.ok = true;
        reading.cumulative_usd = c.total_usage;
        reading.credits_total_usd = c.total_credits ?? null;
      } else {
        reading.err = 'credits: ' + JSON.stringify(cr ?? {}).slice(0, 300);
      }
      if (k) {
        reading.usage_daily_usd = k.usage_daily ?? null;
        reading.usage_monthly_usd = k.usage_monthly ?? null;
        reading.limit_remaining_usd = k.limit_remaining ?? null;
        reading.key_label = k.label ?? null;
        // The key endpoint carries its own lifetime `usage`; when /credits failed it is the only
        // meter we have, so it is used rather than losing the reading entirely.
        if (!reading.ok && typeof k.usage === 'number') {
          reading.ok = true; reading.cumulative_usd = k.usage;
          reading.err = String(reading.err ?? '') + ' [fell back to /api/v1/key usage]';
        }
      } else {
        reading.err = String(reading.err ?? '') + ' key: ' + JSON.stringify(kr ?? {}).slice(0, 200);
      }
    }
  } catch (e) { reading.err = String((e as Error)?.message || e).slice(0, 400); }
  try {
    const { data, error } = await admin.rpc('fn_accountant_openrouter_tick', { p_reading: reading });
    if (error) return { ok: false, error: error.message, reading };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e), reading }; }
}

// THE IT ENGINEER'S ALERT HANGS HERE FOR THE SIXTH TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: "once their is an issue, he will email me directly so i can open a
// session with you to fix it ... he reports to me directly only". The delivery is deterministic and
// lives entirely in Postgres (fn_it_engineer_alert_tick, scripts/sql/
// the_it_engineer_hands_the_founder_a_session_he_can_start_from.sql); this call is only the clock.
//
// IT IS SAFE TO CALL EVERY 15 MINUTES, and that is the point rather than a tolerance: dedupe is on
// the ISSUE, not on the tick, so a problem open for a week produces ONE email, and a second only
// when a fact he was already told has changed (severity rose, affected at least doubled, it closed,
// it came back). A tick with nothing to say returns sent:0 and writes nothing.
//
// IT IS THE ONE TICK HERE THAT MUST NOT BE FULLY SWALLOWED. The other five are informational -- a
// digest or a report that fails is a missing document. This one is the monitor, and a monitor that
// fails open is worse than no monitor, because zero findings then reads as a quiet night. So the
// routine itself never raises (it records partial failure into founder_alerts and returns it), and
// its result is carried in this function's response either way, so the failure is visible in the
// watchdog's own output instead of vanishing into a catch. The watchdog still cannot be taken down
// by it: an unreachable RPC returns ok:false here rather than throwing.
// THE IT ENGINEER'S DUTIES, HOURLY (founder, 14 Sep 2026: "fine add them"). The readings Postgres
// cannot take are taken here and handed to fn_it_duties, which decides; fn_it_duties_due keeps the
// HTTP calls to once an hour. Only a count is returned: this endpoint is public and the findings
// name internals. Runs before the alert tick so a new finding goes round the loop on this pass.
async function itDutiesTick(): Promise<unknown> {
  try {
    const { data: due, error: dueErr } = await admin.rpc('fn_it_duties_due');
    if (dueErr) return { ok: false, error: dueErr.message };
    if (due !== true) return { due: false };
    const readings = await takeDutyReadings(sec);
    const { data, error } = await admin.rpc('fn_it_duties', { p_r: readings });
    if (error) return { ok: false, error: error.message };
    // The SAME readings, no second HTTP call: fn_it_duties stores only expires_on, so a provider that
    // answers "this token has no expiry at all" (Meta debug_token expires_at 0) was measured hourly and
    // dropped, and the ledger went on asking the accountant for a date that will never exist. See
    // scripts/sql/configuration_that_is_missing_is_recorded_once_not_every_tick.sql.
    const { error: expErr } = await admin.rpc('fn_it_expiry_measured', { p_expiries: readings.expiries ?? {} });
    return { due: true, duties: Object.keys((data ?? {}) as Record<string, unknown>).length,
             expiries: expErr ? { ok: false, error: expErr.message } : true };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// EVERY EXTERNAL INTEGRATION, EVERY 15 MINUTES (it_engineer, 24 Sep 2026, founder instruction 979). The list is
// _shared/integration_registry.json; _shared/integration_watch.ts probes each due entry, retries once and makes
// the fixes it can (a Stripe webhook Stripe disabled is re-enabled), and fn_it_integration_settle files one
// finding per integration, closes it by its exact key on recovery, mails the founder only what the company could
// not fix, and counts what it did fix for the IT daily line. Only counts come back: this endpoint is public.
// THE MORNING INBOX PLACEMENT CHECK (24 Sep 2026, it_engineer). Rides on this step because it is the IT
// engineer's 15-minute step (resilience_step every 15 min) and needs no new schedule row
// (every_tick_step_is_scheduled.mjs), as PR #961's Postmaster reading rides on itlater. On a sending day the
// database queues one seed from 04:30 UTC; the next beats read its folder in the Gmail and Microsoft 365 seed
// inboxes (until 08:00 UTC) and fn_invite_placement_record decides. The batch waits for a verdict and goes only on
// Inbox + Inbox (the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql). Outside that
// window it is one indexed read. The answer is counts and verdicts only: this endpoint is public.
async function inboxPlacement(): Promise<Record<string, unknown>> {
  try {
    // The rotated Graph refresh token is stored here; the result's {error} goes back to the reader, which records the
    // message (never the token) in the reading's evidence.
    return await placementTick((fn, args) => admin.rpc(fn, args) as never, fetch, sec,
      async (k, v) => await admin.from('app_secrets').update({ value: v }).eq('key', k));
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

async function itIntegrationsTick(): Promise<unknown> {
  // TWO INDEPENDENT PATHS, run side by side (review of #966): an integration settle that errors must not skip the
  // morning's placement reading, and a placement error must not hide the integration result.
  const integrations = (async (): Promise<Record<string, unknown>> => {
    try {
      const { items, fixed, outcomes } = await integrationItems(fetch, sec, (k) => Deno.env.get(k));
      const { data, error } = await admin.rpc('fn_it_integration_settle', { p_duty: 'integration', p_items: items, p_fixed: fixed });
      if (error) return { ok: false, error: 'fn_it_integration_settle: ' + error.message };
      return { ok: true, probed: outcomes.length, failing: items.filter((i) => !i.carried && !i.recovered).length, fixed: fixed.length,
               settled: (data as Record<string, unknown> | null)?.failing ?? null };
    } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
  })();
  const replies = m365Replies();   // a third independent path (6 Oct 2026): replies to the Microsoft 365 mailbox
  // a fourth (2 Nov 2026): every other mailbox of the tenant, after supplier@, so one message addressed to both is taken once
  const tenantMail = replies.then(() => m365TenantMail());
  const [integ, placement] = await Promise.all([integrations, inboxPlacement()]);
  const inbox = await replies;
  const tenantInbox = await tenantMail;
  // Either path failing is this step's failure (duty:heartbeat:itintegrations), so it reaches the IT engineer's loop
  // the same beat. The batch is held by the gate regardless. placement carries counts and verdicts only (public).
  const errors = [integ.ok === false ? String(integ.error) : null, placement.ok === false ? 'inbox placement: ' + String(placement.error) : null,
    inbox.ok === false ? 'm365 reply inbox: ' + String(inbox.why) : null,
    tenantInbox.ok === false ? 'm365 tenant mailboxes: ' + String(tenantInbox.why) : null].filter(Boolean);
  return { ...integ, ok: errors.length === 0, ...(errors.length ? { error: errors.join('; ') } : {}), inbox_placement: placement, m365_reply_inbox: inbox, m365_tenant_mailboxes: tenantInbox };
}

// REPLIES TO supplier@quotesdone.com (6 Oct 2026, it_engineer + customer_support; _shared/m365_reply_inbox.ts).
// The invitation lane sends without a Reply-To once this reader is proven, so a supplier's answer lands in that
// mailbox; this reads it and hands every new message to resend_inbound, the handler every other reply goes through.
const m365OnFile = async (ids: string[]) => {
  const { data, error } = await admin.from('inbound_messages').select('provider_email_id').in('provider_email_id', ids);
  if (error) throw new Error('inbound_messages: ' + error.message);
  return new Set((data || []).map((r) => String(r.provider_email_id)));
};
const m365MessageOnFile = async (ids: string[]) => {
  const { data, error } = await admin.from('inbound_messages').select('message_id:raw->>message_id').in('raw->>message_id', ids);
  if (error) throw new Error('inbound_messages: ' + error.message);
  return new Set((data || []).map((r) => String((r as { message_id: unknown }).message_id)));
};
// Who wrote, read only: the founder or staff; a lead (leads.email or claimed_by) or a customer; else a stranger.
async function m365Sender(address: string): Promise<SenderKind> {
  const [own, rel] = await Promise.all([admin.rpc('fn_is_founder_own_inbox', { p_addr: address }), admin.rpc('fn_mail_sender_known', { p_email: address })]);
  if (own.error || rel.error) throw new Error('sender lookup failed');
  if (own.data === true || rel.data === 'staff') return 'founder';
  if (rel.data) return 'known';
  const { data, error } = await admin.from('leads').select('id').ilike('claimed_by', address.replace(/[\\%_]/g, '\\$&')).limit(1);
  if (error) throw new Error('sender lookup failed');
  return data?.length ? 'known' : null;
}
async function m365TenantMail(): Promise<Record<string, unknown>> {
  try {
    return await pollTenantMailboxes({
      fetchFn: (u, i) => timedFetch(u, i || {}, 25_000), env: (k) => Deno.env.get(k),
      inviteMailbox: await sec('invite_m365_mailbox'), listedMailboxes: await sec('m365_tenant_mailboxes'),
      strangersFrom: await sec('m365_tenant_strangers_from'), financialDomains: await sec('m365_financial_domains'), messageOnFile: m365MessageOnFile,
      inboundToken: await sec('resend_inbound_token'), signingSecret: await sec('resend_inbound_signing_secret'), inboundUrl: FN + '/resend_inbound',
      onFile: m365OnFile, sender: m365Sender,
      // counts.m365_tenant and never counts.m365_inbox: send_outbox's proof read cannot select this row.
      record: async (status, counts, note) => {
        await admin.from('agent_runs').insert({ agent: PROOF_LABEL, status, counts, note: note.slice(0, 500),
          started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
      },
    });
  } catch (e) { return { ok: false, why: String((e as Error)?.message || e).slice(0, 200) }; }
}
async function m365Replies(): Promise<Record<string, unknown>> {
  try {
    return await pollReplyInbox({
      fetchFn: (u, i) => timedFetch(u, i || {}, 25_000), env: (k) => Deno.env.get(k),
      mailbox: await sec('invite_m365_mailbox'), inboundToken: await sec('resend_inbound_token'),
      signingSecret: await sec('resend_inbound_signing_secret'), inboundUrl: FN + '/resend_inbound',
      onFile: m365OnFile, sender: m365Sender, messageOnFile: m365MessageOnFile,
      fileFinding: async (args) => { const { error } = await admin.rpc('fn_it_engineer_finding_upsert', args); if (error) throw error; },
      record: async (status, counts, note) => {
        await admin.from('agent_runs').insert({ agent: PROOF_LABEL, status, counts, note: note.slice(0, 500),
          started_at: new Date().toISOString(), finished_at: new Date().toISOString() });
      },
    });
  } catch (e) { return { ok: false, why: String((e as Error)?.message || e).slice(0, 200) }; }
}

// DUTIES 9-15 ON THEIR OWN CADENCES (founder, 14 Sep 2026: "fine build those tasks for IT agent").
// fn_it_scheduled_due names what is due; only those readings are taken; fn_it_duties_scheduled decides.
async function itScheduledTick(): Promise<unknown> {
  try {
    const { data: due, error: dueErr } = await admin.rpc('fn_it_scheduled_due');
    if (dueErr) return { ok: false, error: dueErr.message };
    const list = (due ?? []) as string[];
    const { data: n } = await admin.rpc('fn_it_threshold', { p_key: 'restore_sample_files' });
    const readings = await takeScheduledReadings(admin as never, sec, list, Number(n) || 5);
    const { data, error } = await admin.rpc('fn_it_duties_scheduled', { p_r: readings });
    if (error) return { ok: false, error: error.message };
    // Duty 10 settles findings; this keeps the day's numbers (scripts/sql/sender_health_is_recorded_once_a_day_and_a_breach_is_named.sql).
    let senderRow: unknown = null;
    if (readings.sender) {
      const { data: row, error: rerr } = await admin.rpc('fn_it_sender_health_record', { p_sender: readings.sender });
      senderRow = rerr ? { ok: false, error: rerr.message } : { breaches: (row as { breaches?: string[] })?.breaches ?? [] };
    }
    return { due: list, settled: Object.keys((data ?? {}) as Record<string, unknown>), sender_health: senderRow };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE IT ENGINEER'S DUTIES 19-24 (founder, 14 Sep 2026: "add all for accountant and IT"). Each step is its
// own try, so one failing duty is reported and never stops the others or the watchdog. Only booleans and
// counts come back, because this endpoint is public. The routines each own a file in scripts/sql/.
//   renewal        fn_it_renewal_watch   licences, domains, tokens: 60 and 30 days to the accountant (20)
//   changes        GitHub's verdict on every revision a signed apply named, then fn_it_change_watch (24)
//   usage          when it_duty_schedule says so: provider usage against the caps in it_threshold (22)
//   restore_table  monthly: one table page from the newest finished export restored into scratch (19)
// Duty 19's file half is duty 9's sample (itScheduledTick); 21 is duty 10's sender check; 23's patch PR
// runs in .github/workflows/it-weekly-readings.yml. Runs before the alert tick, so anything raised here
// goes round the IT loop on this same pass.
async function itLaterDutiesTick(clock: StepClock = stepClock()): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const rpc = async (fn: string, args?: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + error.message);
    return data;
  };
  const pause = await pausedDuties(admin);
  const step = async (name: string, run: () => Promise<unknown>) => {
    if (pause.has('resilience_ping.' + name)) { out[name] = PAUSED; return; }
    // every step is timed on the run's clock, which outlives the 120 s race (steps.ts stepClock)
    clock.begin(name);
    try { out[name] = await run(); } catch (e) { out[name] = { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
    clock.end(name, !failureOf(out[name]));
  };
  await step('renewal', async () => { await rpc('fn_it_renewal_watch'); return { ok: true }; });
  await step('changes', async () => {
    const revs = ((await rpc('fn_it_change_revisions_due')) ?? []) as string[];
    await rpc('fn_it_change_revisions_record', { p: await verifyRevisions(sec, revs) });
    return { asked: revs.length };
  });
  await step('usage', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('usage')) return { due: false };
    await rpc('fn_it_usage_watch', { p_r: await takeUsageReadings(sec) });
    return { due: true };
  });
  // WhatsApp / SMS delivery health (22 Sep 2026): read from what Twilio reported — delivered, read,
  // failed, undelivered — never from 'sent', which only ever meant Twilio accepted the message.
  await step('whatsapp_delivery', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('whatsapp_delivery')) return { due: false };
    return { due: true, result: await rpc('fn_it_whatsapp_delivery_health') };
  });
  // THE SCHEDULED READINGS RUN BEFORE THE MODEL STEPS (it_engineer, 19 Oct 2026). They used to sit at the end of this
  // chain, behind deliberations, held-reasoning replay and routine judgements. Since ruling 1260 opened the models,
  // those steps make real model calls (ai_cost_log, 01:00-04:00 UTC 19 Oct: 242 to 1,796 calls an hour, up from
  // 31-115). The detached itlater run ran out of its instance's time before reaching the tail: provider_status
  // last succeeded at 00:46 UTC and model_catalogue never ran once, while duty:usage and duty:whatsapp_delivery,
  // which come first, kept running every hour. These four steps are cheap, model-free and due-gated, so they run
  // first; a slow model step can delay only itself and the steps after it.
  // Provider status pages and the Vercel firewall (24 Sep 2026, it_engineer; seat audit IT gaps 3 and 5). Measured
  // here, decided by fn_it_provider_watch, hourly by it_duty_schedule 'provider_status'.
  await step('provider_status', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('provider_status')) return { due: false };
    const r = (await rpc('fn_it_provider_watch', { p_r: await takeProviderReadings(sec) })) as Record<string, unknown>;
    return { due: true, failing: r?.failing ?? null };
  });
  // Gmail Postmaster Tools, once a day (it_engineer, 24 Sep 2026): spam rate, reputation and SPF/DKIM/DMARC for
  // quotesdone.com, read by _shared/it_postmaster_readings.ts and stored and acted on by fn_it_postmaster_record
  // (a finding at 0.1%; the #943 invitation pause at 0.3% or reputation LOW/BAD). Next to the sender duty's DNS and
  // blocklist reading, on this heartbeat, never pg_cron. This function deploys on merge while its SQL may still be
  // pending, so runPostmasterStep records a missing routine or table as "skipped: schema not applied".
  await step('postmaster', () => runPostmasterStep((fn, args) => admin.rpc(fn, args), () => takePostmasterReading(fetch, sec)));
  // The model registry against the public OpenRouter catalogue, once a day (it_engineer, follow-up 28). Reading the
  // catalogue is a public GET with no key, not inference. Postgres records (fn_model_catalogue_sync): every disagreement
  // becomes a ledger row and a finding; no price is ever changed here (rulings 1217/1218). Only the fields the
  // rule reads are sent, so the payload is a fraction of the catalogue.
  await step('model_catalogue', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('model_catalogue')) return { due: false };
    const res = await timedFetch('https://openrouter.ai/api/v1/models', {}, 20_000);
    if (!res.ok) throw new Error('catalogue answered HTTP ' + res.status);
    // deno-lint-ignore no-explicit-any
    const data = ((await res.json())?.data ?? []) as any[];
    const cat = data.map((m) => ({ id: m?.id, context_length: m?.context_length ?? null,
      pricing: { prompt: m?.pricing?.prompt ?? null, completion: m?.pricing?.completion ?? null } }));
    const r = (await rpc('fn_model_catalogue_sync', { p_catalogue: cat })) as Record<string, unknown>;
    return { due: true, compared: r?.compared, open: r?.open, new: r?.new,
             resolved: r?.resolved };
  });
  await step('supplier_docs', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('supplier_docs')) return { due: false };
    const r = (await rpc('fn_sales_engineer_supplier_documents_tick')) as Record<string, unknown>;
    return { due: true, approved_rechecked: r?.approved_rechecked, registrations_closed: r?.registrations_closed };
  });
  await step('held_registrations', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('held_registrations')) return { due: false };
    const unreached = await rpc('fn_sales_engineer_closes_unreached_requests');
    return { due: true, ...((await rpc('fn_sales_engineer_decides_held_registrations')) as Record<string, unknown>), unreached };
  });
  // Its own step, never behind fn_it_restore_table_due: a drill that stops completing is a finding.
  await step('restore_overdue', async () => rpc('fn_it_restore_table_overdue'));
  // Two seats never agree on one model family (founder_instruction 873). The review steps are routed and
  // held in the database (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql): under the hold each
  // one records "held, not run" once and costs nothing. Then the agreement monitor: a reviewer approving
  // >= 90% of >= 10 proposals, or a review with no independent model, is a finding for the CEO.
  await step('deliberations', async () => advanceOpenDeliberations(admin, 3));
  // Ledger 1152: open requests to review an automated decision are decided by the owning seat on another model family. The
  // model call runs in the CEO seat's own function (this heartbeat never imports the model client).
  await step('review_requests', async () => {
    const r = await fetch(FN + '/ceo_agent', { method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_ceo_agent'), action: 'review_requests', limit: 1 }), signal: AbortSignal.timeout(55000) });
    const j = await r.json().catch(() => null);
    return r.ok ? j : { ok: false, error: 'ceo_agent review_requests ' + r.status, body: j };
  });
  await step('deliberation_independence', async () => rpc('fn_it_deliberation_independence_watch'));
  // Reviews held for want of an independent model, and third-family last-resort reviews, reach the CEO (#880).
  await step('review_independence', async () => rpc('fn_it_review_independence_watch'));
  // Questions a seat could not reason about under the hold are reasoned the moment it lifts
  // (founder_instruction 886-903; _shared/think.ts replayHeld). Under the hold fn_reason_held_due
  // returns nothing and no model is asked, so this step costs one gate read. Since 7 Oct (ledger 1175) a tick claims REPLAY_CLAIM
  // at a time, concurrently, up to REPLAY_MAX_ROWS within REPLAY_BUDGET_MS, a slice that fits every tick (12 Oct).
  // 27 Oct 2026 (review of #1688): the replay no longer runs here. It is KICKED into its own detached invocation
  // (heldReplayTick, its own DETACHED_MS), so its model calls can never eat the time of the steps after it
  // (reasoning_escalate's owed holding notices, routine_judgements, wa_arrival_sweep, ceo_support_replies). Measured:
  // duty:detached_itlater:itlater "passed its 120000 ms limit", seen 51 times 16:17-20:32Z with a 25 s replay budget.
  await step('reasoning_held', async () => kickDetached('heldReplay'));
  // The four routine judgements (quote spec match, repeat requests, supplier trade words, unknown-sender mail) queued by
  // their callers and not judged inline: five a tick, no per-day limit; three failed readings end a row. Held rows stay queued
  // (scripts/sql/the_retired_model_leaves_every_live_routine_and_the_judgement_queue_says_what_it_does.sql).
  // 27 Oct 2026 (it_engineer): KICKED into its own detached run (routineJudgementsTick), the same move #1688 made for the
  // replay. Measured: the 22:01:12Z itlater run claimed five rows here at 22:01:27 and judged them one after another at
  // ~60 s each (two model calls of 19-31 s apiece); the run's cap fired at 22:03:12 with this step still going.
  await step('routine_judgements', async () => kickDetached('routineJudgements'));
  // A WHATSAPP TURN THAT CRASHED (customer_support, 19 Oct 2026): a wa_messages row still at stage 'received' after 5 minutes
  // goes to customer_support once and into the held-question queue (so reasoning_escalate below sends the holding notice in the same tick); never replayed
  // (scripts/sql/a_whatsapp_message_whose_turn_crashed_reaches_customer_support_in_five_minutes.sql).
  await step('wa_arrival_sweep', async () => ({ escalated: ((await rpc('fn_wa_arrival_sweep', { p_limit: 20 })) as unknown[] | null ?? []).length }));
  // A held question never expires: at 48 hours (or after 5 failed reasonings) it becomes a pending item in its
  // seat's queue, once, and a WhatsApp customer is told a person is handling it. Runs under the hold too; the
  // row stays held and is still replayed above the moment the hold lifts.
  // The CEO's answer to a customer_support handover (customer_support, #1462) passes the customer-reply gate before it
  // is sent; a held answer leaves the item open. Routing and pick-up run on pg_cron (cs_held_question_route); only this
  // TypeScript gate runs here (a_customer_support_question_reaches_a_person_in_fifteen_minutes.sql).
  await step('ceo_support_replies', async () => {
    const due = ((await rpc('fn_ceo_support_reply_due', { p_limit: 10 })) ?? []) as { handover_id: number; answer: string; lang: 'en' | 'ar'; supplier: boolean }[];
    const verdicts: Record<string, unknown>[] = [];
    for (const d of due) {
      const problems = await customerReplyGate((fn, args) => admin.rpc(fn, args), d.answer, d.lang, d.supplier);
      verdicts.push({ id: d.handover_id, verdict: await rpc('fn_ceo_support_reply_record', { p_handover_id: d.handover_id, p_problems: problems }), problems });
    }
    return { verdicts };
  });
  await step('reasoning_escalate', async () => {
    const rows = (await rpc('fn_reason_held_escalate', { p_limit: 20 })) as unknown[] | null;
    // The notices owed — the rows just escalated AND any earlier one whose send failed — come from the queue, not
    // from the escalate call's return, so a failure is retried (a_customer_notice_that_failed_is_sent_again.sql).
    const owed = (await rpc('fn_reason_held_notice_due', { p_limit: 20 })) as { id: number; surface: string; question: string; subject: Record<string, unknown> | null }[] | null;
    const told = await sendHeldNotices(owed ?? [], liveDeliveryIO(admin), (id, d) => rpc('fn_reason_held_notice_record', { p_id: id, p_delivery: d }));
    return { escalated: (rows ?? []).length, told };
  });
  // A SUPPLIER DOCUMENT WHOSE READ NEVER FINISHED (review of #1404): a profile or catalogue is marked 'reading' before
  // its parse; one still 'reading' after 30 minutes was killed mid-parse. It is set unreadable with the reason and handed
  // to the sales_engineer seat (fn_supplier_doc_reading_escalate) - never left silent - and the gate never approves past it.
  // BEFORE THAT, ONE RE-READ (19 Oct 2026, sales_engineer; _shared/supplier_docs_later.ts): a profile or catalogue read
  // after its upload answered and still 'reading' 10 minutes on is read once more by supplier_api (it runs after that
  // answer), marked retry; only a second stall reaches the escalation below.
  await step('supplier_doc_reread', async () => {
    const r = await timedFetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/supplier_api', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE_KEY },
      body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), action: 'docs_reread' }),
    }, 30_000);
    const j = await r.json().catch(() => ({}));
    if (!(r.ok && j?.ok)) throw new Error('supplier_api docs_reread: ' + String(j?.error ?? r.status));
    return { rereading: j.rereading };
  });
  await step('supplier_doc_reading_stuck', async () => {
    const rows = (await rpc('fn_supplier_doc_reading_escalate', { p_minutes: 30, p_limit: 50 })) as unknown[] | null;
    return { handed_to_sales_engineer: (rows ?? []).length };
  });
  // THE SUPPLIER TRADE BACKFILL (sales_engineer, 23 Sep 2026): files at most the daily cap of leads for reasoning,
  // and NOTHING unless app_secrets.lead_reclassify_backfill = 'go' (the cost is quoted beside the gate).
  await step('lead_reclassify', async () => rpc('fn_lead_reclassify_tick', { p_limit: 20 }));
  await step('restore_table', async () => {
    if ((await rpc('fn_it_restore_table_due')) !== true) return { due: false };
    const pick = await rpc('fn_it_restore_table_pick');
    await rpc('fn_it_restore_table_record', { p: await runRestoreTable(admin, pick) });
    return { due: true };
  });
  // Duty 15's third-party half: a provider key the estate can rotate by API is rotated and recorded; the database
  // decides when (fn_it_provider_rotation_claim) and the old key is deleted only after the overlap (_shared/it_rotate_by_api.ts).
  await step('rotate_by_api', async () => rotateAndSettle({ rpc, sec, fetch: (u, i) => timedFetch(u, i, 20_000) }));
  // The sales engineer's daily document duty, on this heartbeat because pg_cron is not coming back:
  // expiry reconcile and final notice, approved suppliers re-verified, 14-day incomplete registrations
  // closed (the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql). Counts only.
  return out;
}

// THE LAUNCH PATH, HOURLY (21 Sep 2026, it_engineer): the invitation link on both hosts in EN/AR, the
// customer's request page, the portal API, the sign-in code request and the portal functions' health —
// all read-only, none able to reach a person; _shared/launch_path.ts says what each probe asserts.
// Hourly by public.resilience_step (scripts/sql/the_launch_path_is_tested_every_hour.sql), not by
// GitHub Actions: an hourly job is 720 billed minutes a month on the allowance the 15-minute ping was
// moved off for (.github/workflows/resilience-ping.yml).
// A broken path is ONE finding, duty:launch_path:down, held open two clean hours before it closes so a
// blip cannot reopen it and re-email the founder as a recurrence. It reaches him only through
// fn_it_engineer_alert_tick and founder_mail_policy, never from here. This step reports ok:false only
// when it could not settle; a failing probe is the finding, not a failing step.
async function launchPathTick(): Promise<unknown> {
  try {
    const r = await probeLaunchPath(Deno.env.get('SUPABASE_ANON_KEY')!, fetch, undefined, (await sec('cred_fn_resilience_ping')) || undefined);
    const { data: open } = await admin.from('it_engineer_finding').select('last_seen_at')
      .eq('issue_key', 'duty:launch_path:down').is('closed_at', null).maybeSingle();
    const act = launchPathAction(r.ok, (open?.last_seen_at as string) ?? null);
    if (act !== 'hold') {
      const { error } = await admin.rpc('fn_it_duty_settle', { p_duty: 'launch_path', p_items: act === 'raise' ? [launchPathItem(r)] : [] });
      if (error) return { ok: false, error: 'fn_it_duty_settle: ' + error.message };
    }
    // Counts and probe names only: this endpoint is public.
    return { probes: r.results.length, failed: r.failed.map((x) => x.id), action: act, ms: r.ms };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

async function itEngineerAlertTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_it_engineer_alert_tick');
    if (error) return { ok: false, error: error.message };
    return data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE IT ENGINEER'S DETECTION TICK — "is anything wrong, in the app or on the website".
//
// Founder, 9 Sep 2026: the IT engineer must "monitor literally everything in the app and the
// website". Everything he can be asked about the DATABASE side — edge functions failing or failing
// more than usual, a subject that has gone silent past its own cadence, the scheduler skipping
// beats, error_events, a queue nobody is draining, latency departing a subject's own baseline —
// is decided deterministically inside fn_it_detect. No model call is anywhere on this path.
//
// This function exists only because Postgres cannot make an HTTP request and the website can only
// be judged by making one. So the split is the same one the OpenRouter meter already uses in this
// file: the tick MEASURES and Postgres DECIDES. Nothing here has an opinion about severity.
//
// THREE READINGS, and each one says honestly when it could not be taken:
//   home        GET public_site_url, status + milliseconds. The site's latency baseline is built
//               from these very samples in it_watch_tick, so it needs ~5 hours of ticks before it
//               can call anything slow, and reports insufficient_history until then.
//   deployment  the latest PRODUCTION deployment's state. NOTE app_secrets.vercel_project holds
//               'qd-site', a NAME, and /v6/deployments 404s on it — measured 9 Sep 2026. The id
//               lives in vercel_project_id; the name is kept as a fallback rather than deleted.
//   runtime     THE SITE REPORTS ITSELF (22 Sep 2026, SEATS-06). No Vercel REST path serves
//               runtime errors to the stored token: re-measured this morning, /v1/observability/
//               {errors,runtime-errors,logs}, /v1/projects/<id>/{observability/errors,runtime-logs},
//               /v1/deployments/<uid>/runtime-logs, /v1/errors and /v1/monitoring/metrics ALL 404
//               while /v6/deployments with the same token answers. So polling cannot take this
//               reading at all. src/instrumentation.ts (Next.js `onRequestError`) posts every
//               uncaught server error to the site_error_ingest function, which writes
//               public.error_events(source='website'), and this step COUNTS those rows for the last
//               hour. fn_it_detect raises website_runtime_errors from that count.
//               It still says honestly when it did not look: with no ingest secret, or no
//               'site_report_ready' heartbeat in 24 h (the site posts one per cold start), the
//               reading is 'unavailable' — zero rows from a site that is not reporting must never
//               read as zero errors.
//
// Swallowed like every other tick in this file: monitoring must never take the watchdog down.
// The website's runtime errors for the last hour, or an honest account of why there is no reading.
// The site pushes them (src/instrumentation.ts -> site_error_ingest -> public.error_events); this
// only counts. Three outcomes, never a made-up zero:
//   no ingest secret            the reporting path is not configured at all
//   no heartbeat in 24 h        the secret exists but no deployment has reported in, so a count of
//                               zero would be the ingest being dead, not the site being healthy
//   measured                    {count, window_minutes} — fn_it_detect decides what that means
const RUNTIME_WINDOW_MIN = 60;
async function siteRuntimeErrors(): Promise<Record<string, unknown>> {
  try {
    if (!(await sec('cred_site_error_ingest'))) {
      return { basis: 'unavailable', reason: 'app_secrets.cred_site_error_ingest is not set, so the website has no way to report its runtime errors and they were NOT checked' };
    }
    const since24 = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { count: ready, error: e1 } = await admin.from('error_events')
      .select('id', { count: 'exact', head: true })
      .eq('source', 'website').eq('kind', 'site_report_ready').gte('created_at', since24);
    if (e1) return { basis: 'unavailable', reason: 'public.error_events could not be read: ' + e1.message };
    if (!ready) {
      return { basis: 'unavailable', reason: 'the website has not reported in for 24 hours (no site_report_ready in public.error_events): SITE_ERROR_INGEST_SECRET may be missing from the Vercel project, so its runtime errors were NOT checked' };
    }
    const since = new Date(Date.now() - RUNTIME_WINDOW_MIN * 60_000).toISOString();
    const { count, error: e2 } = await admin.from('error_events')
      .select('id', { count: 'exact', head: true })
      .eq('source', 'website').eq('kind', 'runtime_error').gte('created_at', since);
    if (e2) return { basis: 'unavailable', reason: 'public.error_events could not be counted: ' + e2.message };
    // RETENTION RUNS WHERE THE ROWS ARE READ (22 Sep 2026). Nothing else deletes a website row, and
    // only the last hour and the last 24 h are ever read. Bounded at 2,000 rows a call by the
    // routine itself — a 50k batch delete forced a database restart on 21 Sep. Swallowed: a prune
    // that fails must never cost the tick its reading.
    try { await admin.rpc('fn_prune_website_error_events', { p_limit: 2000 }); } catch (_e) { /* the next tick prunes */ }
    return { basis: 'measured', count: count ?? 0, window_minutes: RUNTIME_WINDOW_MIN, reported_by: 'src/instrumentation.ts onRequestError -> site_error_ingest' };
  } catch (e) {
    return { basis: 'unavailable', reason: 'the runtime-error reading threw: ' + String((e as Error)?.message || e).slice(0, 200) };
  }
}

async function itDetectTick(): Promise<unknown> {
  const web: Record<string, unknown> = {
    probed_at: new Date().toISOString(),
    runtime_errors: await siteRuntimeErrors(),
  };
  try {
    const site = await sec('public_site_url');
    if (site) {
      const t0 = Date.now();
      try {
        const r = await fetch(site, { redirect: 'follow', signal: AbortSignal.timeout(20000) });
        web.home = { url: site, status: r.status, ms: Date.now() - t0 };
      } catch (e) {
        // A fetch that threw is the site being DOWN, and is reported with no status at all rather
        // than a made-up one, because fn_it_detect treats a missing status as unreachable.
        web.home = { url: site, error: String((e as Error)?.message || e).slice(0, 300), ms: Date.now() - t0 };
      }
    } else {
      web.home = { error: 'app_secrets.public_site_url is missing or empty, so the site was not probed' };
    }

    const [token, team, prj, prjName] = await Promise.all([
      sec('vercel_token'), sec('vercel_team_id'), sec('vercel_project_id'), sec('vercel_project'),
    ]);
    const project = prj || prjName;
    if (token && project) {
      const q = `projectId=${encodeURIComponent(project)}&target=production&limit=1`
              + (team ? `&teamId=${encodeURIComponent(team)}` : '');
      try {
        const r = await fetch(`https://api.vercel.com/v6/deployments?${q}`, {
          headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(20000),
        });
        const j = await r.json().catch(() => null);
        // deno-lint-ignore no-explicit-any
        const d = (j as any)?.deployments?.[0];
        if (r.ok && d) {
          web.deployment = { uid: d.uid, state: d.state ?? d.readyState, readyState: d.readyState,
                             created: d.created, url: d.url, target: d.target ?? 'production' };
        } else {
          // An unreadable deployments API is reported as a reading we could not take, NOT as READY.
          web.deployment = { basis: 'unavailable', status: r.status,
                             reason: 'Vercel deployments API returned ' + r.status + ': ' + JSON.stringify(j ?? {}).slice(0, 200) };
        }
      } catch (e) {
        web.deployment = { basis: 'unavailable', reason: 'Vercel deployments API unreachable: ' + String((e as Error)?.message || e).slice(0, 200) };
      }
    } else {
      web.deployment = { basis: 'unavailable', reason: 'app_secrets.vercel_token or vercel_project_id is missing, so the deployment was not checked' };
    }
  } catch (e) {
    web.probe_error = String((e as Error)?.message || e).slice(0, 300);
  }

  try {
    const { data, error } = await admin.rpc('fn_it_detect', { p_web: web, p_persist: true });
    if (error) return { ok: false, error: error.message, web };
    // deno-lint-ignore no-explicit-any
    const v = data as any;
    // The findings themselves are NOT returned into this response body: this endpoint is public
    // and secretless, and the findings name failing internals. The verdict is the summary; the
    // detail is in public.it_watch_finding for whoever owns delivery.
    return { worst: v?.worst, finding_count: v?.finding_count, persisted: v?.persisted };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// KEEP THE PORTAL'S FIVE COLD ISOLATES WARM (14 Sep 2026 e2e finding; reviewed and corrected same
// day). The customer Overview warms kyc, customer_api, customer_portal, project_api and messages_api
// together on every sign-in (CustomerPortal.tsx warmDashboard) — five separate Deno isolates, any
// one of which, cold, adds full V8-boot-plus-module-import latency on top of its query. This closes
// isolate eviction BETWEEN sign-ins; the portal's own warmDashboard already covers a single sign-in.
//
// THE FIRST VERSION OF THIS RELIED ON A 401. That is only confirmed harmless for kyc and
// customer_api; for customer_portal, project_api and messages_api an unauthenticated call could run
// real code before failing, and every one of the five would write a 'warn' row to agent_runs every
// ~15 minutes forever. Each of the five functions now checks `x-qd-warm: 1` as the very first thing
// in its handler — before auth, before any DB read — and returns 204 with no side effect at all.
// verify_jwt:true (customer_api, project_api, messages_api) still requires a signed JWT to pass the
// PLATFORM GATEWAY before the handler ever runs, so the service key travels alongside the warm
// header for those three; kyc and customer_portal (verify_jwt:false) do not need it and are sent it
// anyway for one code path instead of two. A 204 classifies 'ok' in observe.ts (see classify()), so
// none of this can be counted as a failure by any alerting the estate already runs.
//
// Piggybacks on this file's existing ~15min external trigger (.github/workflows/resilience-ping.yml)
// so no new schedule or SQL is needed. Every call is best-effort and swallowed; a warm-ping failure
// must never affect the watchdog's own health verdict.
async function warmPortal(): Promise<{ fn: string; ms: number; ok: boolean; region?: string | null }[]> {
  // The SUPPLIER journey's four joined 28 Sep 2026 (it_engineer): measured on the 24 Sep walk, each first
  // call to supplier_api, supplier_portal, supplier_pay and claim_lookup paid a 2.5-4.5 s isolate boot —
  // the landing-to-claim step and the Billing tab were almost entirely boot. Each answers x-qd-warm with
  // a 204 before auth or the database, exactly like the five above.
  const targets = ['kyc', 'customer_api', 'customer_portal', 'project_api', 'messages_api',
    'supplier_api', 'supplier_portal', 'supplier_pay', 'claim_lookup'];
  return Promise.all(targets.map(async (fn) => {
    const t0 = Date.now();
    try {
      // PINNED TO THE PORTAL'S REGION (28 Sep 2026, it_engineer). Unpinned, Supabase runs a function in
      // the region nearest the CALLER, and this caller is wherever the external cron entered, while
      // both portals pin ?forceFunctionRegion=ap-southeast-1 (src/lib/supaEnv.ts FN_REGION). Measured
      // from Dubai: the same x-qd-warm GET unpinned answered from ap-south-1, pinned from
      // ap-southeast-1 - separate isolates. So this ping kept isolates warm that no customer uses.
      const r = await fetch(FN + '/' + fn + '?forceFunctionRegion=ap-southeast-1', { method: 'GET',
        headers: { 'x-qd-warm': '1', Authorization: 'Bearer ' + Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')! },
        signal: AbortSignal.timeout(8000) });
      await r.body?.cancel().catch(() => {}); // release the connection; a 204 has nothing to read
      return { fn, ms: Date.now() - t0, ok: r.status === 204, region: r.headers.get('x-sb-edge-region') };
    } catch (e) { return { fn, ms: Date.now() - t0, ok: false }; }
  }));
}

// EVERY TICK THIS FUNCTION CAN RUN, BY NAME. The ORDER is not here any more — public.resilience_step
// holds each step's cadence and fn_resilience_tick_plan returns the order, stalest first (18 Sep 2026,
// it_engineer). It had to move: 25 steps on one wall clock in one hard-coded order meant the same tail
// lost every time the front ran long, and on 18 Sep at 06:45Z the tick hit its 110 s deadline exactly
// and the sanctions screen — 22nd of 25 — did not fire despite being due.
//
// What the list still carries, because these are real dependencies and not preferences:
//   * `nested` — the step returns one entry per job and each is judged on its own.
//   * `always` — it runs even past the deadline, because it delivers (the two drains).
//   * itdetect before it, and the outbox after everything that writes mail: expressed in the schedule
//     as place='last' for it/outbox/archive, which the plan appends after every planned step.
const STEP_RUN: Record<string, Omit<Step, 'name'>> = {
  digest: { run: digestTick },
  ratings: { run: ratingTick },
  backup: { run: backupTick },
  backupVerify: { run: dropboxVerifyTick },
  dropboxHealth: { run: dropboxHealthTick },
  vercelSnapshot: { run: vercelSnapshotTick },
  tableExport: { run: tableExportTick },
  backupPrune: { run: backupPruneTick },
  weekly: { run: accountantWeeklyTick },
  vat: { run: vatThresholdTick },
  ceoWeekly: { run: ceoWeeklyTick },
  ceoWeeklyReview: { run: ceoWeeklyReviewTick },
  ceoDecisions: { run: ceoDecisionsTick },
  ceoPlan: { run: ceoPlanTick },
  waSenderQuality: { run: waSenderQualityTick },
  openrouter: { run: openrouterMeterTick },
  ladder: { run: refundLadderTick },
  caseMemory: { run: caseMemoryEmbedTick },
  mlEmbed: { run: mlEmbedTick },
  learningMeasure: { run: learningMeasureTick },
  learningGroup: { run: learningGroupTick },
  learningDistil: { run: learningDistilTick },
  refunds: { run: accountantRefundTick },
  accountantDuties: { run: accountantDutiesTick },
  marketing: { run: () => kickDetached('marketing') },
  marketingChannels: { run: marketingChannelsTick },
  supportCampaignList: { run: supportCampaignListTick },
  whatsapp: { run: whatsappTick },
  itdetect: { run: itDetectTick },
  itduties: { run: itDutiesTick },
  itintegrations: { run: itIntegrationsTick },
  itscheduled: { run: itScheduledTick },
  itlater: { run: () => kickDetached('itlater') },
  specoffer: { run: specOfferTick },
  marketingOutreach: { run: marketingOutreachTick },
  deliveryCanary: { run: deliveryCanaryTick },
  seatClocks: { run: seatClocksTick },
  seatDuties: { run: seatDutiesTick },
  // customer_support's duty updates written by the model (founder_instruction 1339): detached, its own 120 s.
  supportVoice: { run: () => kickDetached('supportVoice') },
  // `nested` because it returns one entry per function it called: without it runSteps would ask
  // failureOf about the map itself, which has neither `ok` nor `status`, and a 500 from email_cron
  // would be invisible.
  orphans: { run: orphanTick, nested: true },
  orgtasks: { run: orgTaskTick },
  launchpath: { run: launchPathTick },
  it: { run: itEngineerAlertTick, always: true },
  outbox: { run: outboxTick, always: true },
  // Every conversation message gets its PDF within one beat (founder, 14 Sep 2026: the email is
  // printed to PDF and kept in "supabase and dropbox"). `always` since 18 Sep: it is a delivery step
  // exactly like the outbox, and it is the one the deadline was actually eating — the finding
  // duty:heartbeat:archive, "not run: the tick passed its 110s deadline", had been seen 27 times by
  // 07:17Z. A conversation without its PDF is lost work, not tidiness.
  archive: { run: archiveTick, always: true },
};

// THE TWO SLOW STEPS RUN DETACHED, IN THEIR OWN INVOCATION (12 Oct 2026, it_engineer).
// Measured on production that morning: `marketing` (ewma 54.5 s) timed out at its 55 s fetch on every run
// from 03:46 UTC - the marketing seat's twelve duties had grown from ~46 s to past 55 s, so the tick
// aborted the wait and recorded "Signal timed out." - and `itlater` cost 52-75 s inline. The plan admits
// its stalest step whatever it costs, so whichever of the two was stalest took most of the 70 s budget and
// `seatDuties` (6 s) was deferred tick after tick: the sales engineer's 15- and 30-minute duties did not
// start from 09:15 to 10:35 UTC.
// Now the tick only KICKS them: one authenticated POST to this same function with {detached: <name>}, which
// answers 202 at once and does the work under EdgeRuntime.waitUntil, with its own wall clock and its own
// timeout (DETACHED_MS, 120 s, raced over the whole run) instead of the tick's. resilience_step's last_ok_at and
// ewma for these two now record only the KICK; whether the work passed is the duty:detached_<name> findings. The tick's cost for each is the kick (~1 s), so neither can
// starve another step again, and whatever the marketing seat adds to its duties (lead sourcing, #1304)
// never runs inside the tick. The detached run settles its own failures as IT findings under duty
// detached_<name>, one per failing sub-step, closed when it passes. A detached call never writes the
// fn:resilience_ping observe row, so it can never make a dead scheduler look alive.
// 120 s for the run itself, raced in runDetached so a hung RPC is cut off with time left inside the ~150 s
// wall clock for fn_it_duty_settle to record it; the marketing fetch waits the same 120 s.
const DETACHED_MS = 120_000;
const DETACHED: Record<string, { run: (clock: StepClock) => Promise<unknown>; nested?: boolean }> = {
  marketing: { run: marketingTick },
  supportVoice: { run: supportVoiceTick },
  itlater: { run: itLaterDutiesTick, nested: true },
  heldReplay: { run: heldReplayTick },
  routineJudgements: { run: routineJudgementsTick },
};
async function kickDetached(name: string): Promise<unknown> {
  try {
    const r = await timedFetch(FN + '/resilience_ping', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY }, body: JSON.stringify({ detached: name }),
    }, 15_000);
    const j = await r.json().catch(() => null) as { started?: boolean } | null;
    return r.ok && j?.started === true ? { ok: true, started: true }
      : { ok: false, error: httpHopError('resilience_ping detached ' + name, r.status, j) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}
async function runDetached(name: string): Promise<void> {
  const d = DETACHED[name];
  let out: unknown;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const clock = stepClock();
  const cap = new Promise<unknown>((res) => { timer = setTimeout(() => res({ ok: false, error: 'detached ' + name + ' passed its ' + DETACHED_MS + ' ms limit' }), DETACHED_MS); });
  try { out = await Promise.race([d.run(clock), cap]); } catch (e) { out = { ok: false, error: String((e as Error)?.message || e) }; }
  finally { clearTimeout(timer); }
  // read the clock where the race left it: on an overrun, `running` is the step that was still going
  const timing = clock.snapshot();
  console.log(JSON.stringify({ detached_timing: name, ok: !failureOf(out), ...timing }));
  try { await admin.rpc('fn_it_duty_settle', { p_duty: 'detached_' + name, p_items: detachedItems(name, out, !!d.nested, timing) }); }
  catch (_e) { /* the next run settles again; a failed settle must not throw out of waitUntil */ }
}

// THE FALLBACK ORDER, used only when fn_resilience_tick_plan cannot be reached. A watchdog that stops
// watching because its scheduler is unavailable is worse than one that schedules badly, so the tick
// still runs every step, in declaration order, exactly as it did before this change.
const DECLARED_ORDER = Object.keys(STEP_RUN);

// THE DEADLINE, 95 s (was 110 s until 22 Sep 2026, it_engineer, CONN-02). It stays the BACKSTOP — the
// thing that catches a step whose real cost the plan's estimate got wrong — while the plan is what keeps
// the tick inside it. Two things changed together and neither works without the other:
//   * runSteps now bounds how long a step may still be WAITED ON (steps.ts, stepCapMs), not only when it
//     may begin. Before, a step admitted at 109.9 s could add its own 55 s timeout on top.
//   * 95 s + the 25 s reserve = a 120 s ceiling on the last step's return, and the three `always` drains
//     get a 10 s floor after that, so the worst tick is 130 s inside the 150 s platform cap. At 110 s the
//     same arithmetic gave 145 s, which leaves nothing for the liveness read and fn_it_duty_settle that
//     run after the steps.
// Raising it again moves the cliff rather than removing it; the plan's budget below is the knob to turn.
const DEADLINE_MS = 95_000;

// WHAT THE PLAN MAY COMMIT, against the 95 s backstop and its 120 s wait ceiling. The three
// place='last' drains are appended OUTSIDE it because they deliver (measured 9.4 s outbox + 5.4 s
// archive + ~1 s it a tick), so the
// arithmetic is 70 + 16 + the liveness read and fn_it_duty_settle ≈ 90 s inside 95 s. The every-tick
// set adds up to 57.4 s of expected cost, which fits with room for the hourly and daily steps to take
// turns in the gap. Measured mean tick before this change: 80.4 s over 24 h, max 140.9 s — the max is
// what this bounds, because before it nothing capped what one tick could commit to.
const PLAN_BUDGET_MS = 70_000;

// A FAILING STEP IS THE IT ENGINEER'S FINDING, NOT A LINE IN A RESPONSE NOBODY READS (15 Sep 2026).
// fn_it_duty_settle raises one finding per failing step (issue key duty:heartbeat:<step>, so a step
// failing every tick is ONE finding, seen_count rising) and closes it on the first tick the step passes.
// From there it goes round the IT engineer's loop like any other finding.
async function settleFailures(failing: Failure[]): Promise<unknown> {
  const items = failing.map((f) => ({
    item: f.name, title: 'resilience_ping step ' + f.name + ' failed: ' + f.error,
    owner_seat: 'it_engineer', subject: 'resilience_ping', blast: 'agent_facing', affected: 1,
    evidence: { step: f.name, error: f.error }, ...(f.carried ? { carried: true } : {}),
  }));
  try {
    const { data, error } = await admin.rpc('fn_it_duty_settle', { p_duty: 'heartbeat', p_items: items });
    return error ? { ok: false, error: error.message } : data;
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE SCHEDULER-DOWN PAGE GOES THROUGH THE FOUNDER-MAIL PATH (15 Sep 2026). It used to be posted to an
// alert_founder edge function that is not deployed: the 9 cron_down pages on record, the last on 14 Sep
// 15:49, were each a 404 that reached nobody. fn_notify_founder is the one path: founder_mail_policy
// allows kind platform_down to email, the dedupe key holds it to one delivery a day, and the send is
// adopted into customer_support's delivery loop. The outbox is drained again so the page leaves on this
// pass, since the drain above ran before the page existed.
async function pageSchedulerDown(ageMin: unknown): Promise<unknown> {
  const detail = 'SCHEDULER DOWN: the previous heartbeat was ' + (ageMin ?? 'an unknown number of') + ' minutes ago, over the '
    + '45-minute threshold. Everything that runs on the heartbeat (email, the seats\' duties, backups, the daily brief) stalls '
    + 'while it is down. This notice was sent by the heartbeat that did arrive.';
  try {
    const { data, error } = await admin.rpc('fn_notify_founder', {
      p_event: 'SCHEDULER DOWN — automation stalled', p_detail: detail, p_level: 'critical',
      p_kind: 'platform_down', p_dedupe_key: 'cron_down', p_owner_agent: 'customer_support',
    });
    if (error) return { ok: false, error: error.message };
    return { notice: data, flush: await outboxTick() };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// ASK POSTGRES WHAT TO RUN, IN WHAT ORDER. Returns the ordered step names, the due ones that did not
// fit, and any that have now been passed over four ticks running. If the plan cannot be read the tick
// falls back to running everything in declaration order — the behaviour it had before — and says so as a
// failing step, so an unreachable scheduler is a finding rather than a silent return to the old defect.
async function tickPlan(): Promise<{ run: string[]; deferred: string[]; starved: string[]; error?: string }> {
  try {
    const { data, error } = await admin.rpc('fn_resilience_tick_plan', { p_budget_ms: PLAN_BUDGET_MS });
    if (error) return { run: DECLARED_ORDER, deferred: [], starved: [], error: error.message };
    const d = data as { run?: unknown; deferred?: unknown; starved?: unknown } | null;
    const list = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
    const run = list(d?.run);
    if (run.length === 0) return { run: DECLARED_ORDER, deferred: [], starved: [], error: 'the plan named no steps' };
    return { run, deferred: list(d?.deferred), starved: list(d?.starved) };
  } catch (e) { return { run: DECLARED_ORDER, deferred: [], starved: [], error: String((e as Error)?.message || e) }; }
}

// WHO MAY RUN THE SWEEP. The service key as a Bearer token (compared in constant time against this
// function's own env), or an internal credential in x-qd-internal. Anything else is a liveness check.
function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
async function tickCaller(req: Request): Promise<boolean> {
  const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (sameSecret(bearer, SERVICE_KEY)) return true;
  // The scheduler's copy of the key may be the other format of the same project's secret key (a legacy
  // JWT here, an sb_secret_ key in Vercel, or the reverse). Ask the project itself: only a service key
  // can read app_secrets, which grants nothing to anon or authenticated.
  if (bearer.length >= 40) {
    try {
      const r = await timedFetch(Deno.env.get('SUPABASE_URL')! + '/rest/v1/app_secrets?select=key&limit=0', { headers: { apikey: bearer, Authorization: 'Bearer ' + bearer } });
      await r.body?.cancel();
      if (r.ok) return true;
    } catch (_e) { /* an unreachable check is not a pass */ }
  }
  const internal = req.headers.get('x-qd-internal');
  if (!internal) return false;
  return (await requireInternal(admin, internal, 'resilience_ping', 'resilience_ping header')).ok;
}
// Liveness for an anonymous monitor: one rate-limit row and a fixed answer. No step, no drain, no read.
// The limiter failing refuses (429), the same fail-closed rule as login_otp.
async function liveness(req: Request): Promise<Response> {
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
  let allowed = false;
  try { const { data, error } = await admin.rpc('rl_check', { p_key: 'resilience_ping_anon:' + ip, p_limit: 60, p_seconds: 3600 }); allowed = !error && data !== false; } catch (_e) { allowed = false; }
  if (!allowed) return J({ ok: false, error: 'rate_limited' }, 429);
  return J({ ok: true, live: true, sweep: 'not_run', why: 'the sweep runs only for an authenticated scheduler' });
}

// The liveness answer is decided OUTSIDE observe() on purpose: observe writes an fn:resilience_ping run
// row, and fn_cron_liveness and the scheduler-health readers take that row as proof a tick ran. An
// outsider pinging the URL must never make a dead scheduler look alive.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  if (!(await tickCaller(req))) return liveness(req);
  const body = await req.clone().json().catch(() => null) as { detached?: unknown } | null;
  const name = typeof body?.detached === 'string' ? body.detached : '';
  if (name) {
    if (!(name in DETACHED)) return J({ ok: false, error: 'no detached step ' + name }, 400);
    const work = runDetached(name);
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime;
    if (typeof rt?.waitUntil === 'function') { rt.waitUntil(work); return J({ ok: true, started: true, detached: name }, 202); }
    await work;
    return J({ ok: true, started: true, detached: name });
  }
  return sweep(req);
});
const sweep = observe('resilience_ping', async (req: Request) => {
  try {
    const t0 = Date.now();
    // Fired now, awaited last: nothing below depends on the portal being warm, so the five pings
    // run alongside the ticks instead of lengthening this already-sequential chain.
    const warmP = warmPortal();
    const plan = await tickPlan();
    // A NAME IN THE PLAN WITH NO RUNNER IS A FAILING STEP, NOT A SILENTLY DROPPED ONE. The schedule and
    // the code are two files; scripts/checks/every_tick_step_is_scheduled.mjs keeps them in step, and
    // this is what happens if it ever does not.
    // DE-DUPLICATED (independent review, ecc:typescript-reviewer, 18 Sep 2026). The old list was
    // authored once and could not repeat itself; a plan is data, and a name arriving twice would drain
    // the outbox or the WhatsApp queue twice in one tick. The Set is the whole guard.
    const steps: Step[] = [];
    const unknown: string[] = [];
    // A step public.duty_pause names is skipped and reported, never run (_shared/duty_pause.ts).
    const pause = await pausedDuties(admin);
    const pausedSteps: string[] = [];
    for (const name of new Set(plan.run)) {
      const s = STEP_RUN[name];
      if (s && pause.has('resilience_ping.' + name)) pausedSteps.push(name);
      else if (s) steps.push({ name, ...s }); else unknown.push(name);
    }
    const { results, failing, ms: stepMs } = await runSteps(steps, t0, DEADLINE_MS);
    for (const name of pausedSteps) results[name] = PAUSED;
    if (pause.error) failing.push({ name: 'duty_pause', error: pause.error });
    if (plan.error) failing.push({ name: 'plan', error: 'fn_resilience_tick_plan unusable, ran every step in declaration order: ' + plan.error });
    for (const name of unknown) failing.push({ name, error: 'the schedule names a step this function does not have' });
    // Deferring a step for one beat is the plan working. Being passed over four ticks running — an hour —
    // is the guarantee not holding, and that is the alarm that was missing when the sanctions screen
    // stopped running: it had to be noticed by a person reading a response.
    // A name that ran on THIS tick is not starved, whatever the plan said before it ran. The plan's own
    // `run` and `starved` are disjoint by construction, but a false ok:false here would poison that
    // step's ewma and raise a finding against a step that passed, so it is checked rather than assumed
    // (independent review, ecc:typescript-reviewer, 18 Sep 2026).
    for (const name of plan.starved) {
      if (name in stepMs || pause.has('resilience_ping.' + name)) continue;
      failing.push({ name, error: 'starved: due and not run for 4 ticks running' });
    }
    // Written back in ONE call. A deferred step stamps nothing, which is what makes it stalest next tick.
    // Written as a plain await in a try/catch rather than a .then/.catch chain: the chain's callback
    // parameters had no contextual type under `deno check` and failed CI with TS7006 twice over.
    let schedule: unknown;
    try {
      const { data, error: sErr } = await admin.rpc('fn_resilience_step_record',
        { p_rows: stepRows(stepMs, failing, plan.deferred) });
      schedule = sErr ? { ok: false, error: sErr.message } : data;
    } catch (e) { schedule = { ok: false, error: String((e as Error)?.message || e) }; }
    const warm = await warmP.catch(() => []);
    // Read cron liveness (plain SELECT; works while Postgres is up even if pg_cron stopped scheduling).
    const { data: live, error } = await admin.rpc('fn_cron_liveness');
    if (error) failing.push({ name: 'liveness', error: error.message });
    const healthy = live?.healthy === true;
    const ageMin = live?.newest_run_age_min ?? null;
    let page: unknown = null;
    if (!error && !healthy) {
      page = await pageSchedulerDown(ageMin);
      const f = failureOf(page);
      if (f) failing.push({ name: 'page', error: f });
    }
    // A step that failed on an earlier tick and was not due on this one is still failing (steps.ts,
    // carriedFailures). Read AFTER the record above, so this tick's own results are already stamped.
    try {
      const { data: st } = await admin.from('resilience_step').select('step,last_started_at,last_ok_at');
      if (Array.isArray(st)) failing.push(...carriedFailures(st as StepState[], stepMs, failing));
    } catch (_e) { /* a failed read carries nothing; this tick's own failures are still settled */ }
    const heartbeat = await settleFailures(failing);
    const failed = failing.map((f) => f.name);
    // `tick` is the whole schedule decision in one field: what ran, what was held for a beat, how long
    // each step took. It is what turns "the tick was slow" into "which step", without a second ledger.
    const tick = { ran: steps.map((s) => s.name), deferred: plan.deferred, ms: stepMs, total_ms: Date.now() - t0, schedule };
    if (error) return J({ ok: false, error: error.message, failing: failed, heartbeat, tick, ...results, warm }, 200);
    if (healthy) return J({ ok: true, healthy: true, newest_run_age_min: ageMin, failing: failed, heartbeat, tick, ...results, warm });
    return J({ ok: true, healthy: false, newest_run_age_min: ageMin, page, failing: failed, heartbeat, tick, ...results, warm });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
});
