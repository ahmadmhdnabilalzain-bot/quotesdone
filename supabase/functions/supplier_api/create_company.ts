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
//   * 10 Nov 2026 (customer_support, item 7 of #1901's report): emailProven() no longer reads used_at at all. It asks
//     public.fn_email_proven, the one definition (a code VERIFIED for the address, email_verifications.verified_at),
//     which the derive trigger and the /portal?t= claim ask too (scripts/sql/an_email_is_proven_only_by_a_code_that_was_verified.sql).
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
import { isFixtureLead } from '../_shared/demo_identity.ts';
import { companyNameCore, companyNameKey, listingProbes } from '../_shared/company_name_key.ts';
export { companyNameKey, listingProbes } from '../_shared/company_name_key.ts';

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

/**
 * A listing claim_lookup answers not_found for (permanently_closed: a PDPL erasure, fn_pdpl_carry_out; banned) is not
 * claimable by index.ts `claim` either. Until 10 Nov 2026 the page said "not valid or has expired" while the claim,
 * run after sign-in from the token the page had already stored, attached the listing anyway.
 * Prevented by: supplier_api/a_closed_listing_cannot_be_claimed.test.ts.
 */
export function listingClosedToClaims(row: { permanently_closed?: boolean | null; banned?: boolean | null }): boolean {
  return row.permanently_closed === true || row.banned === true;
}

