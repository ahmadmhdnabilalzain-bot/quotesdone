// THE UAE MOBILE RULE, SERVER SIDE (audit 22 Sep 2026, SP-A-05; agent: customer_support).
//
// TWIN: src/components/portal/supplier/uaeMobile.ts. The regex below is that file's regex,
// character for character; change one and change the other, or the sign-up form and the function
// behind it disagree about what a UAE mobile number is.
//
// Why this file exists: the browser checked the format and kyc did not. kyc's toE164 accepts any
// 8+ digits, so a caller posting straight to kyc send_sms (or a form bypassed by a stale client)
// could hand Twilio a junk number; Verify accepts the request, the SMS never arrives, and the
// supplier sits on a verification step that cannot complete with nothing on screen saying why.
//
// Accepted: 05X XXX XXXX, 5X XXX XXXX, +971 5X…, 00971 5X…, 971 5X…, with spaces, dashes, dots or
// brackets. Everything else returns null and the caller refuses with the stable code `bad_mobile`.
export function uaeMobile(v: unknown): string | null {
  const d = String(v ?? '').replace(/[\s\-().]/g, '');
  const m = /^(?:\+971|00971|971|0)?(5\d{8})$/.exec(d);
  return m ? '+971' + m[1] : null;
}
