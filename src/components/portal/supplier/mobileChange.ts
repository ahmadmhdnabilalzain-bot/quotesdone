// A NEW MOBILE NUMBER IS NOT VERIFIED UNTIL ITS CODE IS TYPED, AND THE VERIFIED ONE STAYS UNTIL THEN (12 Nov 2026, sales_engineer,
// built by it_engineer; walk of 12 Nov 2026, blocker B2; founder ruling 1645).
// The walk typed another number into Profile: the line still said "Mobile verified" with no way to verify (it keyed on kyc's flag,
// never on the box), and Save then wrote the new number with owner_phone_verified = false while the page said "Changes saved." A
// mandatory registration item was lost unseen, and a customer paying for the reveal would get an unproven number.
// Now the box is compared with the number kyc proved: a different number reads "not verified" at once, offers the same WhatsApp/SMS
// code registration uses (kyc send_sms / verify_sms, which writes the number and the flag together), and Save leaves the verified
// number in force (save_profile keeps it too: supplier_api/lib/phone_change.ts), saying so, so his standing never changes unseen.
// The state words are Settings' (PR #1984): "Mobile number", "verified", "verified by WhatsApp code", "not verified". English only.
// Guard: src/components/portal/supplier/mobileChange.test.mjs
import { uaeMobile } from './uaeMobile.ts';

const digits = (v: unknown): string => String(v ?? '').replace(/\D/g, '');
const asHeld = (v: unknown): string => digits(uaeMobile(v) ?? v);

/** True when a verified number is on file and the box now holds a different one (formatting alone is not a change). */
export function numberChanged(proven: unknown, typed: unknown): boolean {
  const p = asHeld(proven);
  return p !== '' && asHeld(typed) !== p;
}

/** The verified line: by WhatsApp code when kyc's WhatsApp answer is verified for this same number. */
export function verifiedWords(proven: unknown, wa: unknown): string {
  const w = wa as { verified?: unknown; phone?: unknown } | null | undefined;
  return w && w.verified === true && asHeld(w.phone) !== '' && asHeld(w.phone) === asHeld(proven)
    ? 'Mobile number verified by WhatsApp code' : 'Mobile number verified';
}

/** A held number as people read it: +971 50 123 4567 (anything else as it is). */
export function shownNumber(v: unknown): string {
  const m = /^\+971(5\d)(\d{3})(\d{4})$/.exec(uaeMobile(v) ?? '');
  return m ? `+971 ${m[1]} ${m[2]} ${m[3]}` : String(v ?? '');
}

export const MOBILE_CHANGE = {
  not_verified: (proven: string) => `This number is not verified yet. Your verified number ${shownNumber(proven)} stays on your account until you type the code we send to the new number.`,
  keep: 'Keep my verified number',
  saved_kept: (proven: string) => `Your mobile number is still ${shownNumber(proven)}: the new number takes its place once you type its code.`,
} as const;
