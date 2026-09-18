// resilience_ping — the EXTERNAL watchdog target that survives a total pg_cron outage.
// An external scheduler (GitHub Action / uptime service) hits this every ~15min. Because it is an
// HTTP-invoked edge function, it keeps working even if the Supabase pg_cron scheduler has stopped.
// If the previous heartbeat is over 45 minutes old (fn_cron_liveness), it pages the founder through
// fn_notify_founder (kind platform_down, one delivery a day) and drains the outbox so the page leaves now.
// Public + secretless by design (returns only liveness, counts and the names of failing steps) so any
// external monitor can wire it with just the URL.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { type Failure, failureOf, runSteps, type Step } from './steps.ts';
import { takeDutyReadings } from '../_shared/it_duty_readings.ts';
import { takeScheduledReadings } from '../_shared/it_scheduled_readings.ts';
import { takeUsageReadings, verifyRevisions } from '../_shared/it_duty_readings.ts';
import { runRestoreTable } from '../_shared/it_restore_drill.ts';
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
async function digestTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_daily_digest_tick');
    if (error) return { ok: false, error: error.message };
    return data;
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
async function archiveTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/conversation_archive', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, action: 'sweep', limit: 4 }), signal: AbortSignal.timeout(50000),
    });
    return { status: r.status, result: await r.json().catch(() => null) };
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

