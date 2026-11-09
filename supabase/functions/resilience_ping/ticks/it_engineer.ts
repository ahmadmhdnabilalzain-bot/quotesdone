// resilience_ping ticks owned by the it_engineer seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { failureOf, httpHopError, type StepClock, stepClock } from '../steps.ts';
import { takeDutyReadings } from '../../_shared/it_duty_readings.ts';
import { takeScheduledReadings } from '../../_shared/it_scheduled_readings.ts';
import { takeProviderReadings } from '../../_shared/it_provider_readings.ts';
import { runPostmasterStep, takePostmasterReading } from '../../_shared/it_postmaster_readings.ts';
import { takeUsageReadings, verifyRevisions } from '../../_shared/it_duty_readings.ts';
import { runRestoreTable } from '../../_shared/it_restore_drill.ts';
import { rotateAndSettle } from '../../_shared/it_rotate_by_api.ts';
import { PAUSED, pausedDuties } from '../../_shared/duty_pause.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { integrationItems } from '../../_shared/integration_watch.ts';
import { placementTick } from '../../_shared/inbox_placement.ts';
import { pollReplyInbox, pollTenantMailboxes, PROOF_LABEL, type SenderKind } from '../../_shared/m365_reply_inbox.ts';
import { launchPathAction, launchPathItem, probeLaunchPath } from '../../_shared/launch_path.ts';
import { advanceOpenDeliberations } from '../../_shared/seat_deliberation.ts';
import { liveDeliveryIO, sendHeldNotices } from '../../_shared/reasoned_delivery.ts';
import { customerReplyGate } from '../../_shared/ai_reply.ts';
import { envCoverage as vercelEnvCoverage, snapshot as vercelSnapshot } from '../../_shared/vercel_snapshot.ts';
import { FN, GATEWAY, SERVICE_KEY, admin, kickDetached, sec } from '../shared.ts';

// The IT engineer's half of the backup (founder, 14 Sep 2026: "i think the IT agent need to check
// such details yea?"): close verified refiles, run the 48-hour coverage watch, file the daily line
// to the CEO, and once a Dubai week re-check a random sample of Dropbox files.
// deno-lint-ignore no-explicit-any
export async function dropboxVerifyTick(): Promise<unknown> {
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
export async function vercelSnapshotTick(): Promise<unknown> {
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

export async function dropboxHealthTick(): Promise<unknown> {
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

export async function backupTick(): Promise<unknown> {
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

export async function orphanTick(): Promise<unknown> {
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
export async function tableExportTick(): Promise<unknown> {
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
export async function backupPruneTick(): Promise<unknown> {
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
export async function whatsappTick(): Promise<unknown> {
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
export async function waSenderQualityTick(): Promise<unknown> {
  try {
    const r = await fetch(FN + '/send_whatsapp', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...GATEWAY },
      body: JSON.stringify({ __secret: await sec('cred_fn_resilience_ping'), read_sender_quality: true }), signal: AbortSignal.timeout(8500),
    });
    return { ok: r.ok, status: r.status, result: await r.json().catch(() => null) };
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
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
export async function itDutiesTick(): Promise<unknown> {
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

export async function itIntegrationsTick(): Promise<unknown> {
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
export async function itScheduledTick(): Promise<unknown> {
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
export async function itLaterDutiesTick(clock: StepClock = stepClock()): Promise<Record<string, unknown>> {
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
export async function launchPathTick(): Promise<unknown> {
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

export async function itEngineerAlertTick(): Promise<unknown> {
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

export async function itDetectTick(): Promise<unknown> {
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
export async function warmPortal(): Promise<{ fn: string; ms: number; ok: boolean; region?: string | null }[]> {
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
