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
import { observe } from '../_shared/observe.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { carriedFailures, detachedItems, type Failure, failureOf, runSteps, type Step, type StepClock, stepClock, type StepState, stepRows } from './steps.ts';
import { PAUSED, pausedDuties } from '../_shared/duty_pause.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { accountantDutiesTick, accountantRefundTick, accountantWeeklyTick, openrouterMeterTick, refundLadderTick, vatThresholdTick } from './ticks/accountant.ts';
import { ceoDecisionsTick, ceoPlanTick, ceoWeeklyReviewTick, ceoWeeklyTick, digestTick } from './ticks/ceo.ts';
import { ratingTick, seatClocksTick, supportCampaignListTick, supportVoiceTick } from './ticks/customer_support.ts';
import { backupPruneTick, backupTick, dropboxHealthTick, dropboxVerifyTick, itDetectTick, itDutiesTick, itEngineerAlertTick, itIntegrationsTick, itLaterDutiesTick, itScheduledTick, launchPathTick, orphanTick, tableExportTick, vercelSnapshotTick, waSenderQualityTick, warmPortal, whatsappTick } from './ticks/it_engineer.ts';
import { marketingChannelsTick, marketingOutreachTick, marketingTick } from './ticks/marketing.ts';
import { archiveTick, caseMemoryEmbedTick, heldReplayTick, learningDistilTick, learningGroupTick, learningMeasureTick, mlEmbedTick, orgTaskTick, outboxTick, routineJudgementsTick, seatDutiesTick } from './ticks/platform.ts';
import { deliveryCanaryTick, specOfferTick } from './ticks/sales_engineer.ts';
import { DETACHED_MS, J, SERVICE_KEY, admin, kickDetached } from './shared.ts';

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
const DETACHED: Record<string, { run: (clock: StepClock) => Promise<unknown>; nested?: boolean }> = {
  marketing: { run: marketingTick },
  supportVoice: { run: supportVoiceTick },
  itlater: { run: itLaterDutiesTick, nested: true },
  heldReplay: { run: heldReplayTick },
  routineJudgements: { run: routineJudgementsTick },
};
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
