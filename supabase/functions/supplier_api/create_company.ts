// THE INVITED COMPANY IS CLAIMED, NEVER REGISTERED A SECOND TIME (28 Oct 2026, sales_engineer; founder ledger 1401, the
// supplier-journey audit, scenario S7).
//
// MEASURED on production, 28 Oct 2026 07:54Z, run tag aub990b4a: a ZZ DEMO lead invited at qd-…@example.invalid signed
// up on the website with that same address (the real login_otp verify), supplier_api `me` answered null, so the portal
// showed "Register your company", and create_company answered HTTP 500
//   {"error":"duplicate key value violates unique constraint \"uq_leads_email_lower\""}
// leads.email is unique (uq_leads_email_lower) and create_company INSERTED a new lead for the account's address, which
// the invited lead already holds. The portal printed that Postgres sentence to the supplier (serverCopy.ts srvMsg shows
// any `error` that contains a space). The invitation (variant A) carries no link, and fn_supplier_invite_candidates says
// in its own header "a supplier registers at quotesdone.com or replies": registering on the website with the invited
// address is the path the campaign expects, and it was closed to every invited company.
//
// THE RULE NOW, before anything is inserted, from the lead that already holds the account's address (compared
// case-insensitively, exactly as uq_leads_email_lower compares it):
//   * claimed_by is null, and the account's address is proven by its sign-in code (email_verifications, purpose login,
//     used) -> that lead is CLAIMED IN PLACE with what the form says (company name, trade, role, emirate): the same row,
//     so its id, claim token, invitation and outreach history stay attached. The code that reached that mailbox is the
//     same proof the invitation's /portal?t= link is: the link was only ever sent to that mailbox. ONE statement does
//     it (update ... where id = $1 and claimed_by is null), so of two sign-ups racing for the row exactly one wins and
//     the other is told the address already has an account;
//   * claimed by another account (or any other e-mail clash) -> 409 email_already_registered, never a second row;
//   * unclaimed but the address not proven -> 403 verify_email_first (a sign-in by code always proves it: this is
//     the fail-closed answer for anything else);
//   * no lead holds the address -> registered as before (insert), after the claimed-name twin check.
// Any write the database still refuses gets a stable code; the Postgres message goes to the function log only.
// Afterwards the supplier is where a /portal?t= claim leaves him: a claimed company, owner_email_verified, and the
// same registration, licence and verification flow (setRegistration, the first touch).
//
// REVIEW OF #1712 (28 Oct 2026, sales_engineer; read on production the same morning):
//   * A "USED" CODE ROW IS NOT A VERIFIED CODE. email_verifications.used_at is also set when a resend retires the
//     older code (fn_login_otp_email_issue) and when a code is burned at the attempt cap (fn_login_otp_email_verify),
//     so emailProven() is true for any address someone has merely asked two codes for. And a session need not come
//     from a code: the auth config allows public sign-up with a password (disable_signup false), and 30 of 95
//     sessions recorded in auth.mfa_amr_claims are 'password' ones (the harness signs in that way). So the CLAIM also
//     needs THIS session to have been opened by a one-time code sent to the address: sessionOpenedByCode() reads the
//     JWT's amr, which login_otp's sessions carry as 'otp' (65 of 95). A fresh registration (insert) only records
//     the proof, as before; nothing else changed for it.
//   * A failed look-up answers register_failed. It used to read as "no lead holds the address", insert, and meet
//     uq_leads_email_lower: the invited supplier was told "this e-mail already has an account — sign in instead"
//     while signed in.
//   * A sanctioned listing is never claimed: fn_sanctioned_identity excludes the row's own id, so the trigger
//     a01_leads_sanctioned_identity_cannot_re_register does not stop a claim of the banned row itself.
//   * The listing keeps its own trade description (business_role manufacturer, contractor, ...: 3,090 unclaimed
//     leads); the form always sends the constant 'supplier', so it is written only where the lead has none.
//   * index.ts `claim` (/portal?t=) writes under the same guard, so a website sign-up and a token claim racing for
//     one listing have exactly one winner too.
import { COMPANY_ALREADY_REGISTERED, isDuplicateCompany, registrationRefusal, type PgError } from '../_shared/duplicate_company.ts';
import { SANCTIONED_REGISTRATION_REFUSAL } from '../_shared/sanctioned.ts';

