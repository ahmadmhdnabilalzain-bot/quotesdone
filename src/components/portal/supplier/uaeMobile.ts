// A UAE mobile number as login_otp and kyc hold it: +9715XXXXXXXX (15 Sep 2026, agent: customer_support).
// The sign-up form sent whatever was typed to kyc send_sms and only the SMS failure told the supplier
// the number was wrong. The screen now checks the format first and sends the normalised form.
// Accepted: 05X XXX XXXX, 5X XXX XXXX, +971 5X…, 00971 5X…, 971 5X…, with spaces, dashes, dots or brackets.
// ALSO "+971 050 …" AND ARABIC-INDIC DIGITS (12 Nov 2026, customer_support; browser walk M9, founder ruling 1645): both were
// refused with only the general hint. Many people write the trunk 0 after the country code, and an Arabic keyboard types
// ٠-٩ (U+0660-0669) or the Persian forms ۰-۹ (U+06F0-06F9); each is read as its Western digit. Direction marks are dropped.
// Prevented by: src/components/portal/supplier/uaeMobile.test.mjs.
const westernDigits = (s: string) => s.replace(/[\u0660-\u0669\u06F0-\u06F9]/g, (c) => String(c.charCodeAt(0) & 0xF));
export function uaeMobile(v: unknown): string | null {
  const d = westernDigits(String(v ?? '')).replace(/[\s\-().‎‏‪-‮]/g, '');
  const m = /^(?:(?:\+971|00971|971)0?|0)?(5\d{8})$/.exec(d);
  return m ? '+971' + m[1] : null;
}
