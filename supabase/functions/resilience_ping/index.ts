// resilience_ping — the EXTERNAL watchdog target that survives a total pg_cron outage.
// An external scheduler (GitHub Action / uptime service) hits this every ~15min. Because it is an
// HTTP-invoked edge function, it keeps working even if the Supabase pg_cron scheduler has stopped.
// If no cron job has run in >20min (scheduler dead), it pages the founder DIRECTLY over HTTP
// (alert_founder -> WhatsApp) and force-flushes the outbox, so the alert escapes even with pg_cron down.
// Public + secretless by design (returns only liveness; pages only when genuinely down, deduped 30min)
// so any external monitor can wire it with just the URL.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
async function sec(k: string): Promise<string> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }

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

// THE DROPBOX BACKUP HANGS HERE FOR THE THIRD TIME, AND FOR THE SAME REASON.
// The founder, 9 Sep 2026: the sales engineer "is responsible about the organized folders back up in
// dropbox". A daily backup needs a schedule, and pg_cron is not one any more — cron.job holds a
// single inactive row. So the daily-ness lives in Postgres, where Asia/Dubai is a real timezone:
// fn_dropbox_backup_due returns due:true at most once per local day, plus whenever a previous sweep
// left rows in the queue, so a backlog drains instead of waiting for tomorrow.
// dropbox_backup itself is idempotent — fn_enqueue_doc_backups is ON CONFLICT DO NOTHING and only
// pending/error rows are uploaded — so a duplicate call costs one wasted invocation, never a
// duplicate file. Swallowed like the other two: a backup must never take the watchdog down.
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
    if (aerr) return { ...t, pdf_error: err, attach_error: aerr.message };
    return { ...t, pdf_blocks: undefined, delivery: att };
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  try {
    // 0. The CEO's end-of-day digest, before any early return below.
    const digest = await digestTick();
    const ratings = await ratingTick();
    const backup = await backupTick();
    const weekly = await accountantWeeklyTick();
    const openrouter = await openrouterMeterTick();
    const whatsapp = await whatsappTick();
    // 1. Read cron liveness (plain SELECT; works while Postgres is up even if pg_cron stopped scheduling).
    const { data: live, error } = await admin.rpc('fn_cron_liveness');
    if (error) return J({ ok: false, error: error.message }, 200);
    const healthy = live?.healthy === true;
    const ageMin = live?.newest_run_age_min ?? null;
    if (healthy) return J({ ok: true, healthy: true, newest_run_age_min: ageMin, digest, ratings, backup, weekly, openrouter, whatsapp });

    // 2. Scheduler appears DOWN. Dedupe to once per 30min via an app_secrets timestamp.
    const nowMs = Date.now();
    const lastRaw = await sec('cron_down_last_alert');
    const lastMs = lastRaw ? Date.parse(lastRaw) : 0;
    const deduped = lastMs && (nowMs - lastMs) < 30 * 60 * 1000;
    let paged = false, flushed = false;
    if (!deduped) {
      const iso = new Date(nowMs).toISOString();
      await admin.from('app_secrets').upsert({ key: 'cron_down_last_alert', value: iso }, { onConflict: 'key' });
      const secret = await sec('cred_fn_resilience_ping');
      const detail = 'SCHEDULER DOWN: no pg_cron job has run in ' + (ageMin ?? 'an unknown number of') + ' minutes. All scheduled automation (email, invites, matching follow-ups, autonomy sweep, daily brief) is stalled until the scheduler is restored. This alert reached you via the external watchdog.';
      // Page directly over HTTP (independent of pg_cron/pg_net). WhatsApp sends immediately inside alert_founder.
      try {
        const r = await fetch(FN + '/alert_founder', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, event: 'SCHEDULER DOWN — automation stalled', level: 'critical', kind: 'platform_down', dedupe_key: 'cron_down', detail }), signal: AbortSignal.timeout(20000) });
        paged = r.ok;
      } catch (_e) { /* fall through */ }
      // Force-flush the outbox so the alert email escapes even though pg_cron can't drain it.
      try {
        await fetch(FN + '/send_outbox', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, limit: 20 }), signal: AbortSignal.timeout(20000) });
        flushed = true;
      } catch (_e) { /* best effort */ }
    }
    return J({ ok: true, healthy: false, newest_run_age_min: ageMin, paged, flushed, deduped, digest, ratings, backup, weekly, openrouter, whatsapp });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
});
