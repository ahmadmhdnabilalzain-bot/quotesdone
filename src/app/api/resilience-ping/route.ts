// The external resilience watchdog, moved off GitHub Actions.
//
// WHY IT MOVED. The watchdog pings resilience_ping every 15 minutes. On GitHub Actions that is a
// ten-second curl billed as a full minute, 2,880 minutes a month — 144% of the 2,000-minute
// allowance on its own, before a single pull request runs. The account hit 90% of the allowance
// in nine days and the checks that gate the build were competing with a curl for the remainder.
//
// WHY VERCEL PRESERVES THE PROPERTY. The failure mode this exists to catch is a TOTAL pg_cron
// outage: an in-cluster watchdog is itself a pg_cron job, so it cannot detect its own scheduler
// dying. Vercel's scheduler is entirely independent of Supabase, so it still catches that. GitHub
// keeps a once-daily run as a third-party cross-check, so a simultaneous Vercel AND Supabase
// failure is still seen by something outside both.
//
// The edge function does all the work — detect, then page the founder over HTTP. The route's only
// secret is the optional service-role key for the uptime rows below.
//
// THE CALLER MUST OUTWAIT THE FUNCTION IT CALLS (17 Sep 2026, it_engineer). This route waited 30 s
// for a function that declares DEADLINE_MS = 110_000 and runs its ticks in sequence, several with
// their own 55 s sub-timeouts. So the cron log here was permanently 502 and the GitHub cross-check
// permanently red — 4/4 failures 14-17 Sep, all `curl: (28) ... 30002 ms` — while the function
// itself ran 194 times in 48 h with 0 failures. A watchdog that cannot report success is a watchdog
// that cannot report failure either: a real Supabase outage would have looked exactly the same.
// 180 s is the function's 110 s deadline plus the drains that deliberately run past it.
// scripts/checks/resilience_ping_reports_every_tick.test.mjs fails if either number drops below it.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const maxDuration = 180;

import { SITE_ORIGINS } from '@/lib/domains';
import { SUPA_URL } from '@/lib/supaEnv';
import { isUp } from '@/lib/uptime';

const PING = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/resilience_ping';

// THE EXTERNAL UPTIME SLI (28 Sep 2026, it_engineer). Each run checks every public origin from
// OUTSIDE Supabase and writes one edge_health_probe row per origin, fn_key 'uptime:<url>'. The
// hourly seat_duty it_engineer.uptime_slo turns 30 days of these into uptime against 99.9%.
// Writing needs SUPABASE_SERVICE_ROLE_KEY in the Vercel server env (never NEXT_PUBLIC_); without it
// the checks still run and the response says uptime_recorded:false, so a missing key is visible.
// Named, not a literal: resilience_ping_reports_every_tick.test.mjs reads the ONE numeric AbortSignal.timeout
// in this file as the watchdog caller's wait.
const CHECK_MS = 15_000;
async function checkOrigins() {
  return Promise.all(SITE_ORIGINS.map(async (url) => {
    const t0 = Date.now();
    let status = 0; let err = '';
    try {
      const r = await fetch(url + '/', { redirect: 'manual', cache: 'no-store', signal: AbortSignal.timeout(CHECK_MS) });
      status = r.status; await r.body?.cancel();
    } catch (e) { err = String((e as Error)?.message || e); }
    return { url, status, ms: Date.now() - t0, up: isUp(status), err };
  }));
}

type Check = Awaited<ReturnType<typeof checkOrigins>>[number];

async function recordUptime(checks: Check[]) {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || !SUPA_URL || !checks.length) return false;
  const rows = checks.map((c) => ({
    fn_key: 'uptime:' + c.url, verdict: c.up ? 'up' : 'down',
    note: `http ${c.status} in ${c.ms} ms${c.err ? ': ' + c.err.slice(0, 200) : ''}`,
  }));
  const r = await fetch(`${SUPA_URL}/rest/v1/edge_health_probe`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify(rows), signal: AbortSignal.timeout(CHECK_MS),
  }).catch(() => null);
  return !!r?.ok;
}

export async function GET(req: Request) {
  // Vercel signs cron invocations with CRON_SECRET when it is set. If it is not set the route
  // still works — this endpoint triggers a health check and returns a verdict, it mutates nothing
  // and leaks nothing, so an unauthenticated call is a wasted request rather than a risk.
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get('authorization') !== `Bearer ${secret}`) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }
  // The origin checks run alongside the ping, so a slow watchdog never delays the 15-minute sample.
  const uptime = checkOrigins()
    .then(async (checks) => ({ checks, recorded: await recordUptime(checks) }))
    .catch(() => ({ checks: [] as Check[], recorded: false }));
  try {
    const r = await fetch(PING, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
      signal: AbortSignal.timeout(180_000),
    });
    const body = await r.json().catch(() => ({}));
    // A non-ok verdict is reported as a 502 so the platform's own failure log shows it, rather
    // than the route returning 200 over a dead watchdog.
    const ok = r.ok && (body as { ok?: boolean })?.ok === true;
    const u = await uptime;
    return Response.json({ ok, upstream_status: r.status, upstream: body, uptime: u.checks, uptime_recorded: u.recorded },
      { status: ok ? 200 : 502 });
  } catch (e) {
    const u = await uptime;
    return Response.json({ ok: false, error: String((e as Error)?.message || e), uptime: u.checks, uptime_recorded: u.recorded },
      { status: 502 });
  }
}
