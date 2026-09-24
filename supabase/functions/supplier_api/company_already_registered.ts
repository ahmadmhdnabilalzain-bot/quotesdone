// A CLAIMED COMPANY CANNOT BE REGISTERED TWICE (24 Sep 2026, sales_engineer).
//
// #944 gave supplier_api one answer for "this company already has an account": 409 with code
// company_already_registered, which the portal renders from serverCopy.ts in the supplier's language.
// scripts/sql/a_claimed_company_cannot_be_registered_twice_under_another_spelling_or_the_same_licence.sql
// adds the database's version of the same rule: two partial unique indexes over claimed leads, one on
// the normalised company name and one on the trade licence number. When either refuses a write, Postgres
// answers 23505 naming the index, and every supplier_api door that can trip them turns that into THIS
// answer -- create_company (inserts a claimed name), claim (makes a listing's name and licence claimed)
// and process_docs (writes the licence number read off the document); save_profile writes neither
// column. It is the same body #944 returns, so the supplier sees the existing message and never a raw
// constraint name or a 500. No new copy was written.
//
// Only these two indexes map here. Any other 23505 on leads (claimed_by, email, claim_token, place_id)
// means something else and keeps its own answer.

export const DUPLICATE_COMPANY_INDEXES = ['leads_claimed_company_name_uidx', 'leads_claimed_trade_licence_uidx'] as const;

export const COMPANY_ALREADY_REGISTERED = {
  error: 'A company with this name is already registered on QuotesDone. If it is yours, sign in with the email used to register it, or write to management@quotesdone.com.',
  code: 'company_already_registered',
} as const;

type PgError = { code?: unknown; message?: unknown; details?: unknown } | null | undefined;

/** True when a PostgREST/Postgres error is a unique violation on one of the duplicate-company indexes. */
export function isDuplicateCompany(err: PgError): boolean {
  if (!err || String(err.code ?? '') !== '23505') return false;
  const text = `${err.message ?? ''} ${err.details ?? ''}`;
  return DUPLICATE_COMPANY_INDEXES.some((name) => text.includes(name));
}
