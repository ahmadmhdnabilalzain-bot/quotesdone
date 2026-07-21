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
async function twilioAuth() { const sid = await sec('twilio_api_key_sid'); const secret = await sec('twilio_api_key_secret'); const va = await sec('twilio_verify_service_sid'); if (!sid || !secret || !va) return null; return { hdr: 'Basic ' + btoa(sid + ':' + secret), va }; }
async function sendEmail(to: string, subject: string, html: string) { const key = await sec('resend_api_key'); if (!key) return false; const from = (await sec('email_from_info')) || 'QuotesDone <info@quotesdone.com>'; try { const r = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ from, to, subject, html }) }); return r.ok; } catch { return false; } }
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
      const emailProven = !!((user as any).email_confirmed_at || (user as any).confirmed_at);
      if (kind === 'supplier') {
        let ev = !!lead!.owner_email_verified;
        if (!ev && emailProven) { await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email); ev = true; }
        return J({ ok: true, kind, email, full_name: lead!.contact_name, phone: lead!.phone, dob: lead!.owner_dob, email_verified: ev, phone_verified: !!lead!.owner_phone_verified, terms_signed: !!lead!.signed_terms_url });
      }
      const c = cust || {} as any;
      let ev = !!c.email_verified;
      if (!ev && emailProven && cust) { await admin.from('customers').update({ email_verified: true }).eq('id', cust.id); ev = true; }
      else if (!ev && emailProven && !cust) {
        // No customers row exists yet. Previously this reported email_verified:true and
        // persisted nothing, so customer_api would later create the row with false - the
        // gate that just passed would then fail on the next call. Persist what we report.
        try { await admin.from('customers').insert({ email, email_verified: true }); }
        catch (_e) { /* a concurrent request may have created it; the reported state is still correct */ }
        ev = true;
      }
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
      const c = code6();
      await admin.from('email_verifications').insert({ email, token: c, purpose: 'kyc', user_kind: kind, expires_at: new Date(Date.now() + 10 * 60e3).toISOString() });
      // previously the send result was discarded: a failed send left the user waiting with no trace
      const sent = await sendEmail(email, 'Confirm your QuotesDone email', wrapCode(c));
      if (!sent) await logRun('error', { action, kind }, 'verification email failed to send (Resend rejected or key missing) - user cannot verify');
      else await logRun('ok', { action, kind }, '');
      return J({ ok: true });
    }
    if (action === 'verify_email') {
      const c = String(b.code || '').replace(/\D/g, '');
      const { data: row } = await admin.from('email_verifications').select('*').eq('email', email).eq('token', c).eq('purpose', 'kyc').is('used_at', null).order('created_at', { ascending: false }).maybeSingle();
      if (!row) return J({ error: 'Incorrect or expired code.' }, 400);
      if (new Date(row.expires_at) < new Date()) return J({ error: 'That code has expired.' }, 400);
      await admin.from('email_verifications').update({ used_at: new Date().toISOString() }).eq('id', row.id);
      if (kind === 'supplier') await admin.from('leads').update({ owner_email_verified: true }).eq('claimed_by', email); else await admin.from('customers').update({ email_verified: true }).eq('email', email);
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
