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
export async function sendWhatsAppFirst(send: (channel: 'whatsapp' | 'sms') => Promise<VerifySendResult>) {
  let res = await send('whatsapp');
  let refused: number | null = null;
  if (whatsappUnavailable(res.r.status, res.jd)) { refused = Number(res.jd?.code); res = await send('sms'); }
  const ok = res.r.ok && res.jd?.status !== 'canceled';
  return { ...res, ok, refused, channel: ok ? deliveredChannel(res.jd, refused ? 'sms' : 'whatsapp') : null };
}

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
