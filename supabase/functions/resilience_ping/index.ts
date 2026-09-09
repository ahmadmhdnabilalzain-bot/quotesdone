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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok');
  try {
    // 0. The CEO's end-of-day digest, before any early return below.
    const digest = await digestTick();
    // 1. Read cron liveness (plain SELECT; works while Postgres is up even if pg_cron stopped scheduling).
    const { data: live, error } = await admin.rpc('fn_cron_liveness');
    if (error) return J({ ok: false, error: error.message }, 200);
    const healthy = live?.healthy === true;
    const ageMin = live?.newest_run_age_min ?? null;
    if (healthy) return J({ ok: true, healthy: true, newest_run_age_min: ageMin, digest });

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
    return J({ ok: true, healthy: false, newest_run_age_min: ageMin, paged, flushed, deduped, digest });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
});
