// Public LIVENESS endpoint: "is the web process up and answering?" and nothing more.
//
// LIVENESS, NOT READINESS (it_engineer, 9 Nov 2026, launch audit "Health endpoint: PARTIAL").
// This route makes no database call and reads no secret, so it answers in about a millisecond and
// cannot fail because Supabase is slow. That is what an external uptime monitor, a load balancer or
// a container HEALTHCHECK wants: a cheap yes/no on the Next.js process itself. It says nothing
// about whether Postgres, the edge functions or the email provider work.
//
// THE DEEP CHECK IS A DIFFERENT ROUTE. /api/resilience-ping is authenticated (cron secret), calls
// resilience_ping in Postgres, and pages the founder when the scheduler or the database is down.
// It stays the readiness check; do not point a public monitor at it, and do not add a database
// call here, or a database blip would take the liveness probe down with it.
//
// The body carries no secrets: only a constant, the clock and the Vercel deployment id (null off
// Vercel, for example in Docker). Not cached anywhere. next-intl middleware does not run on
// /api/* (src/middleware.ts matcher lists only page paths), so the path is never localised.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export function GET() {
  return Response.json(
    {
      ok: true,
      service: 'quotesdone-web',
      time: new Date().toISOString(),
      deployment: process.env.VERCEL_DEPLOYMENT_ID ?? null,
    },
    { status: 200, headers: { 'Cache-Control': 'no-store' } },
  );
}
