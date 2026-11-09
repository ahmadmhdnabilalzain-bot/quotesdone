// resilience_ping ticks owned by the ceo seat. Moved out of index.ts unchanged (9 Nov 2026);
// the order they run in is still set in index.ts (STEP_RUN).
import { FN, GATEWAY, admin, sec } from '../shared.ts';

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
export async function digestTick(): Promise<unknown> {
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
export async function ceoWeeklyTick(): Promise<unknown> {
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
export async function ceoWeeklyReviewTick(): Promise<unknown> {
  try {
    const { data, error } = await admin.rpc('fn_ceo_weekly_review_tick');
    if (error) return { ok: false, error: error.message };
    // deno-lint-ignore no-explicit-any
    const t = data as any;
    if (!t?.pdf_pending || !t?.pdf_blocks || !t?.id) return t;
    return await renderPdfAndAttach(t, 'ceo/weekly_review', 'ceo_weekly_review', false, 'fn_ceo_weekly_review_attach_pdf');
  } catch (e) { return { ok: false, error: String((e as Error)?.message || e) }; }
}

// THE CEO'S TEN DECISION RULES, EVALUATED ON THE SAME HEARTBEAT (21 Sep 2026, ceo).
// public.ceo_decision held ten active rules and ceo_decision_log had never held a row: nothing in the
// database evaluated a rule. fn_ceo_decisions_evaluate is deterministic, writes one evidenced row per
// firing (deduplicated), emails nobody, and answers ok:false naming any active rule it cannot evaluate.
export async function ceoDecisionsTick(): Promise<unknown> {
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
export async function ceoPlanTick(): Promise<unknown> {
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
export async function renderPdfAndAttach(t: any, folder: string, fallbackName: string, strictGlyphs: boolean, attachRpc: string): Promise<unknown> {
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
