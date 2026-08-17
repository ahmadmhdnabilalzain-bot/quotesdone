// ai_health - lightweight AI-provider liveness monitor. Pings OpenRouter's free /key endpoint (no tokens spent)
// to confirm the model gateway + API key are reachable. Raises a DEDUPED operator alert (founder_alerts +
// admin notification) only on the transition INTO an outage (2 consecutive failures), and logs recovery when it
// returns. Consecutive-failure state persists in app_secrets.ai_health_fails. Secret-gated (verify_jwt=false).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { paidProviderGate } from '../_shared/paid_gate.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
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
    // AUDIT 9.5 (3 Aug 2026): the "is the secret row even there" pre-check is gone. It existed to
    // fail closed when app_secrets could not be read, and requireInternal now does that properly —
    // it returns 503 when the verifier cannot answer for ANY reason, not just a missing row. The
    // pre-check was also the last thing in this function reading the shared secret.
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'ai_health');
    if (!__auth.ok) {
      try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: 'error', counts: { authorised: 0, bad_or_missing_secret: 1 }, note: 'ai_health rejected an unauthenticated caller (403). Before 19 Jul 2026 a request with no __secret was ACCEPTED and could write app_secrets.ai_health_fails, so a rejection here may be a scanner probing the old hole - or an internal caller never updated to send the secret. This run performed NO liveness check.' }); } catch (_e) { /* */ }
      return J({ error: 'forbidden' }, 403);
    }

    const key = await sec('openrouter_api_key');
    const admin_email = (await sec('admin_emails') || 'management@quotesdone.com').split(',')[0].trim();
    const THRESHOLD = 2; // consecutive failures before we page

    // ZERO-COST MODE (16 Aug 2026, Phase C correction 9). The founder holds every OpenRouter route
    // open-circuit until he releases it, and this job hit https://openrouter.ai/api/v1/key every
    // fifteen minutes regardless - six outbound requests to the provider inside a 37-minute Phase C
    // audit window. The calls were free (/key is metadata, not inference) but the boundary was "no
    // outbound request to OpenRouter", and a caller that never consults the hold is exactly the
    // shape that lets a paid one through later.
    //
    // Cost governance is not removed: while the hold is on, the check reports from the state the
    // database already holds. It does NOT fall back to another key, and it does not guess.
    let ok = false; let detail = ''; let skipped = false;
    // KERNEL K12: one authority, asked through the shared fail-closed client. A throw, a null, a
    // malformed shape and an explicit refusal all arrive here as allowed=false with a named rule.
    const gate = await paidProviderGate(admin, 'openrouter/metadata');
    const allowed = gate.allowed;
    const envHold = ['1', 'true', 'yes', 'on'].includes(
      String(Deno.env.get('NO_PAID_AI') ?? Deno.env.get('OPENROUTER_DISABLED') ?? '').toLowerCase());

    if (!allowed || envHold) {
      skipped = true;
      const { data: cached } = await admin.rpc('fn_os_provider_state_cached');
      const c = (cached ?? {}) as Record<string, unknown>;
      // Not "ok" in the sense of "the provider answered" - ok here means the estate is in the state
      // the founder asked for. Saying otherwise would page someone for a deliberate hold.
      ok = true;
      detail = 'skipped_due_to_zero_cost_mode: ' + String(c.routes_held ?? '?') + '/'
             + String(c.routes_total ?? '?') + ' routes held until ' + String(c.held_until ?? 'unknown')
             + '; key_present=' + String(c.key_present) + '; no request was made to any paid provider';
    } else if (!key) {
      detail = 'no openrouter_api_key configured';
    } else {
      try {
        const ctrl = new AbortController(); const tt = setTimeout(() => ctrl.abort(), 8000);
        const r = await fetch('https://openrouter.ai/api/v1/key', { headers: { 'Authorization': 'Bearer ' + key }, signal: ctrl.signal });
        clearTimeout(tt);
        ok = r.ok; if (!ok) detail = 'HTTP ' + r.status + ' from OpenRouter /key';
      } catch (e) { detail = 'fetch error: ' + String((e as Error)?.message || e).slice(0, 140); }
    }

    const prior = parseInt((await sec('ai_health_fails')) || '0', 10) || 0;

    // record a heartbeat run (best-effort)
    try { await admin.from('agent_runs').insert({ agent: 'ai_health', started_at: started, finished_at: new Date().toISOString(), status: ok ? 'ok' : 'error', counts: { authorised: 1, consecutive_fails: ok ? 0 : prior + 1, detail }, note: skipped ? ('ai_health made NO request to any paid provider: ' + detail) : ok ? 'ai_health confirmed the OpenRouter gateway and API key are reachable. AI-dependent agents are operating normally.' : ('ai_health could not reach the AI provider (' + detail + '). This is failure ' + (prior + 1) + ' in a row; paging happens at ' + THRESHOLD + '. AI-dependent steps are degraded and intake is on keyword fallback.') }); } catch (_e) { /* */ }

    if (ok) {
      if (prior >= THRESHOLD) {
        try { await admin.from('founder_alerts').insert({ level: 'info', event: 'ai_recovered', detail: 'AI provider (OpenRouter) is reachable again after ' + prior + ' failed checks.', channel: 'system' }); } catch (_e) { /* */ }
        try { await admin.from('notifications').insert({ type: 'ai_recovered', to_email: admin_email, to_role: 'admin', channel: 'email', subject: 'AI provider recovered', body: 'The AI model gateway (OpenRouter) is reachable again. Agents can resume automatically. Any queued jobs will drain on their next scheduled run.', status: 'queued' }); } catch (_e) { /* */ }
      }
      // ONLY WRITE WHEN THE COUNTER ACTUALLY CHANGES (12 Aug 2026). This reset the counter to '0'
      // on every healthy run, including the overwhelming majority where it was already '0'.
      // app_secrets carries an audit trigger, so each no-op UPDATE wrote a security_audit_log row:
      // measured, 2,593 of the 2,678 app_secrets updates ever recorded are this one key, against 24
      // DELETEs and 157 INSERTs of real credentials across the whole estate.
      //
      // That is not a write-volume problem, it is an instrument problem. security_audit_log exists so
      // that a change to a credential can be found; 90% of it was a health counter ticking every
      // fifteen minutes, and a real key rotation sat buried in the noise. The counter itself is
      // legitimate and is read by the OS shell ("AI health failures"), so it stays — it is only
      // written when its value moves.
      if (prior !== 0) await setSec('ai_health_fails', '0');
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
