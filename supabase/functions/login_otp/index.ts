import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
function code6() { return String(Math.floor(100000 + Math.random() * 900000)); }
// Sign-in codes are stored hashed. A 6-digit code is only safe if guesses are
// capped, so verify is limited per issued code AND per caller.
const EMAIL_VERIFY_MAX_ATTEMPTS = 5;
const EMAIL_VERIFY_PER_IP_HOUR = 30;
// Sign-in codes are stored as HMAC-SHA256(code, server key), never a bare hash. A 6-digit code
// has only 10^6 possibilities, so an unsalted SHA-256 of the code is reversible from a single
// table leak by precomputing all a million hashes. The HMAC key (app_secrets.otp_hmac_key) makes
// a leaked token_hash useless without the key; we fail closed if the key is missing rather than
// silently fall back to a weak hash.
let _otpKey: string | null = null;
async function otpKey(): Promise<string> {
  if (_otpKey) return _otpKey;
  const k = await sec('otp_hmac_key');
  if (!k) throw new Error('otp_hmac_key_missing');
  _otpKey = k; return k;
}
async function otpHash(code: string): Promise<string> {
  const ck = await crypto.subtle.importKey('raw', new TextEncoder().encode(await otpKey()), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(code));
  return Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, '0')).join('');
}
async function twilioAuth() { const sid = await sec('twilio_api_key_sid'); const secret = await sec('twilio_api_key_secret'); const va = await sec('twilio_verify_service_sid'); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }
async function sendEmail(to: string, subject: string, html: string) { const key = await sec('resend_api_key'); if (!key) return false; const from = (await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>'; try { const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ from, to, subject, html }) }); return r.ok; } catch { return false; } }

// SUPPRESSION BYPASS 27 Jul 2026 ----------------------------------------------------------------
// send_outbox was the ONLY sender in the codebase that consulted email_suppressions. sendEmail()
// above builds its own Resend call, so a sign-in code went out to any address a caller typed in -
// including the 27 hard_bounce:permanent rows resend_webhook has recorded. Re-mailing a mailbox
// Resend has already told us rejects permanently is exactly what burns the sender reputation the
// suppression list exists to protect, and the code could never arrive anyway: the user sat waiting
// for an email that bounced while we returned ok:true. Transactional or not, we do not send, and we
// say so instead of silently succeeding. Fails OPEN on a lookup error - a suppression-table outage
// must not lock every user out of sign-in.
async function isSuppressed(email: string): Promise<boolean> {
  try { const { data } = await admin.from('email_suppressions').select('email').eq('email', email).maybeSingle(); return !!data; }
  catch (_e) { return false; }
}

// ABUSE CONTROL 19 Jul 2026 --------------------------------------------------------------------
// The SMS branch was rate limited per PHONE NUMBER only (6/hour). With allow_signup:true the
// "does this number have an account?" check is skipped, so an attacker could walk a list of UAE
// mobile numbers and have QuotesDone send a real, billable Twilio SMS to each one - 6 per number
// per hour with no ceiling on how many DIFFERENT numbers. That is both unbounded spend on our
// Twilio account and SMS harassment of third parties sent in our name.
// Per-number capping alone cannot stop that, because each new victim is a fresh bucket. These add
// a per-CALLER cap and an absolute hourly ceiling on the signup path so the blast radius is bounded
// even if someone scripts it. A legitimate person signing up never comes close to either.
const SMS_PER_IP_HOUR = 10;
const SMS_SIGNUP_GLOBAL_HOUR = 60;
async function rl(key: string, limit: number, seconds: number): Promise<boolean> {
  try { const { data, error } = await admin.rpc('rl_check', { p_key: key, p_limit: limit, p_seconds: seconds }); if (error) return true; return data !== false; }
  catch (_e) { return true; } // limiter unavailable must not lock legitimate users out of sign-in
}
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try { await admin.from('agent_runs').insert({ agent: 'login_otp', status, counts, note: String(note || '').slice(0, 500), finished_at: new Date().toISOString() }); } catch (_e) { /* */ }
}

function wrapCode(code: string) { const logo = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/icon_192.png'; return `<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:480px;margin:0 auto;color:#1f2937"><div style="text-align:center;padding:18px 0"><img src="${logo}" width="44" height="44" alt="QuotesDone"></div><div style="background:#fff;border:1px solid #eef0f2;border-radius:14px;padding:26px;text-align:center"><h1 style="font-size:19px;color:#111827;margin:0 0 8px">Your sign-in code</h1><p style="font-size:14px;color:#6b7280;margin:0 0 16px">Enter this code to sign in to QuotesDone. It expires in 10 minutes.</p><div style="font-size:34px;font-weight:800;letter-spacing:8px;color:#0d9488;background:#f0fdfa;border-radius:12px;padding:14px 0">${code}</div><p style="font-size:12px;color:#9aa1ab;margin-top:16px">If you didn't request this, you can ignore this email.</p></div><p style="text-align:center;font-size:11px;color:#9aa1ab;margin-top:14px">QuotesDone Technologies · Dubai, UAE</p></div>`; }
async function uidByEmail(email: string): Promise<string | null> { try { const { data } = await admin.rpc('auth_uid_by_email', { p_email: email }); return (data as string) || null; } catch { return null; } }
async function ensureUser(email: string) { let uid = await uidByEmail(email); if (!uid) { const cr = await admin.auth.admin.createUser({ email, email_confirm: true, password: crypto.randomUUID() }); uid = cr.data?.user?.id || null; } return uid; }
async function mintSession(email: string): Promise<{ access_token: string; refresh_token: string } | null> { try { await ensureUser(email); const { data } = await admin.auth.admin.generateLink({ type: 'magiclink', email }); const th = (data as any)?.properties?.hashed_token; if (!th) return null; const { data: v, error } = await admin.auth.verifyOtp({ type: 'email', token_hash: th } as any); if (error || !v?.session) return null; return { access_token: v.session.access_token, refresh_token: v.session.refresh_token }; } catch { return null; } }
// THE FOUNDER IS NEITHER A SUPPLIER NOR A CUSTOMER, which is why mobile sign-in could not reach
// him. This resolver knew two kinds — 'supplier' (leads.claimed_by) and 'customer'
// (customers.email) — and his number lives in app_secrets.admin_mfa_phone while `customers` holds
// no row for him at all. Every Twilio credential was provisioned and authenticating (Verify
// service "QuotesDone", HTTP 200), and the OS sign-in still emailed a code, because the phone
// could not be turned into an account. Checked FIRST and on the last nine digits like the other
// two branches, so +971 50 931 9355 and 0509319355 both land.
async function resolveAdminEmailByPhone(e164: string): Promise<string | null> {
  const admins = (await sec('admin_mfa_phone') || '').split(',').map((s) => s.replace(/\D/g, '')).filter((s) => s.length >= 9);
  const last9 = e164.replace(/\D/g, '').slice(-9);
  if (!admins.some((a) => a.slice(-9) === last9)) return null;
  const first = (await sec('admin_emails') || '').split(',')[0]?.trim().toLowerCase();
  return first || null;
}
async function resolveEmailByPhone(kind: string, e164: string): Promise<string | null> { const adminEmail = await resolveAdminEmailByPhone(e164); if (adminEmail) return adminEmail; const last9 = e164.slice(-9); if (kind === 'supplier') { const { data } = await admin.from('leads').select('claimed_by,phone').not('claimed_by', 'is', null).ilike('phone', '%' + last9).limit(1); return (data && data[0] && (data[0] as any).claimed_by) || null; } const { data } = await admin.from('customers').select('email,phone').ilike('phone', '%' + last9).limit(1); return (data && data[0] && (data[0] as any).email) || null; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');
    const kind = body.user_kind === 'supplier' ? 'supplier' : 'customer';
    const idRaw = String(body.identifier || '').trim();
    const allowSignup = body.allow_signup === true;
    const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || 'unknown';

    if (action === 'send') {
      if (emailOk(idRaw)) {
        const email = idRaw.toLowerCase();
        // Checked BEFORE the row is inserted so we never mint a code that cannot be delivered.
        if (await isSuppressed(email)) {
          await logRun('error', { suppressed: 1, channel: 'email' }, 'login_otp refused to email a sign-in code to ' + email + ' - it is in email_suppressions (hard bounce, spam complaint or unsubscribe). No code was issued and no Resend call was made. If this is a real user, confirm the mailbox works and delete their email_suppressions row; do not remove this check.');
          return J({ error: 'We cannot email this address - it is on our do-not-send list because mail to it bounced or was unsubscribed. Please contact info@quotesdone.com and we will restore it.', suppressed: true }, 403);
        }
        const since = new Date(Date.now() - 3600e3).toISOString();
        const { count } = await admin.from('email_verifications').select('id', { count: 'exact', head: true }).eq('email', email).gte('created_at', since);
        if ((count || 0) >= 8) return J({ error: 'Too many code requests. Please try again later.' }, 429);
        const c = code6();
        await admin.from('email_verifications').insert({ email, token_hash: await otpHash(c), purpose: 'login', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
        await sendEmail(email, 'Your QuotesDone sign-in code', wrapCode(c));
        return J({ ok: true, channel: 'email', identifier: email });
      }
      const e164 = toE164(idRaw);
      if (!e164) return J({ error: 'Enter a valid email address or UAE mobile number.' }, 400);
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS sign-in is not enabled yet. Please sign in with your email.' }, 503);
      const acctEmail = await resolveEmailByPhone(kind, e164);
      // Do not send (and pay for) an SMS to a number that has no account. Tell the user first.
      if (!acctEmail && !allowSignup) return J({ error: "This mobile number isn't linked to a QuotesDone account yet. Please sign in with the email you registered with, or create your account first.", no_account: true }, 404);

      // Caller-level and global ceilings. Checked BEFORE the Twilio call so a blocked attempt costs nothing.
      const ipOk = await rl('login_otp_sms_ip:' + ip, SMS_PER_IP_HOUR, 3600);
      const globalOk = (!acctEmail && allowSignup) ? await rl('login_otp_sms_signup_global', SMS_SIGNUP_GLOBAL_HOUR, 3600) : true;
      if (!ipOk || !globalOk) {
        await logRun('error', { rate_limited: 1, scope: !ipOk ? 'ip' : 'signup_global', signup_path: !acctEmail && allowSignup ? 1 : 0 },
          !ipOk
            ? ('login_otp blocked a caller that asked for more than ' + SMS_PER_IP_HOUR + ' SMS codes in an hour from one address. No SMS was sent and no Twilio charge was incurred. A real person signing in never reaches this - sustained hits mean someone is walking a list of numbers.')
            : ('login_otp hit the global hourly ceiling of ' + SMS_SIGNUP_GLOBAL_HOUR + ' sign-up SMS messages. Further sign-up codes are refused this hour to cap Twilio spend. If genuine sign-ups are being turned away, raise SMS_SIGNUP_GLOBAL_HOUR - do not remove the ceiling.'));
        return J({ error: 'Too many code requests. Please try again later.' }, 429);
      }

      const since = new Date(Date.now() - 3600e3).toISOString();
      const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', e164).gte('created_at', since);
      if ((count || 0) >= 6) return J({ error: 'Too many code requests. Please try again later.' }, 429);
      try {
        const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: e164, Channel: 'sms' }) });
        const jd = await r.json(); if (!r.ok || jd?.status === 'canceled') return J({ error: jd?.message || 'Could not send the SMS code.' }, 502);
        await admin.from('phone_verifications').insert({ email: acctEmail || '', phone: e164, code: 'twilio', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
        return J({ ok: true, channel: 'sms', identifier: e164, known: !!acctEmail });
      } catch (e) { return J({ error: 'Could not send the SMS code.', detail: String((e as Error)?.message || e) }, 502); }
    }

    if (action === 'verify') {
      const code = String(body.code || '').replace(/\D/g, '');
      if (!code) return J({ error: 'Enter the code you received.' }, 400);
      if (emailOk(idRaw)) {
        const email = idRaw.toLowerCase();
        // Cap guesses per caller before touching the row at all.
        if (!(await rl('login_otp_verify_ip:' + ip, EMAIL_VERIFY_PER_IP_HOUR, 3600))) {
          await logRun('error', { rate_limited: 1, scope: 'verify_ip' }, 'login_otp blocked a caller making more than ' + EMAIL_VERIFY_PER_IP_HOUR + ' code-verification attempts in an hour. A real person never reaches this; sustained hits mean someone is guessing codes.');
          return J({ error: 'Too many attempts. Please request a new code.' }, 429);
        }
        // Fetch the newest live code for this email, then compare in code so a
        // wrong guess can be counted (a WHERE on the token cannot be).
        // NOTE: limit(1) + [0], NOT maybeSingle(). A user who clicks "resend"
        // has two un-used codes inside the 10-minute window; maybeSingle()
        // errors on >1 row and returns null, which rejected BOTH codes as
        // "Incorrect or expired" until the older expired - a self-inflicted
        // login lockout. limit(1) deterministically takes the newest.
        const { data: rows } = await admin.from('email_verifications').select('*').eq('email', email).eq('purpose', 'login').is('used_at', null).order('created_at', { ascending: false }).limit(1);
        const row = rows && rows[0];
        if (!row) return J({ error: 'Incorrect or expired code.' }, 400);
        if (new Date(row.expires_at) < new Date()) return J({ error: 'That code has expired. Please request a new one.' }, 400);
        if ((row.attempts || 0) >= EMAIL_VERIFY_MAX_ATTEMPTS) {
          await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
          return J({ error: 'Too many incorrect attempts. Please request a new code.' }, 429);
        }
        const givenHash = await otpHash(code);
        // row.token is only set for codes issued before hashing shipped
        const match = row.token_hash ? (givenHash === row.token_hash) : (!!row.token && code === row.token);
        if (!match) {
          await admin.from('email_verifications').update({ attempts: (row.attempts || 0) + 1 }).eq('id', row.id);
          return J({ error: 'Incorrect or expired code.' }, 400);
        }
        await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
        if (kind === 'customer') await admin.from('customers').update({ email_verified: true }).eq('email', email); else await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email);
        const s = await mintSession(email); if (!s) return J({ error: 'Could not start your session. Please try again.' }, 500);
        return J({ ok: true, ...s, user_kind: kind, email });
      }
      const e164 = toE164(idRaw); if (!e164) return J({ error: 'Enter a valid mobile number.' }, 400);
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS sign-in is not enabled yet.' }, 503);
      try {
        const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/VerificationCheck`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: e164, Code: code }) });
        const jd = await r.json(); if (jd?.status !== 'approved') return J({ error: 'Incorrect or expired code.' }, 400);
      } catch (e) { return J({ error: 'Verification failed, please try again.', detail: String((e as Error)?.message || e) }, 502); }
      const { data: pv } = await admin.from('phone_verifications').select('email').eq('phone', e164).not('email', 'eq', '').order('created_at', { ascending: false }).maybeSingle();
      let email = (pv as any)?.email || '';
      if (!email) email = (await resolveEmailByPhone(kind, e164)) || '';
      if (!email) return J({ error: 'No account is registered with this number. Please sign in with your email, or sign up first.' }, 404);
      if (kind === 'customer') await admin.from('customers').update({ phone_verified: true }).eq('email', email);
      await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', e164).is('used_at', null);
      const s = await mintSession(email); if (!s) return J({ error: 'Could not start your session. Please try again.' }, 500);
      return J({ ok: true, ...s, user_kind: kind, email });
    }

    return J({ error: 'Unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
