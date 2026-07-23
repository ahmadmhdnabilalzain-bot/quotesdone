import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const FN = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
function emailOk(e: string) { return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(e || '')); }
function ageFrom(dob: string): number | null { const d = new Date(dob); if (isNaN(d.getTime())) return null; const t = new Date(); let a = t.getFullYear() - d.getFullYear(); const m = t.getMonth() - d.getMonth(); if (m < 0 || (m === 0 && t.getDate() < d.getDate())) a--; return a; }
function clientIp(req: Request): string { return (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || req.headers.get('cf-connecting-ip') || req.headers.get('x-real-ip') || ''; }
function toE164(p: string): string { let d = String(p || '').replace(/[^\d+]/g, ''); if (d.startsWith('+')) { const n = d.slice(1).replace(/\D/g, ''); return n.length >= 8 ? '+' + n : ''; } d = d.replace(/\D/g, ''); if (d.startsWith('00')) d = d.slice(2); if (d.startsWith('971')) return '+' + d; if (d.startsWith('0')) return '+971' + d.slice(1); if (d.length === 9 && d.startsWith('5')) return '+971' + d; if (d.length >= 8) return '+' + d; return ''; }
function tok() { const b = new Uint8Array(32); crypto.getRandomValues(b); return [...b].map((x) => x.toString(16).padStart(2, '0')).join(''); }
async function siteUrl() { return (await sec('public_site_url')) || 'https://quotesdone.com'; }
async function uidByEmail(email: string): Promise<string | null> { try { const { data } = await admin.rpc('auth_uid_by_email', { p_email: email }); return (data as string) || null; } catch { return null; } }
async function sendEmail(to: string, subject: string, html: string, kind: string) { const key = await sec('resend_api_key'); if (!key) return false; const from = kind === 'supplier' ? ((await sec('email_from_supplier')) || 'QuotesDone <info@quotesdone.com>') : ((await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>'); const reply = (await sec('email_reply_info')) || 'info@quotesdone.com'; try { const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ from, to, subject, html, reply_to: reply }) }); return r.ok; } catch { return false; } }
function wrap(title: string, intro: string, btnText: string, btnUrl: string, foot: string) { const logo = 'https://htdblwldjkcgjvmqkbeh.supabase.co/storage/v1/object/public/brand/icon_192.png'; return `<div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;color:#1f2937"><div style="text-align:center;padding:18px 0"><img src="${logo}" width="44" height="44" alt="QuotesDone"></div><div style="background:#fff;border:1px solid #eef0f2;border-radius:14px;padding:26px"><h1 style="font-size:20px;color:#111827;margin:0 0 10px">${title}</h1><p style="font-size:15px;line-height:1.6">${intro}</p><div style="text-align:center;margin:22px 0"><a href="${btnUrl}" style="background:#0d9488;color:#fff;text-decoration:none;padding:12px 26px;border-radius:10px;font-weight:700;display:inline-block">${btnText}</a></div><p style="font-size:12px;color:#6b7280">If the button doesn’t work, copy this link:<br><a href="${btnUrl}" style="color:#0d9488;word-break:break-all">${btnUrl}</a></p>${foot ? `<p style="font-size:12px;color:#6b7280;margin-top:14px">${foot}</p>` : ''}</div><p style="text-align:center;font-size:11px;color:#9aa1ab;margin-top:14px">QuotesDone Technologies · Dubai, UAE</p></div>`; }
async function recentTokenCount(email: string) { const since = new Date(Date.now() - 3600e3).toISOString(); const { count } = await admin.from('email_verifications').select('id', { count: 'exact', head: true }).eq('email', email).gte('created_at', since); return count || 0; }
async function twilioAuth() { const sid = await sec('twilio_api_key_sid'); const secret = await sec('twilio_api_key_secret'); const va = await sec('twilio_verify_service_sid'); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({})); const action = String(body.action || '');

    if (action === 'signup_customer' || action === 'signup_supplier') {
      const kind = action === 'signup_supplier' ? 'supplier' : 'customer';
      const email = String(body.email || '').trim().toLowerCase();
      const password = String(body.password || '');
      const full_name = String(body.full_name || '').trim().slice(0, 120);
      const phone = String(body.phone || '').trim().slice(0, 40);
      const dob = String(body.dob || '').trim();
      const company_name = kind === 'supplier' ? String(body.company_name || '').trim().slice(0, 160) : '';
      if (!emailOk(email)) return J({ error: 'Please enter a valid email address.' }, 400);
      if (password.length < 8) return J({ error: 'Password must be at least 8 characters.' }, 400);
      if (!full_name || full_name.length < 2) return J({ error: 'Please enter your name.' }, 400);
      if (!phone || phone.replace(/\D/g, '').length < 7) return J({ error: 'Please enter a valid mobile number.' }, 400);
      const age = ageFrom(dob);
      if (age === null) return J({ error: 'Please enter your date of birth.' }, 400);
      if (age < 18) return J({ error: 'You must be at least 18 years old to use QuotesDone.' }, 403);
      if (age > 120) return J({ error: 'Please enter a valid date of birth.' }, 400);
      if (!body.accept_terms) return J({ error: 'Please accept the Terms & Conditions to continue.' }, 400);
      if (kind === 'supplier' && company_name.length < 2) return J({ error: 'Please enter your company name.' }, 400);
      if (kind === 'customer') { const { data: c } = await admin.from('customers').select('email_verified').eq('email', email).maybeSingle(); if (c && c.email_verified) return J({ error: 'An account with this email already exists. Please sign in or reset your password.' }, 409); }
      else { const { data: l } = await admin.from('leads').select('owner_email_verified').eq('claimed_by', email).maybeSingle(); if (l && l.owner_email_verified) return J({ error: 'An account with this email already exists. Please sign in or reset your password.' }, 409); }
      if (await recentTokenCount(email) >= 6) return J({ error: 'Too many attempts. Please try again later.' }, 429);
      let uid = await uidByEmail(email);
      if (!uid) { const cr = await admin.auth.admin.createUser({ email, password, email_confirm: true }); if (cr.error || !cr.data?.user) return J({ error: 'Could not create account. ' + (cr.error?.message || '') }, 500); uid = cr.data.user.id; }
      else {
        // SECURITY FIX (18 Jul 2026): this branch previously called
        //   admin.auth.admin.updateUserById(uid, { password, email_confirm: true })
        // which let ANY unauthenticated caller overwrite the password of any existing
        // auth user whose profile row was not yet flagged verified - a full account
        // takeover, including admin accounts (which have no profile row at all, so the
        // guard above could never fire). Signup must never mutate an existing account.
        // Legitimate recovery is forgot_password -> emailed token -> reset_password.
        return J({ error: 'An account with this email already exists. Please sign in, or use "Forgot password" to reset it.' }, 409);
      }
      const ip = clientIp(req); const tosv = kind === 'supplier' ? 'v4' : 'v3'; const nowIso = new Date().toISOString();
      if (kind === 'customer') {
        const { data: ex } = await admin.from('customers').select('id').eq('email', email).maybeSingle();
        const row = { email, full_name, phone, date_of_birth: dob, email_verified: false, tos_accepted_at: nowIso, tos_version: tosv, tos_ip: ip };
        if (ex) await admin.from('customers').update(row).eq('id', ex.id); else await admin.from('customers').insert(row);
      } else {
        const { data: ex } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
        const baseRow = { company_name, contact_name: full_name, signatory_name: full_name, phone, owner_dob: dob, claimed: true, claimed_by: email, email, owner_email_verified: false, business_role: 'supplier', accepted_terms_at: nowIso, accepted_terms_version: tosv, accepted_terms_ip: ip, portal_updated_at: nowIso };
        if (ex) await admin.from('leads').update(baseRow).eq('id', ex.id);
        else { const ins = await admin.from('leads').insert({ ...baseRow, source: 'self_registered', scraped_at: nowIso.slice(0, 10) }).select('id').maybeSingle();
          try { const lid = ins.data?.id; if (lid) { const { data: cfg } = await admin.from('pricing_config').select('supplier_free_count,supplier_reg_fee').eq('id', 1).maybeSingle(); const { data: cnt } = await admin.rpc('registered_supplier_count'); const free = (Number(cnt) || 0) < (Number(cfg?.supplier_free_count) || 1000); const yr = 365 * 864e5; if (free) await admin.from('leads').update({ registration_status: 'free', registration_fee_due: 0, registration_paid_at: nowIso, registration_expires_at: new Date(Date.now() + yr).toISOString() }).eq('id', lid); else await admin.from('leads').update({ registration_status: 'due', registration_fee_due: Number(cfg?.supplier_reg_fee) || 100 }).eq('id', lid); } } catch (_e) { /* */ }
        }
      }
      const t = tok();
      await admin.from('email_verifications').insert({ email, token: t, purpose: 'signup', user_kind: kind, expires_at: new Date(Date.now() + 24 * 3600e3).toISOString() });
      const base = await siteUrl(); const link = `${base}${kind === 'supplier' ? '/suppliers' : '/app'}?verify=${t}`;
      const first = full_name.split(' ')[0] || 'there';
      const html = wrap('Confirm your email', `Hi ${first}, thanks for signing up to QuotesDone. Please confirm your email address to activate your account.`, 'Confirm my email', link, 'This link expires in 24 hours. If you didn’t create this account, you can ignore this email.');
      await sendEmail(email, 'Confirm your QuotesDone email', html, kind);
      const smsOn = (await sec('sms_enabled')) === 'true';
      return J({ ok: true, email, user_kind: kind, phone, sms_required: smsOn, message: 'Check your email for a confirmation link.' });
    }

    if (action === 'verify_email') {
      const t = String(body.token || ''); if (!t) return J({ error: 'Invalid link.' }, 400);
      const { data: row } = await admin.from('email_verifications').select('*').eq('token', t).eq('purpose', 'signup').maybeSingle();
      if (!row) return J({ error: 'This confirmation link is invalid.' }, 400);
      if (row.used_at) return J({ ok: true, already: true, user_kind: row.user_kind });
      if (new Date(row.expires_at) < new Date()) return J({ error: 'This link has expired. Please request a new one.' }, 400);
      await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
      if (row.user_kind === 'customer') await admin.from('customers').update({ email_verified: true }).eq('email', row.email);
      else await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', row.email);
      return J({ ok: true, user_kind: row.user_kind, email: row.email });
    }

    if (action === 'resend_verification') {
      const email = String(body.email || '').trim().toLowerCase(); const kind = body.user_kind === 'supplier' ? 'supplier' : 'customer';
      if (!emailOk(email)) return J({ error: 'Invalid email.' }, 400);
      let verified = false, name = '';
      if (kind === 'customer') { const { data: c } = await admin.from('customers').select('email_verified,full_name').eq('email', email).maybeSingle(); verified = !!c?.email_verified; name = c?.full_name || ''; }
      else { const { data: l } = await admin.from('leads').select('owner_email_verified,contact_name').eq('claimed_by', email).maybeSingle(); verified = !!l?.owner_email_verified; name = l?.contact_name || ''; }
      if (verified) return J({ ok: true, already: true, message: 'Your email is already verified — please sign in.' });
      if (await recentTokenCount(email) >= 6) return J({ error: 'Too many emails sent. Please try again later.' }, 429);
      const t = tok(); await admin.from('email_verifications').insert({ email, token: t, purpose: 'signup', user_kind: kind, expires_at: new Date(Date.now() + 24 * 3600e3).toISOString() });
      const base = await siteUrl(); const link = `${base}${kind === 'supplier' ? '/suppliers' : '/app'}?verify=${t}`;
      await sendEmail(email, 'Confirm your QuotesDone email', wrap('Confirm your email', `Hi ${(name.split(' ')[0] || 'there')}, here is a fresh link to confirm your email and activate your QuotesDone account.`, 'Confirm my email', link, 'This link expires in 24 hours.'), kind);
      return J({ ok: true, message: 'Verification email sent.' });
    }

    if (action === 'forgot_password') {
      const email = String(body.email || '').trim().toLowerCase(); const kind = body.user_kind === 'supplier' ? 'supplier' : 'customer';
      if (!emailOk(email)) return J({ error: 'Invalid email.' }, 400);
      const uid = await uidByEmail(email);
      if (uid && (await recentTokenCount(email)) < 6) { const t = tok(); await admin.from('email_verifications').insert({ email, token: t, purpose: 'reset', user_kind: kind, expires_at: new Date(Date.now() + 3600e3).toISOString() }); const base = await siteUrl(); const link = `${base}${kind === 'supplier' ? '/suppliers' : '/app'}?reset=${t}`; await sendEmail(email, 'Reset your QuotesDone password', wrap('Reset your password', 'We received a request to reset your QuotesDone password. Click below to choose a new one. This link expires in 1 hour.', 'Reset password', link, 'If you didn’t request this, you can safely ignore this email.'), kind); }
      return J({ ok: true, message: 'If that email has an account, a reset link has been sent.' });
    }

    if (action === 'reset_password') {
      const t = String(body.token || ''); const password = String(body.password || '');
      if (password.length < 8) return J({ error: 'Password must be at least 8 characters.' }, 400);
      const { data: row } = await admin.from('email_verifications').select('*').eq('token', t).eq('purpose', 'reset').maybeSingle();
      if (!row) return J({ error: 'This reset link is invalid.' }, 400);
      if (row.used_at) return J({ error: 'This reset link has already been used.' }, 400);
      if (new Date(row.expires_at) < new Date()) return J({ error: 'This reset link has expired.' }, 400);
      const uid = await uidByEmail(row.email); if (!uid) return J({ error: 'Account not found.' }, 404);
      await admin.auth.admin.updateUserById(uid, { password, email_confirm: true });
      await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
      if (row.user_kind === 'customer') await admin.from('customers').update({ email_verified: true }).eq('email', row.email);
      else await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', row.email);
      return J({ ok: true, user_kind: row.user_kind, message: 'Your password has been reset. You can now sign in.' });
    }

    if (action === 'sms_send') {
      const smsOn = (await sec('sms_enabled')) === 'true';
      const email = String(body.email || '').trim().toLowerCase(); const kind = body.user_kind === 'supplier' ? 'supplier' : 'customer';
      if (!smsOn) return J({ ok: true, sms_enabled: false, skipped: true });
      const phone = toE164(String(body.phone || '').trim());
      if (!phone) return J({ error: 'Please enter a valid mobile number.' }, 400);
      const since = new Date(Date.now() - 3600e3).toISOString();
      const { count } = await admin.from('phone_verifications').select('id', { count: 'exact', head: true }).eq('phone', phone).gte('created_at', since);
      if ((count || 0) >= 5) return J({ error: 'Too many code requests. Please try again in a little while.' }, 429);
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS is not configured.' }, 500);
      try {
        const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/Verifications`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Channel: 'sms' }) });
        const jd = await r.json();
        if (!r.ok || jd?.status === 'canceled') return J({ error: jd?.message || 'Could not send the SMS code. Check the number and try again.', code: jd?.code || null }, 502);
        await admin.from('phone_verifications').insert({ email, phone, code: 'twilio', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
        return J({ ok: true, sms_enabled: true, phone, message: 'We sent a 6-digit code by SMS.' });
      } catch (e) { return J({ error: 'Could not send the SMS code.', detail: String((e as Error)?.message || e) }, 502); }
    }
    if (action === 'sms_verify') {
      const smsOn = (await sec('sms_enabled')) === 'true';
      const email = String(body.email || '').trim().toLowerCase(); const kind = body.user_kind === 'supplier' ? 'supplier' : 'customer';
      if (!smsOn) return J({ ok: true, sms_enabled: false, skipped: true });
      const phone = toE164(String(body.phone || '').trim()); const code = String(body.code || '').trim().replace(/\D/g, '');
      if (!phone || !code) return J({ error: 'Enter the 6-digit code.' }, 400);
      const tw = await twilioAuth(); if (!tw) return J({ error: 'SMS is not configured.' }, 500);
      try {
        const r = await fetch(`https://verify.twilio.com/v2/Services/${tw.va}/VerificationCheck`, { method: 'POST', headers: { 'Authorization': tw.hdr, 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ To: phone, Code: code }) });
        const jd = await r.json();
        if (jd?.status === 'approved') {
          if (kind === 'customer' && email) await admin.from('customers').update({ phone_verified: true }).eq('email', email);
          await admin.from('phone_verifications').update({ used_at: new Date().toISOString() }).eq('phone', phone).is('used_at', null);
          return J({ ok: true, verified: true });
        }
        return J({ error: 'Incorrect or expired code. Please try again.' }, 400);
      } catch (e) { return J({ error: 'Verification failed, please try again.', detail: String((e as Error)?.message || e) }, 502); }
    }

    return J({ error: 'Unknown action' }, 400);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
