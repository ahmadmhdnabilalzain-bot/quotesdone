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
// The edge function does all the work — detect, then page the founder over HTTP. This route only
// has to hit it, so it holds no secrets.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const PING = 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/resilience_ping';

export async function GET(req: Request) {
  // Vercel signs cron invocations with CRON_SECRET when it is set. If it is not set the route
  // still works — this endpoint triggers a health check and returns a verdict, it mutates nothing
  // and leaks nothing, so an unauthenticated call is a wasted request rather than a risk.
  const secret = process.env.CRON_SECRET;
  if (secret && req.headers.get('authorization') !== `Bearer ${secret}`) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }
  try {
    const r = await fetch(PING, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
      signal: AbortSignal.timeout(30_000),
    });
    const body = await r.json().catch(() => ({}));
    // A non-ok verdict is reported as a 502 so the platform's own failure log shows it, rather
    // than the route returning 200 over a dead watchdog.
    const ok = r.ok && (body as { ok?: boolean })?.ok === true;
    return Response.json({ ok, upstream_status: r.status, upstream: body }, { status: ok ? 200 : 502 });
  } catch (e) {
    return Response.json({ ok: false, error: String((e as Error)?.message || e) }, { status: 502 });
  }
}
