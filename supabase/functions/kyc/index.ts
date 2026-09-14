// kyc — passwordless account completion: mobile (SMS) + email verification, REQUIRED DOB (18+) profile, terms->signed PDF.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { observe } from '../_shared/observe.ts';
import { dobProblem } from '../_shared/account_rule.ts';
import { asLocale, registeredLocale } from '../_shared/registered_locale.ts';
import { codeEmail } from '../_shared/code_email.ts';
import { askedPatch, choosePatch, parseChoiceOpt, verifiedPatch, whatsappState, whatsappUnavailable, type Patch, type WhatsAppRow } from '../_shared/whatsapp_choice.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
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
type TwAuth = { hdr: string; va: string };
// ONE Verify send, ONE check, ONE per-number limit for every channel (14 Sep 2026). send_sms owned
// these inline; the WhatsApp question needs the identical machinery on Channel=whatsapp, and two
// copies of a rate limit is how one of them ends up looser. The limit counts phone_verifications rows
// for the number in the last hour regardless of channel, so SMS, call and WhatsApp share 5 per hour.
async function phoneRateLimited(phone: string): Promise<boolean> {
  const since = new Date(Date.now() - 3600e3).toISOString();
  const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', phone).gte('created_at', since);
  return (count || 0) >= 5;
}
async function verifySend(tw: TwAuth, phone: string, channel: string, locale: string) {
  const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Channel: channel, Locale: locale }) });
  const jd: any = await r.json().catch(() => ({}));
  return { r, jd };
}
async function verifyCheck(tw: TwAuth, phone: string, code: string): Promise<boolean> {
  const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/VerificationCheck`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Code: code }) });
  const jd: any = await r.json().catch(() => ({}));
  return jd?.status === 'approved';
}
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

Deno.serve(observe('kyc', async (req) => {
  const logRun = mkLog(Date.now());
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  // KEEP-WARM (resilience_ping, 14 Sep 2026). No auth, no DB, before anything else: the isolate is
  // what needs exercising, not a real answer. See the header of resilience_ping/index.ts.
  if (req.headers.get('x-qd-warm') === '1') return new Response(null, { status: 204 });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user || !user.email) return J({ error: 'unauthorized' }, 401);
    const email = user.email.toLowerCase();
    const b = await req.json().catch(() => ({} as any)); const action = String(b.action || '');

    const { data: lead } = await admin.from('leads').select('id,contact_name,phone,owner_dob,owner_email_verified,owner_phone_verified,accepted_terms_at,signed_terms_url,company_name').eq('claimed_by', email).maybeSingle();
    const { data: cust } = await admin.from('customers').select('id,full_name,phone,date_of_birth,email_verified,phone_verified,tos_accepted_at,signed_terms_url').eq('email', email).maybeSingle();
    const kind = lead ? 'supplier' : 'customer';

    // The whatsapp_* columns are read in their OWN query, not added to the two selects above. A
    // select naming a column that does not exist returns data=null, and a null lead flips every
    // supplier to kind='customer' - so deploying this before the schema would have mis-routed every
    // action for every supplier. Isolated here, the worst case is a logged read error.
    const waTable = kind === 'supplier' ? 'leads' : 'customers';
    const waKey = kind === 'supplier' ? 'claimed_by' : 'email';
    const readWa = async (): Promise<WhatsAppRow | null> => {
      const { data, error } = await admin.from(waTable).select('whatsapp_phone,whatsapp_verified_at,whatsapp_opt,whatsapp_asked_at').eq(waKey, email).maybeSingle();
      if (error) { await logRun('error', { action, kind, stage: 'whatsapp_read' }, 'kyc could not read the whatsapp_* columns on ' + waTable + ': ' + error.message); return null; }
      return data as WhatsAppRow | null;
    };
    const writeWa = async (patch: Patch): Promise<boolean> => {
      const { data, error } = await admin.from(waTable).update(patch).eq(waKey, email).select('id');
      if (!error && (data?.length || 0) > 0) return true;
      // Same rule as verify_email: a customer may have a session and no customers row yet.
      if (!error && kind === 'customer') {
        const ins = await admin.from('customers').insert({ email, locale: asLocale(b.lang), ...patch });
        if (!ins.error) return true;
        await logRun('error', { action, kind, stage: 'whatsapp_write' }, 'kyc could not create the customers row for the WhatsApp answer: ' + ins.error.message);
        return false;
      }
      await logRun('error', { action, kind, stage: 'whatsapp_write' }, 'kyc could not save the WhatsApp answer on ' + waTable + ': ' + (error ? error.message : 'no row matched'));
      return false;
    };
    const saveFailed = () => J({ ok: false, error: 'save_failed', code: 'save_failed' }, 500);

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
      const whatsapp = whatsappState(await readWa());
      if (kind === 'supplier') {
        const ev = !!lead!.owner_email_verified;
        return J({ ok: true, kind, email, full_name: lead!.contact_name, phone: lead!.phone, dob: lead!.owner_dob, email_verified: ev, phone_verified: !!lead!.owner_phone_verified, terms_signed: !!lead!.signed_terms_url, whatsapp });
      }
      const c = cust || {} as any;
      const ev = !!c.email_verified;
      return J({ ok: true, kind, email, full_name: c.full_name || '', phone: c.phone || '', dob: c.date_of_birth || '', email_verified: ev, phone_verified: !!c.phone_verified, terms_signed: !!c.signed_terms_url, whatsapp });
    }

    if (action === 'save_customer') {
      const full_name = String(b.full_name || '').trim().slice(0, 120); const phone = String(b.phone || '').trim().slice(0, 40); const dob = String(b.dob || '').trim();
      if (full_name.length < 2) return J({ error: 'Please enter your name.' }, 400);
      if (phone.replace(/\D/g, '').length < 7) return J({ error: 'Please enter a valid mobile number.' }, 400);
      // DATE OF BIRTH IS REQUIRED AND UNDER-18 IS REFUSED (founder's account rule, 14 Sep 2026 — see
      // _shared/account_rule.ts). This used to keep an 18-120 date and silently DROP anything else, so
      // an under-18 user was never told no and a profile could complete with no DOB at all. Now a
      // missing, unparseable or under-18 date answers a code and saves nothing. An empty field falls
      // back to the stored DOB so the Account tab (which edits name/phone only) keeps working.
      const dobUse = dob || String((cust as any)?.date_of_birth || '');
      const dp = dobProblem(dobUse);
      if (dp) {
        const message = dp === 'under_18' ? 'You must be 18 or over to use QuotesDone.' : dp === 'dob_required' ? 'Please enter your date of birth.' : 'Please enter a valid date of birth.';
        return J({ error: dp, code: dp, message }, 400);
      }
      const row: any = { email, full_name, phone, date_of_birth: dobUse.slice(0, 10) };
      // CHANGING A VERIFIED NUMBER MUST UN-VERIFY IT (13 Aug 2026).
      //
      // This wrote `phone` and left `phone_verified` alone, so any caller holding a customer
      // session could POST a DIFFERENT number and keep the verified flag. That flag is not
      // cosmetic: create_inquiry gates on it, fn_wa_context scopes a WhatsApp conversation by it,
      // and login_otp's resolveEmailByPhone maps an incoming number back to an account with
      // `limit 1` — so a number written onto the wrong account can resolve a real person's phone
      // sign-in to somebody else's row. Verification means "we sent a code to THIS number and it
      // came back"; the moment the number changes, that sentence is no longer true about it.
      //
      // Compared digits-only because the same number is stored as +9715…, 05…, and with spaces,
      // and a formatting change is not a new number. Re-verifying is the ProfileGate's existing
      // flow: phone_verified false makes the gate render again on the next load, which is exactly
      // where the Send SMS control lives.
      const digits = (v: unknown) => String(v || '').replace(/\D/g, '');
      const phoneChanged = !!cust && digits((cust as any).phone) !== digits(phone);
      if (phoneChanged) row.phone_verified = false;
      // A first save IS the registration: it records the page language. An update never touches
      // locale - that changes only through Account settings (customer_api set_locale).
      if (cust) await admin.from('customers').update(row).eq('id', cust.id); else await admin.from('customers').insert({ ...row, locale: asLocale(b.lang) });
      if (phoneChanged) await logRun('ok', { action, kind, phone_reverify: 1 }, 'A customer changed their mobile number, so phone_verified was cleared and they must verify the new number before create_inquiry will accept a request. This is the intended behaviour, not a regression.');
      else await logRun('ok', { action, kind, created: !cust }, '');
      return J({ ok: true, phone_reverify_required: phoneChanged });
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
      const codeAr = (await registeredLocale(admin, { role: kind, email }, b.lang)) === 'ar';
      const mail = codeEmail('confirm', c, codeAr);
      const sent = await sendEmail(email, mail.subject, mail.html);
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
      else { const ins = await admin.from('customers').insert({ email, email_verified: true, locale: asLocale(b.lang) }); if (ins.error) await admin.from('customers').update({ email_verified: true }).eq('email', email); }
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'send_sms') {
      const phone = toE164(String(b.phone || '')); if (!phone) return J({ error: 'Enter a valid mobile number.' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio_api_key_sid / secret / verify_service_sid'); return J({ error: 'SMS is not configured.' }, 500); }
      if (await phoneRateLimited(phone)) { await logRun('ok', { action, kind, rate_limited: true }, 'rate limit hit: 5+ code requests for this number in the last hour'); return J({ error: 'Too many code requests. Please try again later.' }, 429); }
      // LANDLINE FALLBACK (12 Aug 2026). Twilio Verify refuses SMS to a landline with error 21635,
      // and the only customer on file registered a Dubai landline: Twilio Lookup returns
      // type=landline for +97142587734, and a real send returned HTTP 400 / 21635. So the one
      // button on the screen could never verify him, and create_inquiry's phone_verified gate kept
      // the RFQ door shut. Verify carries the SAME code by voice on Channel=call, which a landline
      // answers - proven by execution against that number (HTTP 201, status pending). Fall back
      // automatically and tell the caller which channel actually carried it, so the screen can say
      // "we are calling you" instead of asking him to watch for an SMS that cannot arrive.
      // Locale: the SMS or voice call speaks the registered language (founder, 14 Sep 2026).
      const vLocale = await registeredLocale(admin, { role: kind, email }, b.lang);
      let channel = String(b.channel || 'sms'); if (channel !== 'sms' && channel !== 'call') channel = 'sms';
      let { r, jd } = await verifySend(tw, phone, channel, vLocale);
      if (jd?.code === 21635 && channel === 'sms') { channel = 'call'; ({ r, jd } = await verifySend(tw, phone, channel, vLocale)); }
      if (!r.ok || jd?.status === 'canceled') { await logRun('error', { action, kind, http: r.status, channel }, 'twilio verify send failed on channel ' + channel + ': ' + String(jd?.message || jd?.status || '').slice(0, 200)); return J({ error: jd?.message || 'Could not send the code.' }, 502); }
      await admin.from('phone_verifications').insert({ email, phone, code: 'twilio', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      await logRun('ok', { action, kind, channel }, '');
      return J({ ok: true, channel });
    }
    if (action === 'verify_sms') {
      const phone = toE164(String(b.phone || '')); const code = String(b.code || '').replace(/\D/g, '');
      if (!phone || !code) return J({ error: 'Enter the 6-digit code.' }, 400);
      const tw = await twilioAuth(); if (!tw) { await logRun('error', { action, kind }, 'SMS not configured: missing twilio credentials'); return J({ error: 'SMS is not configured.' }, 500); }
      if (!(await verifyCheck(tw, phone, code))) return J({ error: 'Incorrect or expired code.' }, 400);
      if (kind === 'supplier') await admin.from('leads').update({ owner_phone_verified: true, phone }).eq('claimed_by', email); else await admin.from('customers').update({ phone_verified: true, phone }).eq('email', email);
      await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    // ---- "Is this number on WhatsApp?" (founder, 14 Sep 2026; pure rules in _shared/whatsapp_choice.ts)
    // Every refusal carries a `code` the portal maps to EN/AR text. Nothing is stored about a number
    // until Twilio approves a code sent to it over WhatsApp itself; only whatsapp_asked_at moves early.
    if (action === 'whatsapp_choose') {
      const opt = parseChoiceOpt(b.opt);
      if (!opt) return J({ ok: false, error: 'bad_opt', code: 'bad_opt' }, 400);
      const mobileVerified = kind === 'supplier' ? !!lead!.owner_phone_verified : !!(cust as any)?.phone_verified;
      const mobile = mobileVerified ? toE164(String((kind === 'supplier' ? lead!.phone : (cust as any)?.phone) || '')) : '';
      const patch = choosePatch(opt, mobile || null, new Date().toISOString());
      if (!patch) return J({ ok: false, error: 'mobile_not_verified', code: 'mobile_not_verified' }, 400);
      if (!(await writeWa(patch))) return saveFailed();
      await logRun('ok', { action, kind, opt }, '');
      return J({ ok: true, whatsapp: whatsappState(patch as WhatsAppRow) });
    }
    if (action === 'whatsapp_send_code') {
      const phone = toE164(String(b.phone || ''));
      if (!phone) return J({ ok: false, error: 'bad_phone', code: 'bad_phone' }, 400);
      const tw = await twilioAuth();
      if (!tw) { await logRun('error', { action, kind }, 'WhatsApp code not sent: missing twilio_api_key_sid / secret / verify_service_sid'); return J({ ok: false, error: 'whatsapp_unavailable', code: 'whatsapp_unavailable' }, 200); }
      if (await phoneRateLimited(phone)) { await logRun('ok', { action, kind, rate_limited: true }, 'rate limit hit: 5+ code requests for this number in the last hour (SMS, call and WhatsApp share it)'); return J({ ok: false, error: 'rate_limited', code: 'rate_limited' }, 429); }
      if (!(await writeWa(askedPatch(new Date().toISOString())))) return saveFailed();
      const { r, jd } = await verifySend(tw, phone, 'whatsapp', await registeredLocale(admin, { role: kind, email }, b.lang));
      if (whatsappUnavailable(r.status, jd)) {
        await logRun('error', { action, kind, http: r.status, twilio_code: jd?.code ?? null }, 'WhatsApp channel unavailable on the Verify service - no code was sent: ' + String(jd?.message || '').slice(0, 200));
        return J({ ok: false, error: 'whatsapp_unavailable', code: 'whatsapp_unavailable', twilio_code: jd?.code ?? null }, 200);
      }
      if (!r.ok || jd?.status === 'canceled') {
        await logRun('error', { action, kind, http: r.status, twilio_code: jd?.code ?? null }, 'twilio verify send failed on channel whatsapp: ' + String(jd?.message || jd?.status || '').slice(0, 200));
        return J({ ok: false, error: 'send_failed', code: 'send_failed', twilio_code: jd?.code ?? null }, 502);
      }
      // The row is the rate-limit ledger shared with send_sms, not a record of the number as the
      // account's WhatsApp - that is written only by whatsapp_verify.
      const pv = await admin.from('phone_verifications').insert({ email, phone, code: 'twilio', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      if (pv.error) await logRun('error', { action, kind, stage: 'phone_verifications' }, 'WhatsApp code sent but the rate-limit row was not written: ' + pv.error.message);
      else await logRun('ok', { action, kind, channel: 'whatsapp' }, '');
      return J({ ok: true, channel: 'whatsapp' });
    }
    if (action === 'whatsapp_verify') {
      const phone = toE164(String(b.phone || '')); const code = String(b.code || '').replace(/\D/g, '');
      if (!phone) return J({ ok: false, error: 'bad_phone', code: 'bad_phone' }, 400);
      if (!code) return J({ ok: false, error: 'wrong_code', code: 'wrong_code' }, 400);
      const tw = await twilioAuth();
      if (!tw) { await logRun('error', { action, kind }, 'WhatsApp code not checked: missing twilio credentials'); return J({ ok: false, error: 'whatsapp_unavailable', code: 'whatsapp_unavailable' }, 200); }
      if (!(await verifyCheck(tw, phone, code))) return J({ ok: false, error: 'wrong_code', code: 'wrong_code' }, 400);
      const patch = verifiedPatch(phone, new Date().toISOString());
      if (!(await writeWa(patch))) return saveFailed();
      const used = await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
      if (used.error) await logRun('error', { action, kind, stage: 'phone_verifications' }, 'WhatsApp number verified but its phone_verifications rows were not marked used: ' + used.error.message);
      else await logRun('ok', { action, kind }, '');
      return J({ ok: true, whatsapp: whatsappState(patch as WhatsAppRow) });
    }
    if (action === 'whatsapp_later') {
      if (!(await writeWa(askedPatch(new Date().toISOString())))) return saveFailed();
      await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }

    if (action === 'accept_terms') {
      // A customer cannot finish the account without an 18+ date of birth on file (account rule).
      if (kind === 'customer') { const dp = dobProblem((cust as any)?.date_of_birth); if (dp) return J({ error: dp, code: dp }, 400); }
      const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();
      const nowIso = new Date().toISOString();
      // ONE SOURCE OF TRUTH FOR THE VERSION (2 Aug 2026, external code review). 'v4' and 'v3' were
      // hard-coded here, supplier_api read app_secrets('terms_version') (a key that did not exist,
      // so it recorded 'v2'), and compliance_archive printed "Version 4" on the certificate. Three
      // independent answers to "which document did this business actually sign?", which is the one
      // question an acceptance record exists to answer. All three now read the same secrets.
      const supV = (await sec('supplier_terms_version')) || (await sec('terms_version')) || 'v5';
      const custV = (await sec('customer_terms_version')) || 'v3';
      if (kind === 'supplier') await admin.from('leads').update({ accepted_terms_at: nowIso, accepted_terms_version: supV, accepted_terms_ip: ip }).eq('claimed_by', email);
      else await admin.from('customers').update({ tos_accepted_at: nowIso, tos_version: custV, tos_ip: ip }).eq('email', email);
      let signed_url = null; let signErr = '';
      try { const secret = await sec('cred_fn_kyc'); const r = await fetch(`${FN}/compliance_archive`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, action: 'sign', kind, email }) }); const jd = await r.json(); signed_url = jd?.signed_url || null; if (!signed_url) signErr = String(jd?.error || jd?.detail || 'no signed_url returned').slice(0, 200); } catch (e) { signErr = String((e as Error)?.message || e).slice(0, 200); }
      // terms acceptance is recorded either way; a missing signed PDF is a compliance-trail gap worth surfacing
      if (!signed_url) await logRun('error', { action, kind, terms_recorded: true, signed_pdf: false }, 'terms accepted but signed PDF not produced: ' + signErr);
      else await logRun('ok', { action, kind, terms_recorded: true, signed_pdf: true }, '');
      return J({ ok: true, signed_url });
    }

    await logRun('error', { action }, 'unknown_action');
    return J({ error: 'unknown_action' }, 400);
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception: ' + m); return J({ error: m }, 500); }
}));
