// whatsapp_choice — the pure half of "Is this number on WhatsApp?" (kyc actions whatsapp_*).
//
// Founder, 14 Sep 2026: "what if the customer has whatsapp on another phone number, maybe we should
// confirm this point through the sign up". After the mobile is verified the customer or supplier
// answers Yes (same) / No, it's a different number (other) / I don't use WhatsApp (none). A different
// number is proven by a code sent OVER WHATSAPP, so an unverified WhatsApp number is never written:
// every patch below that sets whatsapp_phone also sets whatsapp_verified_at in the same object.
// Email stays the identity; nothing here reads or writes a lookup by phone, and leads.whatsapp (a
// legacy scraped number) is deliberately not a column this module knows about.
//
// Columns (customers and leads alike): whatsapp_phone, whatsapp_verified_at, whatsapp_opt
// ('same'|'other'|'none', null = not answered), whatsapp_asked_at. (wa_optin is no longer written: nothing reads it since #657.)
export type WhatsAppOpt = 'same' | 'other' | 'none';
export type ChoiceOpt = 'same' | 'none';

// 'other' is not choosable directly: it is only ever the result of whatsapp_verify approving a code.
export function parseChoiceOpt(v: unknown): ChoiceOpt | null {
  return v === 'same' || v === 'none' ? v : null;
}

export interface WhatsAppRow {
  whatsapp_phone?: string | null;
  whatsapp_verified_at?: string | null;
  whatsapp_opt?: string | null;
  whatsapp_asked_at?: string | null;
}

export function whatsappState(r: WhatsAppRow | null | undefined) {
  const row = r || {};
  const opt = row.whatsapp_opt === 'same' || row.whatsapp_opt === 'other' || row.whatsapp_opt === 'none' ? row.whatsapp_opt : null;
  // A phone with no verification timestamp is reported as absent: the UI must never show, and no
  // sender may use, a number that did not come back with a code.
  const verified = !!row.whatsapp_verified_at && !!row.whatsapp_phone;
  return { opt, phone: verified ? row.whatsapp_phone! : null, verified, asked: !!row.whatsapp_asked_at || opt !== null };
}

// Twilio refusals that mean "Verify cannot use its WhatsApp sender or Authentication template" — and
// ONLY those (founder, 15 Sep 2026: fall back only on the specific template or sender refusal):
//   68008  Verify WhatsApp channel not configured (missing sender / Authentication template, WABA policy)
//   63118  the WhatsApp sender configuration behind the Verify service was not found
//   63008  the WhatsApp channel module is misconfigured
// 60410 (Fraud Guard blocked the attempt) is deliberately NOT here: retrying a fraud block on SMS would
// hand the attacker the second channel. Any other refusal is a send failure, never a false "sent".
const REFUSED_CODES = new Set([68008, 63118, 63008]);
export function whatsappUnavailable(_httpStatus: number, body: { code?: unknown; message?: unknown } | null | undefined): boolean {
  return REFUSED_CODES.has(Number(body?.code));
}

// Which channel actually carried the code. Verify's top-level `channel` echoes what was ASKED for:
// measured 15 Sep 2026 on this service, a Channel=whatsapp send answered 201 with channel:'whatsapp'
// while its only delivery attempt, send_code_attempts[0].channel, was 'sms' — Verify fell back by itself
// because Meta has not approved the Authentication template. The last attempt is the truth.
// deno-lint-ignore no-explicit-any
export function deliveredChannel(jd: any, asked: string): string {
  const a = Array.isArray(jd?.send_code_attempts) ? jd.send_code_attempts : [];
  const last = a.length ? a[a.length - 1] : null;
  return String(last?.channel || jd?.channel || asked);
}

