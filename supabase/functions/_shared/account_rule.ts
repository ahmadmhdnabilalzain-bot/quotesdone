// THE FOUNDER'S ACCOUNT RULE (14 Sep 2026), verbatim:
//   "requests are made only after signing up and we require otp verified mobile/email and we also
//    need the name, date of birth (-18 age is rejected) and the check box for the terms and
//    conditions."
//
// One definition, used by kyc (profile completion) and by every path that creates a customer request
// (customer_api create_inquiry — measured 14 Sep: the only writer of public.inquiries; no DB routine
// inserts into it and anon/authenticated hold no INSERT grant). Kept in one file so the two sides of
// the rule — what the profile accepts and what a request requires — cannot drift apart.
//
// Columns read are public.customers: full_name, date_of_birth (date), email_verified, phone_verified,
// tos_accepted_at (the Terms checkbox, written by kyc accept_terms).

export const MIN_AGE = 18;
export const MAX_AGE = 120;

// Age in whole years on `today`, from a strict YYYY-MM-DD date. Calendar arithmetic in UTC so the
// answer does not move with the server's timezone. Returns null for anything that is not a real date.
export function ageOn(dob: unknown, today: Date = new Date()): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dob ?? '').trim().slice(0, 10));
  if (!m) return null;
  const y = +m[1], mo = +m[2], d = +m[3];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null; // 2026-02-30
  const ty = today.getUTCFullYear(), tm = today.getUTCMonth() + 1, td = today.getUTCDate();
  let a = ty - y;
  if (tm < mo || (tm === mo && td < d)) a--;
  return a;
}

export type DobProblem = 'dob_required' | 'dob_invalid' | 'under_18';

// Why a date of birth is not acceptable, or null when it is. A future date or an age over MAX_AGE is
// dob_invalid (a typo), not under_18.
export function dobProblem(dob: unknown, today: Date = new Date()): DobProblem | null {
  if (dob === null || dob === undefined || String(dob).trim() === '') return 'dob_required';
  const a = ageOn(dob, today);
  if (a === null || a < 0 || a > MAX_AGE) return 'dob_invalid';
  if (a < MIN_AGE) return 'under_18';
  return null;
}

export type CustomerAccount = {
  full_name?: string | null;
  date_of_birth?: string | null;
  email_verified?: boolean | null;
  phone_verified?: boolean | null;
  tos_accepted_at?: string | null;
};

// The items still missing before this customer may create a request. Empty array = allowed.
export function accountMissing(c: CustomerAccount | null | undefined, today: Date = new Date()): string[] {
  const x = c || {};
  const missing: string[] = [];
  if (String(x.full_name || '').trim().length < 2) missing.push('name');
  const p = dobProblem(x.date_of_birth, today);
  if (p) missing.push(p === 'under_18' ? 'age_18_or_over' : 'date_of_birth');
  if (!(x.email_verified === true || x.phone_verified === true)) missing.push('verified_email_or_mobile');
  if (!x.tos_accepted_at) missing.push('terms_accepted');
  return missing;
}
