// ai_health - lightweight AI-provider liveness monitor. Pings OpenRouter's free /key endpoint (no tokens spent)
// to confirm the model gateway + API key are reachable. Raises a DEDUPED operator alert (founder_alerts +
// admin notification) only on the transition INTO an outage (2 consecutive failures), and logs recovery when it
// returns. Consecutive-failure state persists in app_secrets.ai_health_fails. Secret-gated (verify_jwt=false).
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
async function setSec(k: string, v: string) { try { await admin.from('app_secrets').upsert({ key: k, value: v }, { onConflict: 'key' }); } catch (_e) { /* */ } }

Deno.serve(async (req) => {
  const started = new Date().toISOString();
  try {
    let body: any = {}; try { body = await req.json(); } catch (_e) { /* cron may send none */ }

    // SECURITY FIX 19 Jul 2026 ---------------------------------------------------------------
    // The gate used to read:
    //     if (body.__secret !== undefined && body.__secret !== await sec('inbound_secret')) -> 403
    // The reject branch only fired when a secret was SUPPLIED AND WRONG, so an empty POST ({})
    // skipped the check entirely. That mattered more here than on a read-only endpoint, because
    // an anonymous caller could reach setSec('ai_health_fails', ...) - a service-role WRITE into
    // app_secrets - and by hammering this endpoint while OpenRouter was healthy could drive the
    // counter to 0 and suppress the paging transition, hiding a real AI outage from the operator.
    // It could also manufacture a false 'ai_provider_down' page. Now fails CLOSED; the
    // ai_health_15min cron caller already passes the secret, so legitimate traffic is unaffected.
    const expected = await sec('inbound_secret');
    if (!expected) {
      try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { authorised: 0, secret_lookup_ok: 0 }, note: 'ai_health refused every caller because inbound_secret could not be read from app_secrets. The AI-provider liveness check did NOT run, so an absence of ai_provider_down alerts right now means the monitor is blind, not that the provider is healthy.' }); } catch (_e) { /* */ }
      return J({ error: 'secret unavailable' }, 503);
    }
    if (body.__secret !== expected) {
      try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { authorised: 0, bad_or_missing_secret: 1 }, note: 'ai_health rejected an unauthenticated caller (403). Before 19 Jul 2026 a request with no __secret was ACCEPTED and could write app_secrets.ai_health_fails, so a rejection here may be a scanner probing the old hole - or an internal caller never updated to send the secret. This run performed NO liveness check.' }); } catch (_e) { /* */ }
      return J({ error: 'forbidden' }, 403);
    }

    const key = await sec('openrouter_api_key');
    const admin_email = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
    const THRESHOLD = 2; // consecutive failures before we page

    let ok = false; let detail = '';
    if (!key) { detail = 'no openrouter_api_key configured'; }
    else {
      try {
        const ctrl = new AbortController(); const tt = setTimeout(() => ctrl.abort(), 8000);
        const r = await fetch('https://openrouter.ai/api/v1/key', { headers: { 'Authorization': 'Bearer ' + key }, signal: ctrl.signal });
        clearTimeout(tt);
        ok = r.ok; if (!ok) detail = 'HTTP ' + r.status + ' from OpenRouter /key';
      } catch (e) { detail = 'fetch error: ' + String((e as Error)?.message || e).slice(0, 140); }
    }

    const prior = parseInt((await sec('ai_health_fails')) || '0', 10) || 0;

    // record a heartbeat run (best-effort)
    try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: ok ? 'ok' : 'error', counts: { authorised: 1, consecutive_fails: ok ? 0 : prior + 1, detail }, note: ok ? 'ai_health confirmed the OpenRouter gateway and API key are reachable. AI-dependent agents are operating normally.' : ('ai_health could not reach the AI provider (' + detail + '). This is failure ' + (prior + 1) + ' in a row; paging happens at ' + THRESHOLD + '. AI-dependent steps are degraded and intake is on keyword fallback.') }); } catch (_e) { /* */ }

    if (ok) {
      if (prior >= THRESHOLD) {
        try { await admin.from('founder_alerts').insert({ level: 'info', event: 'ai_recovered', detail: 'AI provider (OpenRouter) is reachable again after ' + prior + ' failed checks.', channel: 'system' }); } catch (_e) { /* */ }
        try { await admin.from('notifications').insert({ type: 'ai_recovered', to_email: admin_email, to_role: 'admin', channel: 'email', subject: 'AI provider recovered', body: 'The AI model gateway (OpenRouter) is reachable again. Agents can resume automatically. Any queued jobs will drain on their next scheduled run.', status: 'queued' }); } catch (_e) { /* */ }
      }
      await setSec('ai_health_fails', '0');
      return J({ ok: true, healthy: true, recovered: prior >= THRESHOLD });
    }

    const fails = prior + 1;
    await setSec('ai_health_fails', String(fails));
    if (fails === THRESHOLD) {
      try { await admin.from('founder_alerts').insert({ level: 'crit', event: 'ai_provider_down', detail: 'AI provider (OpenRouter) unreachable on ' + fails + ' consecutive checks — ' + detail + '. Agents (matching, comparison, intake reasoning) are degraded; jobs are preserved and will auto-retry on recovery. Intake keeps working on keyword fallback.', channel: 'system' }); } catch (_e) { /* */ }
      try { await admin.from('notifications').insert({ type: 'ai_provider_down', to_email: admin_email, to_role: 'admin', channel: 'email', subject: 'AI provider appears DOWN', body: 'The AI model gateway (OpenRouter) has failed ' + fails + ' consecutive health checks (' + detail + ').\n\nWhat this means: AI-dependent steps (supplier matching, quote comparison, intake reasoning) are paused. Customer intake still works on the keyword fallback, and all in-flight jobs are preserved — they will be routed automatically once the provider recovers. No customer or supplier sees a raw error.\n\nWhat to do: usually nothing — this self-recovers. If it persists, check the OpenRouter status page and the API key limit in the OS.', status: 'queued' }); } catch (_e) { /* */ }
    }
    return J({ ok: true, healthy: false, consecutive_fails: fails, paged: fails === THRESHOLD, detail });
  } catch (e) {
    try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { unhandled_exception: 1 }, note: 'ai_health threw an unhandled exception and returned 500: ' + String((e as Error)?.message || e).slice(0, 200) + ' — no liveness verdict was produced, so silence from this monitor does not mean the AI provider is healthy.' }); } catch (_e2) { /* */ }
    return J({ error: String((e as Error)?.message || e) }, 500);
  }
});
