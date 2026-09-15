// A UAE mobile number as login_otp and kyc hold it: +9715XXXXXXXX (15 Sep 2026, agent: customer_support).
// The sign-up form sent whatever was typed to kyc send_sms and only the SMS failure told the supplier
// the number was wrong. The screen now checks the format first and sends the normalised form.
// Accepted: 05X XXX XXXX, 5X XXX XXXX, +971 5X…, 00971 5X…, 971 5X…, with spaces, dashes, dots or brackets.
export function uaeMobile(v: unknown): string | null {
  const d = String(v ?? '').replace(/[\s\-().]/g, '');
  const m = /^(?:\+971|00971|971|0)?(5\d{8})$/.exec(d);
  return m ? '+971' + m[1] : null;
}
