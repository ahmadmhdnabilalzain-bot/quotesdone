// wa_code — a WhatsApp phone code we generate, send and check ourselves (it_engineer, ledger 1252, 27 Oct 2026).
//
// Founder, 18 Oct 2026: "USD 0.17 per OTP is way too much". #1432 sent a UAE mobile code by WhatsApp first, through
// Twilio Verify, and measured this account's prices (_shared/whatsapp_choice.ts header): Verify SMS to +971 USD 0.1176,
// a WhatsApp Authentication-template send USD 0.0157, and Verify's own fee USD 0.05 on every approved code, either
// channel. So a WhatsApp code still cost USD 0.0657, three quarters of it Verify's fee. The estate owns an approved
// Authentication template for this exact message (wa_template_sids.login_code en/ar; Meta writes the body, {{1}} is
// the code, the button copies it), so the code is generated here, its HMAC stored in public.phone_code, the message
// sent through the Messages API with that template, and the answer checked here: USD 0.0157 a code, about a tenth of
// the USD 0.17 the founder saw. SMS and voice stay on Verify (a number with no WhatsApp still gets its code, and the
// failover after an undelivered WhatsApp message is still a Verify SMS).
//
// SAFE BY CONSTRUCTION. Anything that is not a clean send (no template SID, no table yet, Twilio refuses the template,
// a timeout) answers { ok: false } and the caller sends the code by Verify exactly as before, so this can only make a
// code cheaper, never stop one. The code is never stored, logged or returned: only HMAC(purpose|phone|binding|code)
// with otp_hmac_key, so a code issued for one purpose, number or account verifies nothing else. Guesses are counted
// and spent in one statement (fn_phone_code_verify, the email routine's twin): 5 a code, a resend retires the last.
// scripts/sql/a_whatsapp_phone_code_is_sent_by_us_without_the_verify_fee.sql
// prevented by: _shared/wa_code.test.ts, login_otp/own_whatsapp_code.test.ts, login_otp/verify_race.check.ts
import { timedFetch } from './timed_fetch.ts';
import { isDemoPhone } from './demo_identity.ts';
import { statusCallbackUrl } from './twilio_status.ts';
import type { VerifySent } from './whatsapp_choice.ts';

export type WaPurpose = 'login' | 'kyc_phone' | 'kyc_whatsapp';
export type OwnVerdict = 'ok' | 'wrong' | 'expired' | 'burned' | 'no_code' | 'unavailable';
export const OWN_CODE_TTL_S = 600;
export const OWN_CODE_MAX_ATTEMPTS = 5;
// deno-lint-ignore no-explicit-any
type Admin = any;
export type WaCodeDeps = {
  admin: Admin;
  secret: (key: string) => Promise<string | null | undefined>;
  hmac: (s: string) => Promise<string>;     // the caller's otpHash: HMAC-SHA256 with otp_hmac_key
  fetch?: typeof timedFetch;
};

/** Six digits, uniform: a 32-bit draw is rejected above the largest multiple of 1,000,000 (no modulo bias). */
export function newCode(draw: () => number = () => crypto.getRandomValues(new Uint32Array(1))[0]): string {
  const LIMIT = 4_294_000_000;   // 4294 * 10^6 <= 2^32
  for (;;) { const n = draw(); if (n < LIMIT) return String(n % 1_000_000).padStart(6, '0'); }
}

/** What is MACed: the purpose, the number and the account the code was sent for, then the code. */
export const macInput = (purpose: WaPurpose, phone: string, binding: string, code: string) =>
  [purpose, phone, String(binding || '').toLowerCase(), code].join('|');

/** wa_template_sids.login_code -> the SID for the language, English when that language has none. */
export function loginTemplateSid(raw: unknown, lang: string): string | null {
  let map: unknown = raw;
  if (typeof raw === 'string') { try { map = JSON.parse(raw); } catch (_e) { return null; } }
  const lc = (map as Record<string, unknown> | null)?.login_code;
  if (typeof lc === 'string') return /^HX\w{32}$/.test(lc) ? lc : null;
  const o = (lc ?? {}) as Record<string, unknown>;
  const sid = String((lang === 'ar' ? o.ar : o.en) || o.en || '');
  return /^HX\w{32}$/.test(sid) ? sid : null;
}

/** The phone_verifications.code marker for a code we sent: 'qd:whatsapp:<message SID>'. */
export const ownMarker = (sid: string) => 'qd:whatsapp:' + sid;

/** A send we made, in the shape the Verify path hands its callers, so the rest of each action is unchanged. */
export function ownSent(sid: string): VerifySent {
  return { r: { ok: true, status: 201 }, jd: { sid, status: 'pending', channel: 'whatsapp' }, refused: null, ok: true, channel: 'whatsapp' };
}