// WhatsApp first on EVERY attempt, SMS to the same number only when Verify refuses the WhatsApp channel
// itself. The day Meta approves the template, the first send starts delivering on WhatsApp and nothing
// here changes. `send` is kyc's Twilio call (or the fixture stand-in); injected so the fallback is
// unit-tested without Twilio.
// deno-lint-ignore no-explicit-any
export type VerifySendResult = { r: { ok: boolean; status: number }; jd: any };
// 18 Sep 2026 (typescript review): the pairing "ok ⇒ channel is a real channel" was true in the code
// and absent from the type, so `channel` inferred as string|null and every caller concatenated a
// possible null. A later edit here could have written 'twilio:null' into phone_verifications.code
// with nothing failing. The union states the pairing, so the compiler enforces it at every caller.
export type VerifySent = VerifySendResult & { refused: number | null }
  & ({ ok: true; channel: string } | { ok: false; channel: null });
export async function sendWhatsAppFirst(send: (channel: 'whatsapp' | 'sms') => Promise<VerifySendResult>): Promise<VerifySent> {
  let res = await send('whatsapp');
  let refused: number | null = null;
  if (whatsappUnavailable(res.r.status, res.jd)) { refused = Number(res.jd?.code); res = await send('sms'); }
  return res.r.ok && res.jd?.status !== 'canceled'
    ? { ...res, refused, ok: true, channel: deliveredChannel(res.jd, refused ? 'sms' : 'whatsapp') }
    : { ...res, refused, ok: false, channel: null };
}

// SMS, THEN VOICE (customer_support, 6 Oct 2026). The sign-in code's last channel. Same rule as the
// WhatsApp->SMS step above (founder, 15 Sep 2026: fall back only on the specific refusal): Verify is
// asked to CALL the number only when it refused SMS because SMS cannot reach that number at all -
//   60205  SMS is not supported to this number (a landline)      21614  not a mobile number
//   21408  no permission to send SMS to this region              21612  this route cannot carry SMS
//   60220  the SMS geo-permission for this country is off
// A fraud block (60410), a rate limit (60203) or any other refusal is NOT retried by voice: the second
// channel must never hand an attacker or a flood a second door.
const SMS_UNREACHABLE = new Set([60205, 21614, 21408, 21612, 60220]);
// deno-lint-ignore no-explicit-any
export function smsUnreachable(jd: any): boolean { return SMS_UNREACHABLE.has(Number(jd?.code)); }
export async function voiceAfterSms(first: VerifySent, send: (channel: 'call') => Promise<VerifySendResult>): Promise<VerifySent> {
  if (first.ok || !smsUnreachable(first.jd)) return first;
  const res = await send('call');
  return res.r.ok && res.jd?.status !== 'canceled'
    ? { ...res, refused: first.refused, ok: true, channel: 'call' }
    : { ...res, refused: first.refused, ok: false, channel: null };
}