export const EMAIL_ALREADY_REGISTERED = {
  error: 'This e-mail already has an account — sign in instead.',
  code: 'email_already_registered',
} as const;
export const VERIFY_EMAIL_FIRST = {
  error: 'Please verify your work e-mail with the 6-digit code we send you, then register your company.',
  code: 'verify_email_first',
} as const;
export const REGISTER_FAILED = {
  error: 'We could not register your company. Please try again, or write to management@quotesdone.com.',
  code: 'register_failed',
} as const;

export type EmailLead = { id: number | string; claimed: boolean | null; claimed_by: string | null; business_role?: string | null };
export type CreatePlan =
  | { kind: 'company_exists' }
  | { kind: 'claim_invited'; lead: EmailLead }
  | { kind: 'email_taken' }
  | { kind: 'verify_email_first' }
  | { kind: 'insert' };

/** What create_company does for this account, from three facts. Pure; create_company.test.ts replays S7. */
export function planCreateCompany(o: { ownCompany: boolean; emailLeads: EmailLead[]; emailProven: boolean }): CreatePlan {
  if (o.ownCompany) return { kind: 'company_exists' };
  if (o.emailLeads.length > 1) return { kind: 'email_taken' };   // uq_leads_email_lower allows one; never guess between two
  const lead = o.emailLeads[0];
  if (!lead) return { kind: 'insert' };
  if (lead.claimed_by != null && String(lead.claimed_by).trim() !== '') return { kind: 'email_taken' };
  return o.emailProven ? { kind: 'claim_invited', lead } : { kind: 'verify_email_first' };
}

const EMAIL_INDEX = 'uq_leads_email_lower';
const CLAIMED_BY_INDEX = 'leads_claimed_by_lower_uidx';
const clashOn = (e: PgError, idx: string) => !!e && String(e.code ?? '') === '23505' && `${e.message ?? ''} ${e.details ?? ''}`.includes(idx);
const ilikeExact = (s: string) => s.replace(/[\\%_]/g, (c) => '\\' + c);

/** The methods a session opened by a one-time code or link sent to the address carries in its JWT amr. */
const CODE_METHODS = new Set(['otp', 'magiclink']);
/**
 * True when THIS session was opened by a one-time code or link sent to its address (amr 'otp' / 'magiclink'), never by
 * a password. Read only from a token auth.getUser has already verified (supplier_api does so before any action).
 */
export function sessionOpenedByCode(jwt: string): boolean {
  try {
    const part = String(jwt || '').split('.')[1] || '';
    if (!part) return false;
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (part.length % 4)) % 4);
    const claims = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
    const amr = Array.isArray(claims?.amr) ? claims.amr : [];
    return amr.some((m: { method?: unknown } | null) => CODE_METHODS.has(String(m?.method ?? '')));
  } catch {
    return false;
  }
}

// The few supabase-js calls this makes, so create_company.test.ts can hand in an in-memory table.
// deno-lint-ignore no-explicit-any
type Db = any;
export type CreateDeps = {
  emailProven: (email: string) => Promise<boolean>;
  /** sessionOpenedByCode(jwt) for this request: the claim needs it as well as emailProven. */
  sessionByCode: boolean;
  /** _shared/sanctioned.ts sanctionedLead: a listing under a confirmed sanctions ban is never claimed. */
  sanctionedLead: (leadId: number) => Promise<boolean>;
  setRegistration: (leadId: number) => Promise<unknown>;
  recordFirstTouch: (leadId: number, touch: unknown) => Promise<void>;
  locale: string;
};

const lookupFailed = (what: string, error: PgError) => {
  console.error(`create_company: ${what} failed —`, error?.message);
  return { status: 500, body: { ...REGISTER_FAILED } };
};

