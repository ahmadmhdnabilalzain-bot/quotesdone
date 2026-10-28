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

export type EmailLead = { id: number | string; claimed: boolean | null; claimed_by: string | null };
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

// The few supabase-js calls this makes, so create_company.test.ts can hand in an in-memory table.
// deno-lint-ignore no-explicit-any
type Db = any;
export type CreateDeps = {
  emailProven: (email: string) => Promise<boolean>;
  setRegistration: (leadId: number) => Promise<unknown>;
  recordFirstTouch: (leadId: number, touch: unknown) => Promise<void>;
  locale: string;
};

/** supplier_api create_company: { status, body } for the handler to answer. */
export async function createCompany(admin: Db, email: string, body: Record<string, unknown>, deps: CreateDeps): Promise<{ status: number; body: Record<string, unknown> }> {
  const { data: existing } = await admin.from('leads').select('id').eq('claimed_by', email).maybeSingle();
  const name = String(body.company_name || '').trim().slice(0, 160);
  if (!existing && name.length < 2) return { status: 400, body: { error: 'Enter your company name.', code: 'enter_company' } };
  const { data: held } = existing ? { data: [] } : await admin.from('leads').select('id,claimed,claimed_by').ilike('email', ilikeExact(email)).limit(2);
  const proven = existing ? false : await deps.emailProven(email);
  const plan = planCreateCompany({ ownCompany: !!existing, emailLeads: (held || []) as EmailLead[], emailProven: proven });
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
    const upd: Record<string, unknown> = { claimed: true, claimed_by: email, owner_email_verified: true, company_name: name,
      business_role: body.role || 'supplier', portal_updated_at: new Date().toISOString() };
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
