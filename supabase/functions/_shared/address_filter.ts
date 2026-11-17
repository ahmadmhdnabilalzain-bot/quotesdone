// AN IDENTITY IS FOUND BY EQUALITY, NEVER BY A PATTERN (security audit of 17 Nov 2026, finding 1, docs/reports/
// 2026-11-17-security-audit.md; it_engineer).
//
// sales_engineer/lib/caller.ts and site_assistant/index.ts found the signed-in caller's customer row with
// `.ilike('email', email)`, the e-mail unescaped. In a LIKE pattern `_` is any one character and `%` any run, so a
// supplier-portal login `john_smith@x.com` (a session with no customer row of its own) resolved to the customer
// `john.smith@x.com` and read his conversations, signed PDF links and report, and filed disputes in his name.
//
// Escaping `\ % _` is not enough on its own through PostgREST: it rewrites EVERY `*` in a like/ilike value to `%`
// before Postgres sees it, and no escape survives that, so `a*b@x.com` still matched `axyzb@x.com`. An RFC 5321
// local part may carry `*`. So:
//   - a column every writer stores lower-cased is read with `.eq(column, normalEmail(v))`. Measured 17 Nov 2026
//     (SELECT on production): customers.email 4 rows, leads.claimed_by 11 non-null, auth.users.email 34, none
//     with a capital or surrounding space; every writer lower-cases (login_otp, mobile_otp, kyc, signed_in_user.ts),
//     and customers has a unique index on lower(btrim(email)). A row stored otherwise is not found: the miss fails
//     closed, never onto somebody else. customerIdOf and claimedLeadIdOf are those two reads.
//   - a column that is NOT reliably lower-cased (leads.email: 47 of 20,283 carry capitals, scraped listings) is read
//     with whereAddress: an escaped ilike, which is a case-insensitive EQUALITY, or `.eq` on the lower-cased value
//     when the address holds a `*` that no ilike can carry literally.
// The guard that keeps it so: scripts/checks/no_identity_is_matched_by_a_pattern.test.mjs fails on any `.ilike(` or
// `.like(` whose column is an address. A value inside a PostgREST or() string is or_filter_email.ts's subject.

/** The address as the estate stores it: trimmed, lower-cased; '' for nothing. */
export const normalEmail = (v: unknown): string => String(v ?? '').trim().toLowerCase();

/** The LIKE pattern that matches exactly `s` and nothing else (`\`, `%`, `_` escaped), or null when PostgREST cannot
 *  carry it literally: PostgREST turns every `*` of a like/ilike value into `%`. */
export function likeLiteral(s: string): string | null {
  if (s.includes('*')) return null;
  return s.replace(/[\\%_]/g, (c) => '\\' + c);
}

// deno-lint-ignore no-explicit-any
type Narrowable = { eq: (column: string, value: any) => any; ilike: (column: string, pattern: string) => any };

/** Narrows a query to rows whose `column` is the address `email`, case and surrounding space ignored, never as a
 *  pattern. For a column every writer lower-cases, `.eq(column, normalEmail(email))` says the same more plainly. */
// Q is unconstrained on purpose: checking a supabase-js builder against Narrowable is "excessively deep" for TypeScript
// (TS2589 at conversation_archive and resend_inbound, local gate 17 Nov 2026); the cast below is the same check, made once.
export function whereAddress<Q>(q: Q, column: string, email: unknown): Q {
  const v = normalEmail(email);
  const p = likeLiteral(v);
  const n = q as unknown as Narrowable;
  return (p === null ? n.eq(column, v) : n.ilike(column, p)) as Q;
}

type Read = { data?: unknown; error?: unknown };
// deno-lint-ignore no-explicit-any
type Db = { from: (table: string) => any };

async function oneId(r: Promise<Read> | PromiseLike<Read>): Promise<string | null> {
  const { data, error } = await r;
  if (error || !Array.isArray(data) || data.length !== 1) return null;   // exactly one row, or nobody
  const id = (data[0] as { id?: unknown })?.id;
  return id === null || id === undefined ? null : String(id);
}

/** The customers row of a verified address, or null. Exact: `john_smith@x.com` is never `john.smith@x.com`. */
export function customerIdOf(db: Db, email: unknown): Promise<string | null> {
  const e = normalEmail(email);
  return e ? oneId(db.from('customers').select('id').eq('email', e).limit(2)) : Promise.resolve(null);
}

/** The listing a verified address has claimed (leads.claimed_by), or null. Exact, as customerIdOf. */
export function claimedLeadIdOf(db: Db, email: unknown): Promise<string | null> {
  const e = normalEmail(email);
  return e ? oneId(db.from('leads').select('id').eq('claimed_by', e).limit(2)) : Promise.resolve(null);
}