// A DIRECTORY LISTING IS CLAIMED BY ITS NAME, NEVER REGISTERED A SECOND TIME (12 Nov 2026, customer_support; founder ruling
// 1645, browser perfection walk of supplier registration, finding H10).
//
// MEASURED on production, 12 Nov 2026 (walk scen_company `listed_company_public_signup`): an unclaimed directory listing
// (lead 158191) existed; a public sign-up with ANOTHER address typed the same name; a second lead was inserted (158192,
// self_registered) and the listing stayed invitable. The rule above matched a listing only by the account's address, and a
// name only among CLAIMED rows. 20,276 of 20,278 leads are unclaimed listings (read 12 Nov 2026), so for the founder's
// friends from 16 Nov this is the common case, not an edge.
//
// A REGISTRATION NEVER TAKES A LISTING BY ITS NAME (review of this change, 12 Nov 2026; coordinator's decision). A first version
// claimed the one unclaimed listing with the same legal name and emirate. The review proved it wrong both ways: the real form
// (Onboarding.tsx) sends no emirate and no licence number, so no real registration ever reached the claim; while a hand-made
// request with a public name, an emirate and ANY mailbox (gmail included) did, and got the listing's row, scraped phone, bell
// history and capability rows before any licence check, through an UPDATE that the disposable-mail trigger (BEFORE INSERT) never
// sees. A code to the registrant's own mailbox proves the registrant, never the listing.
// So every registration creates its own row, and when an open listing comes close the it_engineer seat is asked to merge it by
// hand (agent_actions it_engineer / possible_duplicate_listing, pending), with how close it came:
//   "name and emirate agree with one listing" (the strongest: a person confirms before it is merged), more than one listing has
//   the name, the emirate differs or is unknown, a contradiction (company e-mail domains or licence numbers differ), the same name
//   but for the legal form ("X Trading" against "X Trading LLC"), or too many listings share the name's words to read them all.
// The listing stays out of the invitation campaign meanwhile: fn_supplier_invite_candidates skips a listing whose name key equals a
// claimed company's (scripts/sql/a_listing_whose_company_registered_itself_is_not_invited.sql).
// THE CLAIM COMES BACK ONLY WHEN IT CONFIRMS SOMETHING OF THE LISTING'S OWN: a code sent to the LISTING's address or mobile, or the
// licence number read from the uploaded licence equal to the listing's. Name, emirate and the registrant's mailbox never suffice.
// Prevented by: create_company.test.ts "H10 …".
const EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'] as const;
/** The emirate a value names: an emirate itself, or an address naming exactly one emirate. Anything else is unknown (null). */
export function emirateOf(v: unknown): string | null {
  const s = ' ' + String(v ?? '').toLowerCase().replace(/[^a-z]+/g, ' ').trim() + ' ';
  const hits = EMIRATES.filter((e) => s.includes(' ' + e.toLowerCase() + ' '));
  return hits.length === 1 ? hits[0] : null;
}
const FREE_MAIL = /^(gmail|googlemail|yahoo|ymail|hotmail|outlook|live|msn|icloud|me|aol|proton|protonmail|gmx|mail|zoho|yandex)\./i;
const domainOf = (v: unknown) => { const s = String(v ?? '').trim().toLowerCase(); const at = s.lastIndexOf('@'); const h = at >= 0 ? s.slice(at + 1) : s.replace(/^[a-z]+:\/\//, '').split('/')[0]; return h.replace(/^www\./, ''); };
const companyDomain = (v: unknown) => { const d = domainOf(v); return d && d.includes('.') && !FREE_MAIL.test(d) ? d : ''; };
const licenceNo = (v: unknown) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');

export type Listing = { id: number | string; company_name: string | null; emirate?: string | null; email?: string | null; website?: string | null;
  claimed?: boolean | null; claimed_by?: string | null; permanently_closed?: boolean | null; banned?: boolean | null; is_demo?: boolean | null;
  tags?: string[] | null; trade_license_no?: string | null; business_role?: string | null };
export type ListingPlan =
  | { kind: 'none' }
  | { kind: 'strong'; lead: Listing; basis: Record<string, unknown> }   // flagged like the rest: never merged without a person
  | { kind: 'flag'; leads: Listing[]; why: string };

/** What an unclaimed directory listing with this company's name means for a registration. Pure; create_company.test.ts. */
export function planListingMatch(o: { name: string; emirate: unknown; email: string; licence?: unknown; proven: boolean; listings: Listing[]; truncated?: boolean }): ListingPlan {
  const key = companyNameKey(o.name);
  if (!key) return { kind: 'none' };
  const fixture = isFixtureLead({ company_name: o.name, email: o.email, claimed_by: o.email });
  const open = o.listings.filter((l) => !(l.claimed_by != null && String(l.claimed_by).trim() !== '') && l.claimed !== true
    && !listingClosedToClaims(l) && isFixtureLead(l) === fixture);   // a fixture never meets a real company, either way round
  const same = open.filter((l) => companyNameKey(l.company_name) === key);
  const near = open.filter((l) => companyNameKey(l.company_name) !== key && companyNameCore(companyNameKey(l.company_name)) === companyNameCore(key) && companyNameCore(key) !== '');
  if (!same.length) {
    if (near.length) return { kind: 'flag', leads: near, why: 'the same name but for the legal form' };
    // A page that was cut at its limit may hide the twin: say so rather than "none" (review finding 2).
    return o.truncated ? { kind: 'flag', leads: [], why: 'too many listings share the words of this name to read them all; none of those read matched' } : { kind: 'none' };
  }
  if (same.length > 1 || o.truncated) return { kind: 'flag', leads: same, why: same.length > 1 ? 'more than one listing has this name' : 'too many listings share a word of this name to be sure' };
  const lead = same[0];
  const mine = emirateOf(o.emirate), theirs = emirateOf(lead.emirate);
  if (!mine || !theirs) return { kind: 'flag', leads: same, why: 'the emirate is not known on both sides' };
  if (mine !== theirs) return { kind: 'flag', leads: same, why: `the emirate differs (${theirs} on the listing, ${mine} on the form)` };
  const myDomain = companyDomain(o.email), theirDomains = [companyDomain(lead.email), companyDomain(lead.website)].filter(Boolean);
  if (myDomain && theirDomains.length && !theirDomains.includes(myDomain)) return { kind: 'flag', leads: same, why: `the e-mail domain differs (${theirDomains[0]} on the listing, ${myDomain} on the account)` };
  const a = licenceNo(o.licence), b = licenceNo(lead.trade_license_no);
  if (a && b && a !== b) return { kind: 'flag', leads: same, why: 'the trade licence number differs' };
  if (!o.proven) return { kind: 'flag', leads: same, why: 'the address was not proven by a sign-in code in this session' };
  return { kind: 'strong', lead, basis: { name_key: key, emirate: mine, domain_agrees: !!(myDomain && theirDomains.includes(myDomain)), licence_agrees: !!(a && b && a === b) } };
}
const LISTING_COLUMNS = 'id,company_name,emirate,email,website,claimed,claimed_by,permanently_closed,banned,is_demo,tags,trade_license_no,business_role';
const LISTING_LIMIT = 300;

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
  /** lib/me_row.ts supplierOf for this account: the row `me` would answer, read after the write. */
  readSupplier?: () => Promise<Record<string, unknown> | null>;
  locale: string;
};

const lookupFailed = (what: string, error: PgError) => {
  console.error(`create_company: ${what} failed —`, error?.message);
  return { status: 500, body: { ...REGISTER_FAILED } };
};

/**
 * After the company is written and its registration state derived: the first touch is recorded and the supplier is read the
 * way `me` reads him, together. The answer carries `supplier` so the portal opens the registration form on this answer and
 * does not ask `me` next (Onboarding.tsx). A read that fails or finds nothing leaves `supplier` out, and the portal asks `me`
 * as it always did; the registration itself has already succeeded and is never reported as failed for it.
 */
async function afterTheWrite(id: number, touch: unknown, deps: CreateDeps): Promise<{ supplier?: Record<string, unknown> }> {
  const [, supplier] = await Promise.all([
    deps.recordFirstTouch(id, touch),
    deps.readSupplier ? deps.readSupplier().catch((e) => { console.error('create_company: the supplier read after the write failed —', String(e)); return null; }) : Promise.resolve(null),
  ]);
  return supplier && Number(supplier.id) === id ? { supplier } : {};
}

/** An agent_actions row recording what create_company decided about a listing. A failed write is logged; the registration stands. */
async function audit(admin: Db, row: Record<string, unknown>): Promise<void> {
  try { const { error } = await admin.from('agent_actions').insert(row); if (error) console.error('create_company: the agent_actions record failed —', error.message); }
  catch (e) { console.error('create_company: the agent_actions record failed —', String(e)); }
}

/** supplier_api create_company: { status, body } for the handler to answer. */
export async function createCompany(admin: Db, email: string, body: Record<string, unknown>, deps: CreateDeps): Promise<{ status: number; body: Record<string, unknown> }> {
  const name = String(body.company_name || '').trim().slice(0, 160);
  // THE FOUR LOOK-UPS ARE ISSUED TOGETHER (11 Nov 2026, customer_support; registration certification free round 6, run 2 J1:
  // create_company 1,810 ms in the browser). The account's own company, the lead holding the address, the e-mail proof and
  // the claimed-name twin depend on none of each other's answers; they were four round trips in series before the write.
  // They are read in one wave and judged in the same order as before, so every answer is the one the series gave.
  // Prevented by: create_company.test.ts "the look-ups before the write are one wave".
  // The unclaimed listings that share the name's longest word are read in the same wave (H10 above); a failed read is no listing.
  const probes = listingProbes(name);
  const [own, byEmail, provenRead, { data: twins }, listingsRead] = await Promise.all([
    admin.from('leads').select('id').eq('claimed_by', email).maybeSingle(),
    admin.from('leads').select('id,claimed,claimed_by,business_role').ilike('email', ilikeExact(email)).limit(2),
    deps.emailProven(email),
    admin.from('leads').select('id').eq('claimed', true).ilike('company_name', ilikeExact(name.replace(/\s+/g, ' '))).limit(1),
    probes.length ? probes.reduce((q, re) => q.imatch('company_name', re), admin.from('leads').select(LISTING_COLUMNS).is('claimed_by', null)).limit(LISTING_LIMIT) : Promise.resolve({ data: [], error: null }),
  ]);
  const { data: existing, error: ownErr } = own;
  if (ownErr) return lookupFailed('the account\'s company look-up', ownErr);
  if (!existing && name.length < 2) return { status: 400, body: { error: 'Enter your company name.', code: 'enter_company' } };
  let held: EmailLead[] = [];
  if (!existing) {
    const { data, error } = byEmail;
    if (error) return lookupFailed('the look-up of the lead holding the address', error);
    held = (data || []) as EmailLead[];
  }
  const proven = existing ? false : provenRead;
  // The claim takes an address proven by a used code AND a session opened by a code (header, review of #1712).
  const plan = planCreateCompany({ ownCompany: !!existing, emailLeads: held, emailProven: proven && deps.sessionByCode === true });
  if (plan.kind === 'company_exists') return { status: 409, body: { error: 'Your account already manages a company.', code: 'company_exists' } };
  if (plan.kind === 'email_taken') return { status: 409, body: { ...EMAIL_ALREADY_REGISTERED } };
  if (plan.kind === 'verify_email_first') return { status: 403, body: { ...VERIFY_EMAIL_FIRST } };
  // A COMPANY ALREADY CLAIMED IS NOT REGISTERED TWICE (24 Sep 2026, ledger 993): case- and space-folded, exact. It
  // applies to the claim too, because the claim writes the name the form gives.
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
    const supplier = await afterTheWrite(id, body.first_touch, deps);
    return { status: 200, body: { ok: true, id, registration: reg, claimed_invited: true, ...supplier } };
  }
  // H10: every registration is its own row; an open listing that comes close is flagged for a person to merge (header above).
  const listings = (listingsRead && !listingsRead.error ? listingsRead.data || [] : []) as Listing[];
  if (listingsRead?.error) console.error('create_company: the listing look-up failed —', listingsRead.error.message);
  const match = planListingMatch({ name, emirate: body.emirate, email, licence: body.trade_license_no, proven: proven && deps.sessionByCode === true,
    listings, truncated: listings.length >= LISTING_LIMIT });
  const flag = match.kind === 'strong' ? { leads: [match.lead], why: 'name and emirate agree with one listing; a person confirms before it is merged' }
    : match.kind === 'flag' ? { leads: match.leads, why: match.why } : null;
  const { data: ins, error } = await admin.from('leads').insert({ company_name: name, emirate: body.emirate || null, sector: body.category || null,
    business_role: body.role || 'supplier', claimed: true, claimed_by: email, email, owner_email_verified: proven, source: 'self_registered',
    locale: deps.locale, scraped_at: new Date().toISOString().slice(0, 10) }).select('id').maybeSingle();
  if (error) return refused(error);
  if (flag) await audit(admin, { agent: 'it_engineer', kind: 'possible_duplicate_listing', status: 'pending', risk: 'medium',
    title: 'Possible duplicate of a directory listing — ' + name.slice(0, 120),
    recommendation: `A registration came close to ${flag.leads.length === 1 ? 'an unclaimed directory listing' : flag.leads.length ? flag.leads.length + ' unclaimed directory listings' : 'unclaimed directory listings'} (${flag.why}). The company was registered as a new row and the listing was not touched. Compare them; if they are the same company, merge the listing into the new row by hand.`,
    detail: { new_lead_id: Number(ins!.id), account: email, typed_name: name, emirate: body.emirate ?? null, why: flag.why,
      ...(match.kind === 'strong' ? { basis: match.basis } : {}),
      listings: flag.leads.slice(0, 10).map((l) => ({ id: Number(l.id), company_name: l.company_name, emirate: l.emirate ?? null })) },
    target_table: 'leads', target_id: String(ins!.id) });
  const reg = await deps.setRegistration(Number(ins!.id));
  const supplier = await afterTheWrite(Number(ins!.id), body.first_touch, deps);
  return { status: 200, body: { ok: true, id: ins?.id, registration: reg, ...supplier } };
}
