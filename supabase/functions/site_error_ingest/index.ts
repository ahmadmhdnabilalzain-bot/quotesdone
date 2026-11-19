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
// SECRET, in three places and each for its own reason. One value:
//   Vercel env SITE_ERROR_INGEST_SECRET      the site sends it in x-qd-site-secret
//   function env SITE_ERROR_INGEST_SECRET    this function compares it, without a database read
//   app_secrets.cred_site_error_ingest       resilience_ping reads THAT ROW only to know whether
//                                            reporting is configured at all, so the tick can say
//                                            "not wired up" instead of reporting zero errors
// Without the secret anyone could manufacture website faults through a public endpoint and page
// the IT engineer.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { J } from '../_shared/json_response.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

// Length-independent comparison: a timing oracle on a shared secret is cheap to close.
function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// THE SECRET IS AN ENV VAR, NOT A QUERY (hardening, 22 Sep 2026 review). This endpoint is public
// and anonymous: reading app_secrets before the secret is checked would hand every unauthenticated
// POST a database round trip, which is a free amplifier. SITE_ERROR_INGEST_SECRET is set on the
// function with the same value as app_secrets.cred_site_error_ingest (the resilience tick reads
// that row to know whether reporting is configured at all).
const WANT = (Deno.env.get('SITE_ERROR_INGEST_SECRET') || '').trim();

// A bounded throttle, in this isolate's memory: a site in a crash loop, or a caller who has the
// secret and a bug, must not be able to write unbounded rows between two prunes. 120 accepted
// posts a minute is far above any real error rate and far below anything that hurts.
const LIMIT_PER_MIN = 120;
let windowAt = 0, windowN = 0;
function throttled(): boolean {
  const m = Math.floor(Date.now() / 60_000);
  if (m !== windowAt) { windowAt = m; windowN = 0; }
  return ++windowN > LIMIT_PER_MIN;
}

// NOT CONFIGURED IS A FINDING, NOT A QUIET 503 (7 Oct 2026, stage-2 run fe7ba9c4). With the secret
// missing here AND on Vercel, the site's post() returns before sending and this function answers 503:
// zero website error rows, which reads exactly like a healthy site. A 503 now upserts ONE it_engineer
// finding (one issue_key, so it recurs rather than multiplies). The secret value is never generated or
// stored by an agent; the finding names where a human must set it.
const NOT_CONFIGURED_ISSUE = 'site_error_ingest_secret_not_set';
let raisedAt = 0;
async function raiseNotConfigured(): Promise<void> {
  if (Date.now() - raisedAt < 3_600_000) return; // at most once an hour per isolate: no write amplifier
  raisedAt = Date.now();
  try {
    const { error } = await admin.rpc('fn_it_engineer_finding_upsert', {
      p_issue_key: NOT_CONFIGURED_ISSUE,
      p_title: 'Website runtime errors are being dropped: SITE_ERROR_INGEST_SECRET is not set',
      p_where: 'supabase/functions/site_error_ingest (function secret) + Vercel project quotesdone-next env read by src/instrumentation.ts',
      p_blast: 'internal',
      p_affected: 0,
      p_evidence: {
        subject: 'site_error_ingest', owner_seat: 'it_engineer', demo: false,
        secret_name: 'SITE_ERROR_INGEST_SECRET',
        set_in: [
          'Supabase edge function secret SITE_ERROR_INGEST_SECRET (this project)',
          'Vercel env SITE_ERROR_INGEST_SECRET on quotesdone-next (production and preview), the same value',
          'app_secrets.cred_site_error_ingest, the same value (resilience_ping reads it to know reporting is configured)',
        ],
        why: 'without the function secret every report answers 503; without the Vercel env src/instrumentation.ts never posts',
      },
      p_raised_by: 'it_engineer',
    });
    if (error) console.error('site_error_ingest: finding could not be opened -', error.message);
  } catch (e) {
    console.error('site_error_ingest: finding could not be opened -', String((e as Error)?.message || e));
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return J({ error: 'method_not_allowed' }, 405);
  if (!WANT) { await raiseNotConfigured(); return J({ error: 'not_configured', detail: 'SITE_ERROR_INGEST_SECRET is not set on this function' }, 503); }
  if (!sameSecret(String(req.headers.get('x-qd-site-secret') || ''), WANT)) return J({ error: 'unauthorized' }, 401);
  if (throttled()) return J({ error: 'too_many_reports', detail: 'over ' + LIMIT_PER_MIN + ' reports in this minute' }, 429);

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
      render_source: s(b?.render_source, 40), user_agent: s(b?.user_agent, 200), reported_at: new Date().toISOString(),
    },
  });
  if (error) return J({ ok: false, error: error.message }, 500);
  return J({ ok: true, kind });
});
