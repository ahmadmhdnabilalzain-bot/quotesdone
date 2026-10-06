import { siteCors } from '../_shared/site_origins.ts';
// mobile_otp v3 - customer mobile verification via Twilio VERIFY API (API-key auth).
// Uses the credentials that are actually provisioned: twilio_verify_service_sid + twilio_api_key_sid/_secret
// (account uses API keys + a Verify service, not legacy auth_token+from). Twilio manages the OTP code itself.
// Actions: 'status' (reports sms_enabled + phone), 'send', 'verify', 'diag' (read-only credential check).
// Authed via the customer's Supabase JWT. verify_jwt=false (validates JWT internally).
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { asLocale } from '../_shared/registered_locale.ts';
import { prefixBlocked } from '../_shared/otp_guard.ts';
import { FIXTURE_CAPTURE_NOTE, FIXTURE_REFUSAL, isDemoPhone } from '../_shared/demo_identity.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined)||undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function normPhone(p: string){ let s = String(p||'').trim().replace(/[^0-9+]/g,''); if(!s) return ''; if(s.startsWith('00')) s='+'+s.slice(2); if(!s.startsWith('+')){ if(s.startsWith('0')) s='+971'+s.slice(1); else if(s.startsWith('971')) s='+'+s; else s='+'+s; } return s; }

async function verifyCreds(){ return { svc: await sec('twilio_verify_service_sid'), ks: await sec('twilio_api_key_sid'), kk: await sec('twilio_api_key_secret') }; }
function basic(ks: string, kk: string){ return 'Basic ' + btoa(ks + ':' + kk); }

async function verifySend(svc: string, ks: string, kk: string, to: string, channel: string, locale: string){
  // Locale: the code arrives in the customer's registered language (founder, 14 Sep 2026).
  const form = new URLSearchParams({ To: to, Channel: channel, Locale: asLocale(locale) });
  const r = await timedFetch(`https://verify.twilio.com/v2/Services/${svc}/Verifications`, { method:'POST', headers:{ 'Authorization': basic(ks,kk), 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() });
  const jd = await r.json().catch(()=>({})); return { ok: r.ok, status: r.status, vstatus: jd?.status || null, error: r.ok ? null : (jd?.message || ('http '+r.status)), code: jd?.code || null };
}
async function verifyCheck(svc: string, ks: string, kk: string, to: string, code: string){
  const form = new URLSearchParams({ To: to, Code: code });
  const r = await timedFetch(`https://verify.twilio.com/v2/Services/${svc}/VerificationCheck`, { method:'POST', headers:{ 'Authorization': basic(ks,kk), 'Content-Type':'application/x-www-form-urlencoded' }, body: form.toString() });
  const jd = await r.json().catch(()=>({})); return { ok: r.ok, status: r.status, vstatus: jd?.status || null, error: r.ok ? null : (jd?.message || ('http '+r.status)) };
}

Deno.serve(siteCors(observe('mobile_otp', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');
    const { svc, ks, kk } = await verifyCreds();
    const smsEnabled = !!(svc && ks && kk);

    // read-only credential + service reachability check (no SMS sent). Secret-gated to avoid abuse.
    if (action === 'diag') {
      // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
      // per-context credential and the legacy shared secret, and records which one called.
      const __auth = await requireInternal(admin, body?.__secret, 'mobile_otp');
      if (!__auth.ok) return J({ error:'forbidden' }, 403);
      if (!smsEnabled) return J({ ok:false, sms_enabled:false, missing:{ verify_service_sid:!svc, api_key_sid:!ks, api_key_secret:!kk } });
      const r = await timedFetch(`https://verify.twilio.com/v2/Services/${svc}`, { headers:{ 'Authorization': basic(ks!,kk!) } });
      const jd = await r.json().catch(()=>({}));
      return J({ ok:r.ok, sms_enabled:true, http:r.status, service_name: jd?.friendly_name || null, auth_ok: r.ok, error: r.ok?null:(jd?.message||('http '+r.status)) });
    }

    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'Not signed in' }, 401);
    const email = user.email.toLowerCase();
    let { data: cust } = await admin.from('customers').select('id,phone,phone_verified,locale').eq('email', email).maybeSingle();
    if (!cust) { const ins = await admin.from('customers').insert({ email, locale: asLocale(body.lang) }).select('id,phone,phone_verified,locale').maybeSingle(); cust = ins.data; }

    // A fixture number never reaches Twilio, for a send or a check (_shared/demo_identity.ts).
    if ((action === 'send' || action === 'verify') && isDemoPhone(normPhone(String(body.phone || '')))) {
      try { await admin.from('agent_runs').insert({ agent: 'mobile_otp', status: 'skipped', counts: { action, captured: 1 }, note: FIXTURE_CAPTURE_NOTE, finished_at: new Date().toISOString() }); } catch (_e) { /* logging never blocks */ }
      return J(FIXTURE_REFUSAL);
    }

    if (action === 'status') return J({ ok: true, sms_enabled: smsEnabled, phone: cust!.phone || null, phone_verified: !!cust!.phone_verified });

    if (action === 'send') {
      if (!smsEnabled) return J({ ok: false, error: 'sms_not_configured' }, 200);
      const phone = normPhone(String(body.phone || ''));
      if (!phone || phone.replace(/\D/g,'').length < 9) return J({ ok: false, error: 'bad_phone' }, 200);
      // A prefix the IT engineer blocked for OTP pumping gets no code (public.otp_blocked_prefix).
      if ((await prefixBlocked(admin, phone)).blocked) return J({ ok: false, error: 'prefix_blocked' }, 403);
      // rate-limit: max 5 sends / 10 min / customer (ledger row, no code stored - Twilio Verify holds the code)
      const tenMinAgo = new Date(Date.now() - 600e3).toISOString();
      const { count } = await admin.from('customer_phone_otps').select('id', { count: 'exact', head: true }).eq('customer_id', cust!.id).gte('created_at', tenMinAgo);
      if ((count || 0) >= 5) return J({ ok: false, error: 'too_many_requests' }, 200);
      const res = await verifySend(svc!, ks!, kk!, phone, 'sms', String((cust as any)?.locale || 'en'));
      if (!res.ok) return J({ ok:false, error:'send_failed', detail: res.error, code: res.code }, 200);
      await admin.from('customer_phone_otps').insert({ customer_id: cust!.id, phone, code_hash: 'twilio_verify', expires_at: new Date(Date.now() + 600e3).toISOString() });
      return J({ ok: true, status: res.vstatus });
    }

    if (action === 'verify') {
      if (!smsEnabled) return J({ ok: false, error: 'sms_not_configured' }, 200);
      const phone = normPhone(String(body.phone || '')); const code = String(body.code || '').trim();
      if (!phone || !/^[0-9]{4,8}$/.test(code)) return J({ ok: false, error: 'bad_input' }, 200);
      const res = await verifyCheck(svc!, ks!, kk!, phone, code);
      if (!res.ok) return J({ ok:false, error:'verify_failed', detail: res.error }, 200);
      if (res.vstatus !== 'approved') return J({ ok: false, error: 'wrong_code', status: res.vstatus }, 200);
      await admin.from('customer_phone_otps').update({ consumed: true }).eq('customer_id', cust!.id).eq('phone', phone).eq('consumed', false);
      await admin.from('customers').update({ phone, phone_verified: true }).eq('id', cust!.id);
      return J({ ok: true, phone, phone_verified: true });
    }

    return J({ error: 'unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
})));
