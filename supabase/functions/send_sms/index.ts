// send_sms v3 - sends SMS via Twilio using API-KEY auth (account uses API keys, not auth_token).
// Two modes: single ({to, body}) or flush (drains queued channel='sms' notifications).
// Secret-guarded (inbound_secret). Reads twilio_account_sid (URL) + twilio_api_key_sid/_secret (auth) + twilio_from (sender).
// Graceful: if not configured, returns { ok:false, error:'sms_not_configured' } and changes nothing.
// v3: agent_runs instrumentation. Runs every 2 minutes and always returned 200, so 'sms_not_configured'
//     and Twilio rejections were indistinguishable from a healthy idle flush. Recurring config states are
//     throttled to one row per hour; idle runs with nothing queued are not logged at all.
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { FIXTURE_CAPTURE_NOTE, FIXTURE_REFUSAL, isDemoPhone } from '../_shared/demo_identity.ts';
import { statusCallbackUrl } from '../_shared/twilio_status.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function normPhone(p: string){ let s = String(p||'').trim().replace(/[^0-9+]/g,''); if(!s) return ''; if(s.startsWith('00')) s='+'+s.slice(2); if(!s.startsWith('+')){ if(s.startsWith('0')) s='+971'+s.slice(1); else if(s.startsWith('971')) s='+'+s; else s='+'+s; } return s; }

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'send_sms', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging block sending */ }
}
async function logThrottled(signal: string, minutes: number, status: string, counts: Record<string, unknown>, note: string) {
  try {
    const since = new Date(Date.now() - minutes * 60000).toISOString();
    const { data } = await admin.from('agent_runs').select('id').eq('agent', 'send_sms')
      .gte('started_at', since).eq('counts->>signal', signal).limit(1);
    if (data && data.length) return;
  } catch (_e) { /* if the check fails, fall through and log */ }
  await logRun(status, { ...counts, signal }, note);
}

async function twilioSend(acct: string, ks: string, kk: string, from: string, to: string, body: string){
  const auth = btoa(ks + ':' + kk);
  const form = new URLSearchParams({ To: to, From: from, Body: body, StatusCallback: statusCallbackUrl() });
  const r = await timedFetch(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`, { method: 'POST', headers: { 'Authorization': 'Basic ' + auth, 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
  const jd = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, sid: jd?.sid || null, error: r.ok ? null : (jd?.message || ('http ' + r.status)) };
}

Deno.serve(observe('send_sms', async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'send_sms');
    if (!__auth.ok) { await logThrottled('forbidden', 60, 'error', {}, 'send_sms called without the inbound secret'); return J({ error: 'forbidden' }, 403); }
    const acct = await sec('twilio_account_sid'); const ks = await sec('twilio_api_key_sid'); const kk = await sec('twilio_api_key_secret'); const from = await sec('twilio_from');
    if (!acct || !ks || !kk || !from) { await logThrottled('not_configured', 60, 'error', {}, 'SMS NOT SENDING - missing twilio_account_sid / api_key_sid / api_key_secret / twilio_from'); return J({ ok: false, error: 'sms_not_configured' }, 200); }

    // Single send
    if (body.to && body.body) {
      const to = normPhone(String(body.to)); if (!to || to.length < 8) { await logRun('error', { direct: true }, 'bad_phone on direct send: ' + String(body.to || '').slice(0, 40)); return J({ ok: false, error: 'bad_phone' }, 200); }
      if (isDemoPhone(to)) { await logRun('skipped', { direct: true, captured: 1 }, FIXTURE_CAPTURE_NOTE); return J(FIXTURE_REFUSAL); }
      const res = await twilioSend(acct, ks, kk, from, to, String(body.body).slice(0, 600));
      if (!res.ok) await logRun('error', { direct: true, http: res.status }, 'direct SMS rejected by Twilio: ' + String(res.error || '').slice(0, 200));
      return J({ ok: res.ok, sid: res.sid, error: res.error });
    }

    // Flush queued SMS notifications
    const { data: rows } = await admin.from('notifications').select('id,to_phone,body').eq('channel', 'sms').eq('status', 'queued').not('to_phone', 'is', null).order('created_at', { ascending: true }).limit(25);
    let sent = 0, failed = 0, badPhone = 0; let lastErr = '';
    for (const n of (rows || [])) {
      const to = normPhone(String(n.to_phone || '')); if (!to) { await admin.from('notifications').update({ status: 'failed' }).eq('id', n.id); failed++; badPhone++; continue; }
      if (isDemoPhone(to)) { await admin.from('notifications').update({ status: 'suppressed', last_error: FIXTURE_CAPTURE_NOTE }).eq('id', n.id); continue; }
      const res = await twilioSend(acct, ks, kk, from, to, String(n.body || '').slice(0, 600));
      // 22 Sep 2026: the SID is stored, as send_whatsapp does, so wa_status can match Twilio's delivered /
      // undelivered report to this row. Before this an SMS was 'sent' with nothing to match it by.
      await admin.from('notifications').update({ status: res.ok ? 'sent' : 'failed', sent_at: res.ok ? new Date().toISOString() : null, provider_message_id: res.ok ? res.sid : null, last_error: res.ok ? null : String(res.error).slice(0,300) }).eq('id', n.id);
      if (res.ok) sent++; else { failed++; lastErr = String(res.error || '').slice(0, 200); }
    }
    // Idle polls (nothing queued) stay out of agent_runs so real events are not buried.
    if (failed) await logRun('error', { sent, failed, bad_phone: badPhone }, failed + ' SMS failed and are marked failed with no retry. Last error: ' + (lastErr || 'unroutable phone number'));
    else if (sent) await logRun('ok', { sent, failed }, '');
    return J({ ok: true, sent, failed });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
