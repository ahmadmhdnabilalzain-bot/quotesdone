// site_error_ingest — the website's runtime errors, written where the IT engineer can read them.
//
// WHY IT EXISTS (22 Sep 2026, SEATS-06). resilience_ping's IT detection tick hard-coded the
// website's runtime-error reading as {basis:'unavailable'}: "the website's runtime errors were NOT
// checked". Measured again this morning with the stored app_secrets.vercel_token (which reads
// /v6/deployments fine — it returned dpl_6EXpJgzBK927F68ibgkZSTBshCEv), EVERY candidate Vercel REST
// path for runtime logs or errors answers 404:
//   /v1/observability/errors, /v1/observability/runtime-errors, /v1/observability/logs,
//   /v1/projects/<id>/observability/errors, /v1/projects/<id>/runtime-logs,
//   /v1/deployments/<uid>/runtime-logs, /v1/errors, /v1/monitoring/metrics
// So polling cannot take this reading at all: the estate must be told, not ask. Next.js has a
// native hook for exactly this — instrumentation.ts `onRequestError`, which fires for every
// uncaught server error in the app — and src/instrumentation.ts posts here.
//
// THE READING MUST BE ABLE TO SAY "I AM NOT WIRED UP". A silent ingest and a healthy site both look
// like zero rows, which is the estate's own recorded lesson (zero cannot tell a dead guard from an
// idle system). So the site also posts kind='site_report_ready' from register() on every cold
// start, and resilience_ping reports basis:'unavailable' when no such heartbeat arrived in 24 h.
//
// SECRET. The site holds SITE_ERROR_INGEST_SECRET (Vercel env) and sends it in x-qd-site-secret;
// this function compares it with app_secrets.cred_site_error_ingest. Without it anyone could
// manufacture website faults and page the IT engineer through a public endpoint.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });

// Length-independent comparison: a timing oracle on a shared secret is cheap to close.
function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return J({ error: 'method_not_allowed' }, 405);
  const { data: row } = await admin.from('app_secrets').select('value').eq('key', 'cred_site_error_ingest').maybeSingle();
  const want = String(row?.value || '');
  if (!want) return J({ error: 'not_configured', detail: 'app_secrets.cred_site_error_ingest is empty' }, 503);
  if (!sameSecret(String(req.headers.get('x-qd-site-secret') || ''), want)) return J({ error: 'unauthorized' }, 401);

  // deno-lint-ignore no-explicit-any
  let b: any = null;
  try { b = await req.json(); } catch (_e) { return J({ error: 'bad_json' }, 400); }
  const kind = b?.kind === 'site_report_ready' ? 'site_report_ready' : 'runtime_error';
  const s = (v: unknown, n = 300) => (v == null ? null : String(v).slice(0, n));
  const { error } = await admin.from('error_events').insert({
    source: 'website',
    kind,
    severity: kind === 'runtime_error' ? 'error' : 'info',
    detail: {
      message: s(b?.message, 500), route: s(b?.route, 200), path: s(b?.path, 300),
      digest: s(b?.digest, 80), env: s(b?.env, 40), deployment: s(b?.deployment, 80),
      render_source: s(b?.render_source, 40), reported_at: new Date().toISOString(),
    },
  });
  if (error) return J({ ok: false, error: error.message }, 500);
  return J({ ok: true, kind });
});