async function outboxTick(): Promise<unknown> {
  try {
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_outbox', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
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
async function ceoWeeklyTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_weekly_report_tick');
    if (error) return { ok: false, error: error.message };
    return data;
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

async function vatThresholdTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_accountant_vat_threshold_check', { p_notify: true });
    if (error) return { ok: false, error: error.message };
    return data;
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
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, mode: 'reconcile', limit: 20 }), signal: AbortSignal.timeout(55000),
    });
    const reconcile_run = { status: r.status, result: await r.json().catch(() => null) };
    // deno-lint-ignore no-explicit-any
    return { ...(data as any), reconcile_run, ...(r.ok ? {} : { ok: false, error: 'dropbox_backup reconcile answered HTTP ' + r.status }) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// DROPBOX IS CHECKED EVERY DAY (it_engineer, 15 Sep 2026): the login, a write/read/delete probe and
// the space used, once a Dubai day and two hours after a failed reading (fn_it_dropbox_health_due).
// Its own tick, never behind fn_it_backup_tick, so neither can stop the other. dropbox_backup records
// the reading itself; if the call never got that far (timeout, a 5xx from our own function), this
// records it as an internal failure so a silent probe is still a finding. Only the verdict comes back:
// this endpoint is public.
async function dropboxHealthTick(): Promise<unknown> {
  try {
    const { data: due, error } = await admin.rpc('fn_it_dropbox_health_due');
    if (error) return { ok: false, error: error.message };
    if (due !== true) return { due: false };
    let status = 0; let recorded: string | null = null; let why = '';
    try {
      const r = await fetch(FN + '/dropbox_backup', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
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
    const r = await fetch(FN + '/dropbox_backup', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, limit: 25 }), signal: AbortSignal.timeout(55000),
    });
    return { due: true, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// TWO FUNCTIONS THAT NOTHING CALLED (17 Sep 2026, it_engineer). email_cron and wa_templates_watch are
// deployed, owned and instrumented, and pg_cron — which used to call them — has been empty since
// 7 Sep. agent_runs held ONE row for each, both 9 Sep 07:10. email_cron reports the one thing
// send_outbox structurally cannot (a disabled mail system: nothing would invoke send_outbox to tell
// you it is off) and auto-detects Resend domain verification; wa_templates_watch flips
// wa_templates_ready when Meta approves, and WhatsApp is the founder's command channel.
//
// GATED IN POSTGRES, like backupTick: one RPC answers for both, so a tick where neither is due costs
// one round trip and no HTTP. email_cron is due only while email is NOT enabled (when it is, outboxTick
// below already drains every tick and email_cron would add nothing but a second flush);
// wa_templates_watch only while wa_templates_ready is not 'true', so it stops polling Twilio the moment
// approval lands. Measured 18 Sep: both flags are 'true', so both gates are shut and this step is the
// RPC alone. Each swallows its own error — a step that throws is a step the whole tick pays for.
async function orphanTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_resilience_orphan_steps_due');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const due = data as any;
    if (!due?.email_cron && !due?.wa_templates) return { due: false };
    const secret = await sec('cred_fn_resilience_ping');
    const call = async (slug: string) => {
      try {
        const r = await fetch(FN + '/' + slug, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ __secret: secret }), signal: AbortSignal.timeout(20000),
        });
        return { status: r.status, body: await r.json().catch(() => null) };
      } catch (e) { return { ok: false, error: String((e as Error)?.message || e).slice(0, 200) }; }
    };
    const out: Record<string, unknown> = {};
    if (due.email_cron) out.email_cron = await call('email_cron');
    if (due.wa_templates) out.wa_templates_watch = await call('wa_templates_watch');
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
      method: 'POST', headers: { 'Content-Type': 'application/json' },
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
      const r = await fetch(FN + '/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json' },
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
      .select('id', { count: 'exact', head: true }).eq('channel', 'whatsapp').eq('status', 'queued');
    if (!count) return { queued: 0 };
    const secret = await sec('cred_fn_resilience_ping');
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, limit: 25 }), signal: AbortSignal.timeout(30000),
    });
    return { queued: count, status: r.status, result: await r.json().catch(() => null) };
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
        method: 'POST', headers: { 'Content-Type': 'application/json' },
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
    const { data, error } = await admin.rpc('fn_it_duties', { p_r: await takeDutyReadings(sec) });
    if (error) return { ok: false, error: error.message };
    return { due: true, duties: Object.keys((data ?? {}) as Record<string, unknown>).length };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
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
    return { due: list, settled: Object.keys((data ?? {}) as Record<string, unknown>) };
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
async function itLaterDutiesTick(): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const rpc = async (fn: string, args?: Record<string, unknown>) => {
    const { data, error } = await admin.rpc(fn, args);
    if (error) throw new Error(fn + ': ' + error.message);
    return data;
  };
  const step = async (name: string, run: () => Promise<unknown>) => {
    try { out[name] = await run(); } catch (e) { out[name] = { ok: false, error: String((e as Error)?.message || e).slice(0, 300) }; }
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
  // Its own step, never behind fn_it_restore_table_due: a drill that stops completing is a finding.
  await step('restore_overdue', async () => rpc('fn_it_restore_table_overdue'));
  await step('restore_table', async () => {
    if ((await rpc('fn_it_restore_table_due')) !== true) return { due: false };
    const pick = await rpc('fn_it_restore_table_pick');
    await rpc('fn_it_restore_table_record', { p: await runRestoreTable(admin, pick) });
    return { due: true };
  });
  // The sales engineer's daily document duty, on this heartbeat because pg_cron is not coming back:
  // expiry reconcile and final notice, approved suppliers re-verified, 14-day incomplete registrations
  // closed (the_sales_engineer_closes_a_registration_left_incomplete_for_fourteen_days.sql). Counts only.
  await step('supplier_docs', async () => {
    if (!(((await rpc('fn_it_scheduled_due')) ?? []) as string[]).includes('supplier_docs')) return { due: false };
    const r = (await rpc('fn_sales_engineer_supplier_documents_tick')) as Record<string, unknown>;
    return { due: true, approved_rechecked: r?.approved_rechecked, registrations_closed: r?.registrations_closed };
  });
  return out;
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
//   runtime     NOT AVAILABLE to the stored token. /v1/projects/<id>/runtime-logs,
//               /v1/deployments/<uid>/runtime-logs and /v1/observability/runtime-logs all 404, and
//               the deployment `events` endpoints return build output only. So this reading is
//               passed as {basis:'unavailable'} and fn_it_detect reports that it did not look —
//               it is never allowed to read as "no runtime errors". Give the token runtime-log
//               scope, or attach a log drain, and swap the basis for a count; nothing else changes.
//
// Swallowed like every other tick in this file: monitoring must never take the watchdog down.
async function itDetectTick(): Promise<unknown> {
  const web: Record<string, unknown> = {
    probed_at: new Date().toISOString(),
    runtime_errors: {
      basis: 'unavailable',
      reason: 'no runtime-log endpoint is reachable with app_secrets.vercel_token (runtime-logs and observability both 404); the website\'s runtime errors were NOT checked',
    },
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
async function warmPortal(): Promise<{ fn: string; ms: number; ok: boolean }[]> {
  const targets = ['kyc', 'customer_api', 'customer_portal', 'project_api', 'messages_api'];
  return Promise.all(targets.map(async (fn) => {
    const t0 = Date.now();
    try {
      const r = await fetch(FN + '/' + fn, { method: 'GET',
        headers: { 'x-qd-warm': '1', Authorization: 'Bearer ' + Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')! },
        signal: AbortSignal.timeout(8000) });
      await r.body?.cancel().catch(() => {}); // release the connection; a 204 has nothing to read
      return { fn, ms: Date.now() - t0, ok: r.status === 204 };
    } catch (e) { return { fn, ms: Date.now() - t0, ok: false }; }
  }));
}

// THE ORDER THE TICKS RUN IN, ONE LIST (15 Sep 2026). Each name is the key its result has in the
// response. The order carries three rules: the ladder runs before the outbox and WhatsApp drains, so a
// chase written now leaves on this pass; DETECT BEFORE ALERTING, because itEngineerAlertTick reads the
// finding ledger and running it first would deliver the previous tick's picture; and the outbox drains
// AFTER everything that writes mail. `always` marks the two that deliver: they run even past the deadline.
// itlater is a map of the IT engineer's duties 19-24, each judged on its own (`nested`).
const STEPS: Step[] = [
  { name: 'digest', run: digestTick },
  { name: 'ratings', run: ratingTick },
  { name: 'backup', run: backupTick },
  { name: 'backupVerify', run: dropboxVerifyTick },
  { name: 'dropboxHealth', run: dropboxHealthTick },
  { name: 'tableExport', run: tableExportTick },
  { name: 'backupPrune', run: backupPruneTick },
  { name: 'weekly', run: accountantWeeklyTick },
  { name: 'vat', run: vatThresholdTick },
  { name: 'ceoWeekly', run: ceoWeeklyTick },
  { name: 'openrouter', run: openrouterMeterTick },
  { name: 'ladder', run: refundLadderTick },
  { name: 'refunds', run: accountantRefundTick },
  { name: 'accountantDuties', run: accountantDutiesTick },
  { name: 'whatsapp', run: whatsappTick },
  { name: 'itdetect', run: itDetectTick },
  { name: 'itduties', run: itDutiesTick },
  { name: 'itscheduled', run: itScheduledTick },
  { name: 'itlater', run: itLaterDutiesTick, nested: true },
  { name: 'specoffer', run: specOfferTick },
  // Before the outbox drain: email_cron queues nothing itself, but wa_templates_watch queues the
  // founder's "templates approved" mail, and that should leave on this pass rather than the next.
  // `nested` because it returns one entry per function it called: without it runSteps would ask
  // failureOf about the map itself, which has neither `ok` nor `status`, and a 500 from email_cron
  // would be invisible — the exact defect this whole change exists to end.
  { name: 'orphans', run: orphanTick, nested: true },
  { name: 'it', run: itEngineerAlertTick, always: true },
  { name: 'outbox', run: outboxTick, always: true },
  // Every conversation message gets its PDF within one beat (founder, 14 Sep 2026: the email is
  // printed to PDF and kept in "supabase and dropbox"). Called every tick, work or none, for the
  // same reason as the outbox: a heartbeat that beats only under load is not a heartbeat.
  { name: 'archive', run: archiveTick },
];

// THE DEADLINE. Measured 15 Sep 2026: the whole tick took 42-100 s (observe's 'slow run' notes, last
// two hours). Supabase documents an edge function's wall-clock limit as 150 s on the free plan and 400 s
// on paid; the tighter one is assumed. A step not started 110 s in is skipped and raised, leaving room
// for the drains (up to 20 s for the outbox) and the liveness read before the platform kills the tick.
const DEADLINE_MS = 110_000;

// A FAILING STEP IS THE IT ENGINEER'S FINDING, NOT A LINE IN A RESPONSE NOBODY READS (15 Sep 2026).
// fn_it_duty_settle raises one finding per failing step (issue key duty:heartbeat:<step>, so a step
// failing every tick is ONE finding, seen_count rising) and closes it on the first tick the step passes.
// From there it goes round the IT engineer's loop like any other finding.
async function settleFailures(failing: Failure[]): Promise<unknown> {
  const items = failing.map((f) => ({
    item: f.name, title: 'resilience_ping step ' + f.name + ' failed: ' + f.error,
    owner_seat: 'it_engineer', subject: 'resilience_ping', blast: 'agent_facing', affected: 1,
    evidence: { step: f.name, error: f.error },
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

Deno.serve(observe('resilience_ping', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  try {
    const t0 = Date.now();
    // Fired now, awaited last: nothing below depends on the portal being warm, so the five pings
    // run alongside the ticks instead of lengthening this already-sequential chain.
    const warmP = warmPortal();
    const { results, failing } = await runSteps(STEPS, t0, DEADLINE_MS);
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
    const heartbeat = await settleFailures(failing);
    const failed = failing.map((f) => f.name);
    if (error) return J({ ok: false, error: error.message, failing: failed, heartbeat, ...results, warm }, 200);
    if (healthy) return J({ ok: true, healthy: true, newest_run_age_min: ageMin, failing: failed, heartbeat, ...results, warm });
    return J({ ok: true, healthy: false, newest_run_age_min: ageMin, page, failing: failed, heartbeat, ...results, warm });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
}));
