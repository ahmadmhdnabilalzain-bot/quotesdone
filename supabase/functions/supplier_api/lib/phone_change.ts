// A VERIFIED MOBILE STAYS VERIFIED ONLY WHILE IT IS THE NUMBER THAT WAS VERIFIED (it_engineer, 9 Nov 2026).
//
// Launch-readiness security assessment, finding H1: save_profile copied `phone` from the request into
// leads.phone and never touched leads.owner_phone_verified. A supplier could therefore replace the number
// they proved by SMS code with any number at all and keep the "verified" flag. Customers pay to see that
// number at the reveal; messages meant for the supplier would go to a stranger; and login_otp refuses the
// real owner's SMS sign-in as ambiguous once two verified rows carry the number. The customer side was
// closed the same way on 13 Aug 2026 (kyc's phone path clears customers.phone_verified).
//
// The rule: when save_profile receives a phone whose digits differ from the number on file, the
// verification is cleared. Re-verifying goes through kyc, which writes the number and the flag together.
// Formatting alone (spaces, dashes, a leading +) is not a change: the comparison is on digits.
// A database trigger cannot carry this rule, because kyc legitimately writes a new number and
// verified = true in one update, which a trigger cannot tell apart from this path.

const digits = (v: unknown) => String(v ?? '').replace(/\D+/g, '');

/** True when the submitted phone is a different number from the one on file. */
export function phoneChanged(onFile: unknown, submitted: unknown): boolean {
  if (submitted === undefined) return false;
  return digits(onFile) !== digits(submitted);
}