// THE CHEAPER CHANNEL FOR A UAE MOBILE CODE, ONLY WHERE WHATSAPP IS KNOWN TO REACH THE PERSON (it_engineer,
// 18 Oct 2026; tightened by the release operator's review of #1432). The founder found USD 0.17 per sign-in code
// too expensive. Measured that day on this account: a Verify SMS to +971 costs USD 0.1176 (Pricing API,
// Etisalat/du/other alike), a Verify WhatsApp Authentication-template send USD 0.0157 (5 Oct attempt,
// message_status DELIVERED), and Verify adds USD 0.05 per approved code on either channel: USD 0.1676 a code
// by SMS, USD 0.0657 by WhatsApp. WhatsApp goes ONLY to a number the account confirmed is on WhatsApp, or to
// the number a signed-in user just typed and chose WhatsApp for (kyc sign-up). Ruling 994: never rely on
// WhatsApp alone, so SMS stays as the failover - see failoverStep below.
//   - the caller asked for 'sms' or 'call'                                 -> that channel
//   - the last code to this number (10 min) went by WhatsApp               -> 'sms' (asking again = not arrived)
//   - not a UAE mobile (+9715XXXXXXXX; a landline has no WhatsApp)         -> 'sms'
//   - the signed-in user chose WhatsApp, or the account confirmed it       -> 'whatsapp'
//   - otherwise                                                            -> 'sms'
// Resends are spaced by RESEND_GAP_S through public.rl_check, which holds a per-key lock since #1432 so two
// concurrent requests cannot both pass.
export const RESEND_GAP_S = 30;
export type FirstChannel = 'whatsapp' | 'sms' | 'call';
export function nextChannel(o: { e164: string; asked?: unknown; lastChannel?: string | null; waConfirmed?: boolean }): FirstChannel {
  if (o.asked === 'sms' || o.asked === 'call') return o.asked;
  if (o.lastChannel === 'whatsapp') return 'sms';
  if (!/^\+9715\d{8}$/.test(o.e164)) return 'sms';
  return o.asked === 'whatsapp' || o.waConfirmed ? 'whatsapp' : 'sms';
}
// AUTOMATIC FAILOVER. Verify gives no per-message status callback, but its Attempts resource reports the
// WhatsApp message's delivery (channel_data.message_status; DELIVERED is what this service returned
// on 18 Oct 2026, READ / UNDELIVERED / FAILED are the other final states and are matched case-insensitively). The portal asks the function at fixed times after a WhatsApp send; the function
// reads that status and sends the SAME code by SMS when Twilio reports the message undelivered or failed, or
// when it is still not delivered FAILOVER_AFTER_S after the send. A delivered message is left alone.
export const FAILOVER_AFTER_S = 45;
export function failoverStep(messageStatus: unknown, ageMs: number): 'none' | 'sms' | 'wait' {
  const s = String(messageStatus || '').toUpperCase();
  if (s === 'DELIVERED' || s === 'READ') return 'none';
  if (s === 'UNDELIVERED' || s === 'FAILED') return 'sms';
  return ageMs >= FAILOVER_AFTER_S * 1000 ? 'sms' : 'wait';
}
// phone_verifications.code holds 'twilio:<delivered channel>[:<Verify verification SID>]' for a Verify send, and
// 'qd:whatsapp:<message SID>' for a WhatsApp code QuotesDone sent itself (_shared/wa_code.ts, ledger 1252). An SMS
// failover after our own WhatsApp code is a Verify send keyed by that message SID: 'twilio:sms:<SM...>'.
export function channelOfRow(code: string | null | undefined): string | null {
  const m = /^(?:twilio:(\w+)(?::(?:VE|SM|MM)\w+)?|qd:(whatsapp):(?:SM|MM)\w+)$/.exec(String(code || ''));
  return m ? (m[1] || m[2]) : null;
}
export function sidOfRow(code: string | null | undefined): string | null {
  const m = /^(?:twilio:\w+|qd:whatsapp):((?:VE|SM|MM)\w+)$/.exec(String(code || ''));
  return m ? m[1] : null;
}
/** True when the row is a WhatsApp code we sent ourselves (its delivery is read from the Messages API, not Verify). */
export const isOwnRow = (code: string | null | undefined) => /^qd:whatsapp:(?:SM|MM)\w+$/.test(String(code || ''));

export type Patch = Record<string, string | boolean | null>;

// whatsapp_choose. Caller has already refused 'same' when the mobile is not verified; verifiedMobile
// is required here too so a patch can never write an unverified number even if that check moves.
export function choosePatch(opt: ChoiceOpt, verifiedMobile: string | null, nowIso: string): Patch | null {
  if (opt === 'same') {
    if (!verifiedMobile) return null;
    return { whatsapp_opt: 'same', whatsapp_phone: verifiedMobile, whatsapp_verified_at: nowIso, whatsapp_asked_at: nowIso };
  }
  return { whatsapp_opt: 'none', whatsapp_phone: null, whatsapp_verified_at: null, whatsapp_asked_at: nowIso };
}

// whatsapp_verify approved. The previously verified number is replaced only here, never at send time.
export function verifiedPatch(phone: string, nowIso: string): Patch {
  return { whatsapp_opt: 'other', whatsapp_phone: phone, whatsapp_verified_at: nowIso, whatsapp_asked_at: nowIso };
}

// whatsapp_later and whatsapp_send_code: existing accounts are asked once and never blocked.
export function askedPatch(nowIso: string): Patch {
  return { whatsapp_asked_at: nowIso };
}
