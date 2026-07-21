// uptime_check v4 - checks live pages. Self-heals deploy-shaped failures by auto-redeploying once (silent),
// and only escalates to the founder (via alert_founder, which is severity-gated + branded) if it is STILL
// broken on the next run. Recovers silently. Cron-safe.
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
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
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

  const inbound = await sec('inbound_secret');
  if (!inbound) {
    try { await admin.from('agent_runs').insert({ agent: 'uptime', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { authorised: 0, secret_lookup_ok: 0 }, note: 'uptime_check refused every caller because inbound_secret is missing or empty in app_secrets. NO page checks ran, so an absence of site_down alerts right now means the monitor is blind, not that quotesdone.com is healthy.' }); } catch (_e) { /* */ }
    return J({ error: 'secret unavailable' }, 503);
  }
  if (body.__secret !== inbound) {
    try { await admin.from('agent_runs').insert({ agent: 'uptime', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { authorised: 0, bad_or_missing_secret: 1 }, note: 'uptime_check rejected an unauthenticated caller (403). Until 19 Jul 2026 a request with no __secret was ACCEPTED and could trigger a production redeploy of quotesdone.com, so this rejection may be a scanner probing the old hole. No checks ran and no redeploy was triggered.' }); } catch (_e) { /* */ }
    return J({ error: 'forbidden' }, 403);
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

    const deployShaped = fails.some((f) => /missing_marker|empty_body|http_5|http_404|fetch_error/.test(String(f.reason || '')));
    const canHeal = deployShaped && (Date.now() - lastHeal > 60 * 60e3);
    try { await admin.from('founder_alerts').insert({ level: canHeal ? 'info' : 'crit', event: 'site_down', detail: fails.length + ' failing check(s): ' + JSON.stringify(fails).slice(0, 400), channel: 'system' }); } catch (_e) { /* */ }

    if (canHeal) {
      try { await fetch(FN + '/deploy_next_preview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: inbound, target: 'production' }) }); } catch (_e) { /* */ }
      await setSec('uptime_last_autoheal', String(Date.now()));
      return J({ ok: false, self_heal: 'redeploy_triggered', failures: fails.length, fails });
    }

    const detail = fails.length + ' page(s) on quotesdone.com still failing' + (lastHeal ? ' AFTER an automatic redeploy' : '') + ': ' + JSON.stringify(fails).slice(0, 300) + '. This likely needs a code/deploy fix.';
    try { await fetch(FN + '/alert_founder', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: inbound, level: 'critical', event: 'Live site check failing', detail, dedupe_key: 'site_down' }) }); } catch (_e) { /* */ }
    return J({ ok: false, escalated: true, failures: fails.length, fails });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
