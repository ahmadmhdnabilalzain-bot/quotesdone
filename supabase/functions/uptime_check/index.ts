// uptime_check v5 - checks live pages and TELLS A HUMAN. It does not deploy anything. Escalates via
// alert_founder (severity-gated + branded) with what was detected. Recovers silently. Cron-safe.
//
// SAFETY FIX 27 Jul 2026 -------------------------------------------------------------------------
// WHAT WAS WRONG: v4 "self-healed" a deploy-shaped failure by POSTing deploy_next_preview with
// target:'production'. That meant a 12s timeout, a 502 from the edge, or one flaky DNS lookup - any
// transient blip - republished WHATEVER happened to be sitting in qd_deploy_src to the live site,
// unreviewed, with no human in the loop, and did it silently (the founder_alerts row was logged at
// level 'info' precisely because the robot thought it had it handled). A monitor that fixes things
// by pushing code turns a network hiccup into a release. Since the Stripe account went live today
// that is a paying-customer-facing release triggered by packet loss.
// WHY THIS FIX: the auto-deploy is gone entirely. A failing page is now always a crit alert to the
// founder describing exactly what was detected and whether it looks deploy-shaped; republishing is a
// human decision made after looking at the pending source. Nothing here can deploy any more.
//
// SECURITY FIX 19 Jul 2026 ---------------------------------------------------------------------
// The gate used to read:
//     if (body.__secret !== undefined && body.__secret !== (await sec('inbound_secret'))) -> 403
// The reject branch only fired when a secret was SUPPLIED AND WRONG, so a bare POST with no body
// - or any GET - skipped the check entirely and ran with full authority. That was not a read-only
// information leak: an unauthenticated caller could reach the self-heal branch and trigger a
// PRODUCTION REDEPLOY of quotesdone.com via deploy_next_preview, write app_secrets
// (uptime_last_autoheal), insert founder_alerts, and cause critical alert emails to be sent. A
// loop of empty POSTs was a denial-of-service against the live site's deployment pipeline.
//
// Now fails CLOSED, and also rejects when the stored secret is missing or empty rather than
// comparing against a falsy value. The uptime cron caller already passes __secret, so legitimate
// traffic is unchanged.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
async function setSec(k: string, v: string) { try { await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' }); } catch (_e) { /* */ } }
const SITE = 'https://quotesdone.com';
// path -> a marker that must appear in the SSR HTML when the page is healthy (kept broad to avoid false positives)
const CHECKS: [string, string][] = [
  ['/', 'QuotesDone'],
  ['/me', 'QuotesDone'],
  ['/portal', 'QuotesDone'],
  ['/services/', 'Services'],
  ['/ar/', 'QuotesDone'],
  ['/terms/', 'Terms'],
];
Deno.serve(async (req) => {
  const started = new Date().toISOString();
  let body: any = {}; try { body = await req.json(); } catch (_e) { /* a GET or empty POST lands here - and must NOT be treated as authorised */ }

  // AUDIT 9.5 / WI-001 (3 Aug 2026). PILOT FUNCTION for scoped internal credentials.
  //
  // This used to compare body.__secret against the single shared app_secrets.inbound_secret - the
  // same string that authenticates 43 cron jobs and 42 other edge functions. The comparison itself
  // was correct and fail-closed after the 19 Jul fix; the problem is what it compared against.
  //
  // requireInternal() asks the database instead (fn_internal_auth), which:
  //   * accepts the new per-context credential AND, during the migration window, the legacy shared
  //     secret - so the existing cron keeps working unchanged until it is moved;
  //   * checks that the presented credential is SCOPED to 'uptime_check' specifically. The
  //     cron.monitoring credential can call this and ai_health, and nothing else. The shared secret
  //     could call everything, which is the property being removed;
  //   * records who called. Until now every call authenticated by that string was indistinguishable
  //     in the logs, so a leak could not be scoped.
  //
  // Still fails closed, and now also when the verifier itself is unreachable.
  const auth = await requireInternal(admin, body.__secret, 'uptime_check');
  if (!auth.ok) {
    try {
      await admin.from('agent_runs').insert({ agent: 'uptime', started_at: started, finished_at: new Date().toISOString(), status: 'error',
        counts: { authorised: 0, refused: 1 },
        note: auth.status === 503
          ? 'uptime_check refused every caller because the internal credential verifier could not be reached. NO page checks ran, so an absence of site_down alerts right now means the monitor is blind, not that quotesdone.com is healthy.'
          : 'uptime_check rejected a caller with no valid internal credential (403). Until 19 Jul 2026 a request with no __secret was ACCEPTED and could trigger a production redeploy of quotesdone.com, so this may be a scanner probing the old hole. The reason for the refusal is in internal_credential_audit. No checks ran and no redeploy was triggered.' });
    } catch (_e) { /* */ }
    return J({ error: auth.error, message: auth.message }, auth.status);
  }

  const fails: any[] = [];
  for (const [path, marker] of CHECKS) {
    try {
      const ctrl = new AbortController(); const tt = setTimeout(() => ctrl.abort(), 12000);
      const r = await fetch(SITE + path, { headers: { 'User-Agent': 'QuotesDone-Uptime/1.0' }, signal: ctrl.signal });
      clearTimeout(tt);
      const txt = await r.text();
      if (!r.ok) fails.push({ path, reason: 'http_' + r.status });
      else if (marker && !txt.includes(marker)) fails.push({ path, reason: 'missing_marker', marker });
      else if (txt.length < 500) fails.push({ path, reason: 'empty_body', bytes: txt.length });
    } catch (e) { fails.push({ path, reason: 'fetch_error', detail: String((e as Error)?.message || e).slice(0, 120) }); }
  }
  try {
    try { await admin.from('agent_runs').insert({ agent: 'uptime', started_at: started, finished_at: new Date().toISOString(), status: fails.length ? 'error' : 'ok', counts: { authorised: 1, checks: CHECKS.length, failures: fails.length, detail: fails } }); } catch (_e) { /* */ }
    const lastHeal = Number((await sec('uptime_last_autoheal')) || '0');

    if (!fails.length) {
      if (lastHeal && (Date.now() - lastHeal) < 2 * 3600e3) { try { await admin.from('founder_alerts').insert({ level: 'info', event: 'uptime_recovered', detail: 'Site healthy again after auto-remediation.', channel: 'logged' }); } catch (_e) { /* */ } await setSec('uptime_last_autoheal', '0'); }
      return J({ ok: true, checks: CHECKS.length, failures: 0 });
    }

    // FIX 27 Jul 2026: deployShaped is now purely DESCRIPTIVE - it tells the founder what the failure
    // looks like. It used to gate `canHeal`, which fired a production deploy of qd_deploy_src and
    // downgraded this alert to 'info' so nobody was told. A failing page is always crit now.
    const deployShaped = fails.some((f) => /missing_marker|empty_body|http_5|http_404|fetch_error/.test(String(f.reason || '')));
    try { await admin.from('founder_alerts').insert({ level: 'crit', event: 'site_down', detail: fails.length + ' failing check(s): ' + JSON.stringify(fails).slice(0, 400), channel: 'system' }); } catch (_e) { /* */ }

    // FIX 27 Jul 2026: the auto-redeploy that used to sit here is DELETED, not disabled - a monitor
    // must never publish code. What replaces it is a description of what was detected, so the founder
    // can decide whether qd_deploy_src is even the right thing to republish.
    const detail = fails.length + ' page(s) on quotesdone.com are failing: ' + JSON.stringify(fails).slice(0, 300)
      + (deployShaped ? ' The failures look deploy-shaped (missing marker / empty body / 5xx / 404 / fetch error), which can also just be a transient network blip - re-run the check before acting.' : ' The failures do not look deploy-shaped.')
      + ' NOTE: uptime_check no longer auto-redeploys (removed 27 Jul 2026, it republished unreviewed source on transient errors). If a republish is genuinely the fix, review qd_deploy_src and publish deliberately from the OS.';
    // AUDIT 9.5, OUTBOUND SIDE - still on the legacy shared secret, deliberately.
    // This function is both a callee (gated above by requireInternal) and a caller. Moving the
    // OUTBOUND hop needs alert_founder to accept the verifier too, and needs this function to hold
    // a credential scoped to ['alert_founder']. That is the next step in the caller-by-caller order,
    // not this one. Changing both ends at once is precisely the big-bang swap WI-001 warns against.
    // Until then this call is authenticated by the legacy credential - which is now COUNTED, so it
    // shows up in v_internal_credential_health as a reason the shared secret is still in use.
    const outbound = await sec('cred_fn_to_alert_founder');
    try { await fetch(FN + '/alert_founder', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: outbound, level: 'critical', event: 'Live site check failing', detail, dedupe_key: 'site_down' }) }); } catch (_e) { /* */ }
    return J({ ok: false, escalated: true, failures: fails.length, fails });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