/** supplier_api create_company: { status, body } for the handler to answer. */
export async function createCompany(admin: Db, email: string, body: Record<string, unknown>, deps: CreateDeps): Promise<{ status: number; body: Record<string, unknown> }> {
  const { data: existing, error: ownErr } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
  if (ownErr) return lookupFailed('the account\'s company look-up', ownErr);
  const name = String(body.company_name || '').trim().slice(0, 160);
  if (!existing && name.length < 2) return { status: 400, body: { error: 'Enter your company name.', code: 'enter_company' } };
  let held: EmailLead[] = [];
  if (!existing) {
    const { data, error } = await admin.from('leads').select('id,claimed,claimed_by,business_role').ilike('email', ilikeExact(email)).limit(2);
    if (error) return lookupFailed('the look-up of the lead holding the address', error);
    held = (data || []) as EmailLead[];
  }
  const proven = existing ? false : await deps.emailProven(email);
  // The claim takes an address proven by a used code AND a session opened by a code (header, review of #1712).
  const plan = planCreateCompany({ ownCompany: !!existing, emailLeads: held, emailProven: proven && deps.sessionByCode === true });
  if (plan.kind === 'company_exists') return { status: 409, body: { error: 'Your account already manages a company.', code: 'company_exists' } };
  if (plan.kind === 'email_taken') return { status: 409, body: { ...EMAIL_ALREADY_REGISTERED } };
  if (plan.kind === 'verify_email_first') return { status: 403, body: { ...VERIFY_EMAIL_FIRST } };
  // A COMPANY ALREADY CLAIMED IS NOT REGISTERED TWICE (24 Sep 2026, ledger 993): case- and space-folded, exact. It
  // applies to the claim too, because the claim writes the name the form gives.
  const { data: twins } = await admin.from('leads').select('id').eq('claimed', true).ilike('company_name', ilikeExact(name.replace(/\s+/g, ' '))).limit(1);
  if (twins && twins.length) return { status: 409, body: { ...COMPANY_ALREADY_REGISTERED } };
  const refused = (error: PgError) => {
    console.error('create_company: the database refused the write —', error?.message);
    if (clashOn(error, EMAIL_INDEX) || clashOn(error, CLAIMED_BY_INDEX)) return { status: 409, body: { ...EMAIL_ALREADY_REGISTERED } };
    if (isDuplicateCompany(error)) return { status: 409, body: { ...COMPANY_ALREADY_REGISTERED } };
    if (String(error?.message || '').includes('SANCTIONED_PARTY_BLOCKED')) return { status: 403, body: { ...SANCTIONED_REGISTRATION_REFUSAL } };
    return { status: 500, body: { ...REGISTER_FAILED } };
  };
  if (plan.kind === 'claim_invited') {
    const id = Number(plan.lead.id);
    if (await deps.sanctionedLead(id)) return { status: 403, body: { ...SANCTIONED_REGISTRATION_REFUSAL } };
    const upd: Record<string, unknown> = { claimed: true, claimed_by: email, owner_email_verified: true, company_name: name,
      portal_updated_at: new Date().toISOString() };
    if (!String(plan.lead.business_role ?? '').trim()) upd.business_role = body.role || 'supplier';   // the listing's own description stays
    if (body.category) upd.sector = body.category;
    if (body.emirate) upd.emirate = body.emirate;
    const { data: won, error } = await admin.from('leads').update(upd).eq('id', id).is('claimed_by', null).select('id');
    if (error) { const r = registrationRefusal(error); return r.body.code === 'claim_failed' ? refused(error) : { status: r.status, body: r.body }; }
    if (!won || !won.length) return { status: 409, body: { ...EMAIL_ALREADY_REGISTERED } };   // another sign-up won the row
    const reg = await deps.setRegistration(id);
    await deps.recordFirstTouch(id, body.first_touch);
    return { status: 200, body: { ok: true, id, registration: reg, claimed_invited: true } };
  }
  const { data: ins, error } = await admin.from('leads').insert({ company_name: name, emirate: body.emirate || null, sector: body.category || null,
    business_role: body.role || 'supplier', claimed: true, claimed_by: email, email, owner_email_verified: proven, source: 'self_registered',
    locale: deps.locale, scraped_at: new Date().toISOString().slice(0, 10) }).select('id').maybeSingle();
  if (error) return refused(error);
  const reg = await deps.setRegistration(Number(ins!.id));
  await deps.recordFirstTouch(Number(ins!.id), body.first_touch);
  return { status: 200, body: { ok: true, id: ins?.id, registration: reg } };
}
