// kyc — passwordless account completion: mobile (SMS) + email verification, optional DOB profile, terms->signed PDF.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
function ageFrom(dob: string): number | null { const d = new Date(dob); if (isNaN(d.getTime())) return null; const t = new Date(); let a = t.getFullYear() - d.getFullYear(); const m = t.getMonth() - d.getMonth(); if (m < 0 || (m === 0 && t.getDate() < d.getDate())) a--; return a; }
function code6() { return String(Math.floor(100000 + Math.random() * 900000)); }
// SECURITY FIX (27 Jul 2026): email codes here were stored in PLAINTEXT (email_verifications.token)
// and checked with .eq('token', code) — a WHERE clause on the secret. A wrong guess simply matched no
// row, so nothing could be counted: no attempt cap, no lockout, no per-caller ceiling. 10^6 codes is
// minutes of scripted guessing. login_otp documented and fixed exactly this on 19–21 Jul; kyc never
// got the same treatment. Same approach copied here: HMAC-SHA256(code, app_secrets.otp_hmac_key) at
// rest (an unsalted hash of a 6-digit code is reversible from one table leak by precomputing all a
// million), fail closed if the key is absent rather than downgrade, guesses counted on the row and
// capped, plus a per-IP ceiling. email_verifications already carries attempts + token_hash (login_otp
// uses both), so no schema change is involved.
const KYC_EMAIL_MAX_ATTEMPTS = 5;
const KYC_EMAIL_VERIFY_PER_IP_HOUR = 30;
let _otpKey: string | null = null;
async function otpKey(): Promise<string> { if (_otpKey) return _otpKey; const k = await sec('otp_hmac_key'); if (!k) throw new Error('otp_hmac_key_missing'); _otpKey = k; return k; }
async function otpHash(code: string): Promise<string> { const ck = await crypto.subtle.importKey('raw', new TextEncoder().encode(await otpKey()), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); const mac = await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(code)); return Array.from(new Uint8Array(mac)).map((x) => x.toString(16).padStart(2, '0')).join(''); }
async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // limiter unavailable must not lock legitimate users out of account completion
}
async function twilioAuth() { const sid = await sec('twilio_api_key_sid'); const secret = await sec('twilio_api_key_secret'); const va = await sec('twilio_verify_service_sid'); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }
async function sendEmail(to: string, subject: string, html: string) { const key = await sec('resend_api_key'); if (!key) return false; const from = (await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>'; try { const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ from, to, subject, html }) }); return r.ok; } catch { return false; } }
// SUPPRESSION BYPASS 28 Jul 2026 ----------------------------------------------------------------
// login_otp and contact_submit both consult email_suppressions before handing anything to Resend,
// and send_outbox queries the same table. kyc did not: sendEmail() above builds its own Resend call,
// so the "Confirm your QuotesDone email" code went to whatever address the session carries -
// including one Resend has already told us rejects mail permanently. A user correctly refused at
// sign-in by login_otp for exactly this reason reaches the same mailbox one screen later through
// account setup, which is the domain-reputation damage the list exists to prevent. Same check, same
// shape of refusal and the same agent_runs note as login_otp, so there is one mechanism and not two.
// Fails OPEN on a lookup error - a suppression-table outage must not block account completion.
async function isSuppressed(email: string): Promise<boolean> {
  try { const { data } = await admin.from('email_suppressions').select('email').eq('email', email).maybeSingle(); return !!data; }
  catch (_e) { return false; }
}
function wrapCode(code: string) { const logo = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/icon_192.png'; return `<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:480px;margin:0 auto;color:#1f2937"><div style="text-align:center;padding:18px 0"><img src="${logo}" width="44" height="44" alt="QuotesDone"></div><div style="background:#fff;border:1px solid #eef0f2;border-radius:14px;padding:26px;text-align:center"><h1 style="font-size:19px;color:#111827;margin:0 0 8px">Confirm your email</h1><p style="font-size:14px;color:#6b7280;margin:0 0 16px">Enter this code to confirm your email on QuotesDone. It expires in 10 minutes.</p><div style="font-size:34px;font-weight:800;letter-spacing:8px;color:#0d9488;background:#f0fdfa;border-radius:12px;padding:14px 0">${code}</div></div></div>`; }

// Observability: identity state changes and delivery failures land in agent_runs.
// The read-only 'state' action is not logged (high volume, no failure mode worth tracking).
function mkLog(t0: number) {
  return async (status: string, counts: Record<string, unknown>, note: string) => {
    try {
      await admin.from('agent_runs').insert({ agent: 'kyc', status, counts,
        note: String(note || '').slice(0, 500),
        started_at: new Date(t0).toISOString(), finished_at: new Date().toISOString() });
    } catch (_e) { /* never let logging break account completion */ }
  };
}

Deno.serve(async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const b = await req.json().catch(() => ({} as any)); const action = String(b.action || '');

    const { data: lead } = await admin.from('leads').select('id,contact_name,phone,owner_dob,owner_email_verified,owner_phone_verified,accepted_terms_at,signed_terms_url,company_name').eq('claimed_by', email).maybeSingle();
    const { data: cust } = await admin.from('customers').select('id,full_name,phone,date_of_birth,email_verified,phone_verified,tos_accepted_at,signed_terms_url').eq('email', email).maybeSingle();
    const kind = lead ? 'supplier' : 'customer';

    if (action === 'state') {
      // SECURITY FIX (27 Jul 2026): 'state' derived `emailProven` from the auth provider's
      // email_confirmed_at / confirmed_at and, on a plain READ, flipped owner_email_verified /
      // email_verified to true. That flag proves nothing on this platform: every auth user is minted
      // with email_confirm:true (login_otp ensureUser, and auth_api before it was retired), so
      // emailProven was ALWAYS true and the first 'state' call self-granted email verification to
      // anyone holding a session — including a session obtained by SMS alone, which never touches the
      // address. Email is proven only by the 6-digit code this function itself sends and checks
      // (send_email -> verify_email). A read must not mutate identity state, so the persist-what-we-
      // report insert from the earlier fix is gone too: with nothing granted here there is nothing to
      // persist, and a customer with no row is simply not verified yet (save_customer /
      // verify_email create it). Response shape is unchanged for CustomerPortal / SupplierPortal.
      if (kind === 'supplier') {
        const ev = !!lead!.owner_email_verified;
        return J({ ok: true, kind, email, full_name: lead!.contact_name, phone: lead!.phone, dob: lead!.owner_dob, email_verified: ev, phone_verified: !!lead!.owner_phone_verified, terms_signed: !!lead!.signed_terms_url });
      }
      const c = cust || {} as any;
      const ev = !!c.email_verified;
      return J({ ok: true, kind, email, full_name: c.full_name || '', phone: c.phone || '', dob: c.date_of_birth || '', email_verified: ev, phone_verified: !!c.phone_verified, terms_signed: !!c.signed_terms_url });
    }

    if (action === 'save_customer') {
      const full_name = String(b.full_name || '').trim().slice(0, 120); const phone = String(b.phone || '').trim().slice(0, 40); const dob = String(b.dob || '').trim();
      if (full_name.length < 2) return J({ error: 'Please enter your name.' }, 400);
      if (phone.replace(/\D/g, '').length < 7) return J({ error: 'Please enter a valid mobile number.' }, 400);
      const row: any = { email, full_name, phone };
      if (dob) { const a = ageFrom(dob); if (a !== null && a >= 18 && a <= 120) row.date_of_birth = dob; }
      if (cust) await admin.from('customers').update(row).eq('id', cust.id); else await admin.from('customers').insert(row);
      await logRun('ok', { action, kind, created: !cust }, '');
      return J({ ok: true });
    }

    if (action === 'send_email') {
      // Checked BEFORE the row is inserted so we never mint a code that cannot be delivered.
      if (await isSuppressed(email)) {
        await logRun('error', { action, kind, suppressed: 1, channel: 'email' }, 'kyc refused to email a verification code to ' + email + ' - it is in email_suppressions (hard bounce, spam complaint or unsubscribe). No code was issued and no Resend call was made. If this is a real user, confirm the mailbox works and delete their email_suppressions row; do not remove this check.');
        return J({ error: 'We cannot email this address - it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.', suppressed: true }, 403);
      }
      const c = code6();
      // 27 Jul 2026: store token_hash (HMAC), never the bare code. token stays NULL from here on;
      // verify_email still honours a plaintext token row so codes issued before this deploy work out
      // their 10 minutes. Expiry was and stays 10 minutes and is enforced on the verify side.
      await admin.from('email_verifications').insert({ email, token_hash: await otpHash(c), purpose: 'kyc', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      // previously the send result was discarded: a failed send left the user waiting with no trace
      const sent = await sendEmail(email, 'Confirm your QuotesDone email', wrapCode(c));
      if (!sent) await logRun('error', { action, kind }, 'verification email failed to send (Resend rejected or key missing) - user cannot verify');
      else await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }
    if (action === 'verify_email') {
      const c = String(b.code || '').replace(/\D/g, '');
      if (!c) return J({ error: 'Enter the 6-digit code.' }, 400);
      // SECURITY FIX (27 Jul 2026): see the OTP note at the top. The lookup used to put the code in
      // the WHERE clause, so a wrong guess was indistinguishable from "no code" and could not be
      // counted — unlimited guesses at 10^6. Now: cap per caller BEFORE touching the row, fetch the
      // newest live code, compare in code, count the miss, and burn the code on the 5th.
      const vip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';
      if (!(await rl('kyc_verify_email_ip:' + vip, KYC_EMAIL_VERIFY_PER_IP_HOUR, 3600))) {
        await logRun('error', { action, kind, rate_limited: 1, scope: 'verify_ip' }, 'kyc blocked a caller making more than ' + KYC_EMAIL_VERIFY_PER_IP_HOUR + ' email-code attempts in an hour. A real person never reaches this; sustained hits mean someone is guessing codes.');
        return J({ error: 'Too many attempts. Please request a new code.' }, 429);
      }
      // limit(1) + [0], NOT maybeSingle(): a user who pressed send twice has two live rows and
      // maybeSingle() errors on >1 and returns null, which would reject BOTH codes (login_otp's
      // self-inflicted lockout, 21 Jul). limit(1) deterministically takes the newest.
      const { data: rows } = await admin.from('email_verifications').select('*').eq('email', email).eq('purpose', 'kyc').is('used_at', null).order('created_at', { ascending: false }).limit(1);
      const row = rows && rows[0];
      if (!row) return J({ error: 'Incorrect or expired code.' }, 400);
      if (new Date(row.expires_at) < new Date()) return J({ error: 'That code has expired.' }, 400);
      if ((row.attempts || 0) >= KYC_EMAIL_MAX_ATTEMPTS) {
        await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
        await logRun('error', { action, kind, locked: 1 }, 'kyc burned an email code after ' + KYC_EMAIL_MAX_ATTEMPTS + ' wrong guesses; the user must request a new one. Sustained hits on one account mean someone is guessing.');
        return J({ error: 'Too many incorrect attempts. Please request a new code.' }, 429);
      }
      // row.token is only set for codes issued before hashing shipped on 27 Jul 2026
      const match = row.token_hash ? ((await otpHash(c)) === row.token_hash) : (!!row.token && c === row.token);
      if (!match) { await admin.from('email_verifications').update({ attempts: (row.attempts || 0) + 1 }).eq('id', row.id); return J({ error: 'Incorrect or expired code.' }, 400); }
      await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
      // 27 Jul 2026: 'state' no longer creates the customers row as a side effect of a read, so this
      // must not assume one exists — an .update() on a missing row silently persists nothing and the
      // user would loop on the verify step forever. Insert it, falling back to update on a race.
      if (kind === 'supplier') await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email);
      else if (cust) await admin.from('customers').update({ email_verified: true }).eq('email', email);
      else { const ins = await admin.from('customers').insert({ email, email_verified: true }); if (ins.error) await admin.from('customers').update({ email_verified: true }).eq('email', email); }
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'send_sms') {
      const phone = toE164(String(b.phone || '')); if (!phone) return J({ error: 'Enter a valid mobile number.' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio_api_key_sid / secret / verify_service_sid'); return J({ error: 'SMS is not configured.' }, 500); }
      const since = new Date(Date.now() - 3600e3).toISOString();
      const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', phone).gte('created_at', since);
      if ((count || 0) >= 5) { await logRun('ok', { action, kind, rate_limited: true }, 'rate limit hit: 5+ code requests for this number in the last hour'); return J({ error: 'Too many code requests. Please try again later.' }, 429); }
      const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Channel: 'sms' }) });
      const jd = await r.json(); if (!r.ok || jd?.status === 'canceled') { await logRun('error', { action, kind, http: r.status }, 'twilio verify send failed: ' + String(jd?.message || jd?.status || '').slice(0, 200)); return J({ error: jd?.message || 'Could not send the SMS code.' }, 502); }
      await admin.from('phone_verifications').insert({ email, phone, code: 'twilio', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }
    if (action === 'verify_sms') {
      const phone = toE164(String(b.phone || '')); const code = String(b.code || '').replace(/\D/g, '');
      if (!phone || !code) return J({ error: 'Enter the 6-digit code.' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio credentials'); return J({ error: 'SMS is not configured.' }, 500); }
      const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/VerificationCheck`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Code: code }) });
      const jd = await r.json(); if (jd?.status !== 'approved') return J({ error: 'Incorrect or expired code.' }, 400);
      if (kind === 'supplier') await admin.from('leads').update({ owner_phone_verified: true, phone }).eq('claimed_by', email); else await admin.from('customers').update({ phone_verified: true, phone }).eq('email', email);
      await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'accept_terms') {
      const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();
      const nowIso = new Date().toISOString();
      if (kind === 'supplier') await admin.from('leads').update({ accepted_terms_at: nowIso, accepted_terms_version: 'v4', accepted_terms_ip: ip }).eq('claimed_by', email);
      else await admin.from('customers').update({ tos_accepted_at: nowIso, tos_version: 'v3', tos_ip: ip }).eq('email', email);
      let signed_url = null; let signErr = '';
      try { const secret = await sec('inbound_secret'); const r = await fetch(`${FN}/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, action: 'sign', kind, email }) }); const jd = await r.json(); signed_url = jd?.signed_url || null; if (!signed_url) signErr = String(jd?.error || jd?.detail || 'no signed_url returned').slice(0, 200); } catch (e) { signErr = String((e as Error)?.message || e).slice(0, 200); }
      // terms acceptance is recorded either way; a missing signed PDF is a compliance-trail gap worth surfacing
      if (!signed_url) await logRun('error', { action, kind, terms_recorded: true, signed_pdf: false }, 'terms accepted but signed PDF not produced: ' + signErr);
      else await logRun('ok', { action, kind, terms_recorded: true, signed_pdf: true }, '');
      return J({ ok: true, signed_url });
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
});