/** Generate, store (HMAC only) and send one code by the login_code template. { ok:false } = use Verify instead. */
export async function sendOwnWhatsAppCode(d: WaCodeDeps, o: { phone: string; purpose: WaPurpose; binding: string; kind: string; email: string; lang: string }):
  Promise<{ ok: true; sid: string } | { ok: false; why: string }> {
  if (isDemoPhone(o.phone)) return { ok: false, why: 'fixture' };   // callers refuse a fixture first; never texted either way
  const [acct, ks, kk, from, tmpl] = await Promise.all(['twilio_account_sid', 'twilio_api_key_sid', 'twilio_api_key_secret', 'twilio_wa_from', 'wa_template_sids'].map((k) => d.secret(k).catch(() => null)));
  const contentSid = loginTemplateSid(tmpl, o.lang);
  if (!acct || !ks || !kk || !from || !contentSid) return { ok: false, why: 'not_configured' };
  const code = newCode();
  let id: unknown = null;
  try {
    const { data, error } = await d.admin.rpc('fn_phone_code_issue', { p_phone: o.phone, p_purpose: o.purpose, p_hash: await d.hmac(macInput(o.purpose, o.phone, o.binding, code)),
      p_kind: o.kind, p_email: o.email || '', p_ttl_seconds: OWN_CODE_TTL_S });
    if (!error) id = data;
  } catch (_e) { id = null; }   // no otp_hmac_key, no answer
  if (id == null) return { ok: false, why: 'unavailable' };   // the table is not applied yet: Verify carries it
  const form = new URLSearchParams({ From: 'whatsapp:' + (String(from).startsWith('+') ? from : '+' + from), To: 'whatsapp:' + o.phone,
    ContentSid: contentSid, StatusCallback: statusCallbackUrl(), ContentVariables: JSON.stringify({ 1: code }) });
  // StatusCallback, like every other Messages.json send (_shared/twilio_status.ts, 22 Sep 2026): Twilio reports what
  // became of the code message to wa_status. fn_twilio_status_arrived records it only against a notifications row, and
  // a code message has none, so it answers matched:false and records nothing; the SMS failover keeps reading the
  // message itself through ownMessageStatus(). The callback is what lets a refused or undelivered code show up in the
  // wa_status run log instead of Twilio dropping the report.
  try {
    const r = await (d.fetch ?? timedFetch)(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages.json`,
      { method: 'POST', headers: { Authorization: 'Basic ' + btoa(ks + ':' + kk), 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() });
    const j = await r.json().catch(() => ({}));
    const sid = String(j?.sid || '');
    if (!r.ok || !/^(SM|MM)\w{32}$/.test(sid) || /^(failed|undelivered|canceled)$/i.test(String(j?.status || ''))) {
      // the stored code reached nobody: spent at once, so nothing can be guessed against it
      await spend(d, id, 'refused:' + String(j?.code || r.status));
      return { ok: false, why: 'twilio_' + String(j?.code || r.status) };
    }
    await d.admin.rpc('fn_phone_code_sent', { p_id: id, p_message_sid: sid, p_accepted: true }).then(() => {}, () => {});
    return { ok: true, sid };
  } catch (_e) {
    await spend(d, id, 'refused:threw');
    return { ok: false, why: 'send_threw' };
  }
}

const spend = (d: WaCodeDeps, id: unknown, marker: string) =>
  Promise.resolve(d.admin.rpc('fn_phone_code_sent', { p_id: id, p_message_sid: marker, p_accepted: false })).then(() => {}, () => {});

/** Check a code against the newest live code we sent for (phone, purpose). 'unavailable' = no table or no answer. */
export async function checkOwnCode(d: WaCodeDeps, o: { phone: string; purpose: WaPurpose; binding: string; code: string }): Promise<OwnVerdict> {
  if (!/^\d{6}$/.test(o.code)) return 'wrong';
  try {
    const { data, error } = await d.admin.rpc('fn_phone_code_verify', { p_phone: o.phone, p_purpose: o.purpose,
      p_hash: await d.hmac(macInput(o.purpose, o.phone, o.binding, o.code)), p_max_attempts: OWN_CODE_MAX_ATTEMPTS });
    const v = String(data ?? '');
    return error ? 'unavailable' : (['ok', 'wrong', 'expired', 'burned', 'no_code'].includes(v) ? v as OwnVerdict : 'unavailable');
  } catch (_e) { return 'unavailable'; }
}

/** Twilio's delivery status of a message we sent (queued/sent/delivered/read/undelivered/failed), for the SMS failover. */
export async function ownMessageStatus(d: WaCodeDeps, sid: string): Promise<string | null> {
  if (!/^(SM|MM)\w{32}$/.test(sid)) return null;
  const [acct, ks, kk] = await Promise.all(['twilio_account_sid', 'twilio_api_key_sid', 'twilio_api_key_secret'].map((k) => d.secret(k).catch(() => null)));
  if (!acct || !ks || !kk) return null;
  try {
    const r = await (d.fetch ?? timedFetch)(`https://api.twilio.com/2010-04-01/Accounts/${acct}/Messages/${sid}.json`, { headers: { Authorization: 'Basic ' + btoa(ks + ':' + kk) } });
    const j = await r.json().catch(() => ({}));
    return r.ok && j?.status ? String(j.status) : null;
  } catch (_e) { return null; }
}
