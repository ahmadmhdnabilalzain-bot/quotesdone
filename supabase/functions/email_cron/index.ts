// email_cron - run on a schedule: auto-detect Resend domain verification, enable sending, flush the outbox.
// v2: agent_runs instrumentation. This is the parent of send_outbox and only calls it when email_enabled is
//     true, so a disabled mail system could never be reported by send_outbox itself - nothing would invoke it.
//     That gap is closed here. Also surfaces Resend domain-verification failures, which were swallowed by a
//     bare catch. Runs every 2 minutes, so recurring states are throttled to one row per hour and healthy
//     idle runs are not logged at all.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA = Deno.env.get('SUPABASE_URL')!;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'email_cron', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block the mail pipeline */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'email_cron')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({}));
    const secret = await sec('inbound_secret');
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'email_cron');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', {}, 'email_cron called without the inbound secret'); return J({ error:'forbidden' }, 403); }
    let enabled = (await sec('email_enabled')) === 'true';
    let verified = enabled;
    let domainNote = '';
    // auto-verify: if not yet enabled, poll Resend domain status
    if (!enabled) {
      const key = await sec('resend_api_key'); const did = await sec('resend_domain_id');
      if (key && did) {
        try {
          const r = await fetch(`https://api.resend.com/domains/${did}`, { headers: { 'Authorization': `Bearer ${key}` } });
          const d = await r.json();
          if (d?.status === 'verified') { await admin.from('app_secrets').update({ value:'true' }).eq('key','email_enabled'); enabled = true; verified = true; await logRun('ok', { signal: 'email_auto_enabled' }, 'Resend domain verified - email_enabled flipped to true automatically'); }
          else { verified = false; domainNote = 'Resend domain status is "' + String(d?.status || 'unknown') + '", not verified'; }
        } catch (e) { domainNote = 'Resend domain check failed: ' + String((e as Error)?.message || e).slice(0, 200); }
      } else {
        domainNote = 'cannot auto-verify: resend_api_key or resend_domain_id missing';
      }
    }
    let flush: unknown = null;
    let flushErr = '';
    if (enabled) {
      try { const r = await fetch(`${SUPA}/functions/v1/send_outbox`, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ __secret: secret, limit: 50 }) }); flush = await r.json(); if (!r.ok) flushErr = 'send_outbox returned http ' + r.status; } catch (e) { flushErr = String((e as Error)?.message || e).slice(0, 200); flush = { error: String(e) }; }
    } else {
      // send_outbox is never invoked while disabled, so this is the only place the outage can surface.
      const { count: queued } = await admin.from('notifications').select('id', { count: 'exact', head: true }).or('status.eq.queued,status.eq.pending,status.is.null');
      await logThrottled('email_disabled', 60, 'error', { queued: queued || 0, verified },
        'EMAIL PIPELINE IDLE - email_enabled is not true, so send_outbox is never called and ' + (queued || 0) + ' notification(s) are waiting. ' + domainNote);
    }
    if (flushErr) await logRun('error', { enabled, verified }, 'outbox flush failed: ' + flushErr);
    return J({ ok:true, enabled, verified, flush });
  } catch (e) { const m = String((e as Error)?.message||e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
