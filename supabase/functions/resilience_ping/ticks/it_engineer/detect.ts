// resilience_ping ticks owned by the it_engineer seat: the IT engineer alert tick and the detection tick (app and website). Moved out of ticks/it_engineer.ts unchanged (9 Nov 2026);
// the order the steps run in is still set in resilience_ping/index.ts (STEP_RUN).
import { admin, sec } from '../../shared.ts';

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
