// ONE RECORD OF A SUPPLIER'S TERMS ACCEPTANCE (sales_engineer, 15 Sep 2026).
//
// Measured on origin/main: three writers recorded the acceptance three ways. supplier_api save_profile
// and supplier_api accept_terms read app_secrets('terms_version') and stored the SHA-256 of the exact
// agreement text; kyc accept_terms, called by the portal straight afterwards, read
// supplier_terms_version and rewrote the version with NO hash, so the stored record was always the one
// without the evidence. Both keys hold 'v12' today; nothing guaranteed they would stay equal.
//
// Every writer now builds the row here. The version is read server-side (supplier_terms_version, then
// terms_version), never from the browser; the hash is of the text this module was exported for, and is
// null — never the hash of the wrong agreement — when the live version is a different one.
// The hash is the generator's constant (16 Nov 2026): it was recomputed here from the 87,725-byte text on every
// acceptance, which put that text in supplier_api, customer_api and kyc; supplier_terms.test.ts holds them equal.
import { SUPPLIER_AGREEMENT_SHA256, SUPPLIER_AGREEMENT_VERSION } from './supplier_agreement_hash.ts';

export type TermsRecord = {
  accepted_terms_at: string;
  accepted_terms_version: string;
  accepted_terms_ip: string | null;
  accepted_terms_sha256: string | null;
  accepted_terms_user_agent: string | null;
};

export async function currentSupplierTermsVersion(sec: (k: string) => Promise<string | null>): Promise<string> {
  return String((await sec('supplier_terms_version')) || (await sec('terms_version')) || '').trim().slice(0, 20);
}

// A CONTACT-ONLY REVISION DOES NOT ASK ANYONE TO SIGN AGAIN (2 Nov 2026, ceo; ledger 1482).
// Every gate below used to be `accepted_terms_version === current`, so any new version number, even one that
// changes only the contact line (v17: the founder's mobile came out of the text), would have sent every
// supplier back to the re-acceptance card and, through kyc accept_terms, written a second acceptance and a second
// certificate nobody asked for. app_secrets 'supplier_terms_carries_from' lists the earlier versions whose
// acceptance carries to the current one because the current text differs from them in the contact line only
// (comma-separated, e.g. 'v16'). A material version is published with that key EMPTY, so the list can only
// ever name versions the founder's ruling said are the same agreement. The acceptance row is never rewritten:
// a supplier who signed v16 stays recorded as v16 with the SHA-256 of the v16 text, which is kept byte-exact
// at /supplier-agreement/v16.
export async function supplierTermsCarriedFrom(sec: (k: string) => Promise<string | null>): Promise<string[]> {
  return String((await sec('supplier_terms_carries_from')) || '').split(',').map((s) => s.trim()).filter(Boolean);
}

/** True when `accepted` is the current version or one the current version carries (pure; the gate's whole logic). */
export function acceptanceStands(accepted: string | null | undefined, current: string, carriedFrom: string[]): boolean {
  const a = String(accepted ?? '').trim();
  return !!a && !!current && (a === current || carriedFrom.includes(a));
}

export async function supplierAcceptanceStands(sec: (k: string) => Promise<string | null>, accepted: string | null | undefined): Promise<boolean> {
  return acceptanceStands(accepted, await currentSupplierTermsVersion(sec), await supplierTermsCarriedFrom(sec));
}

// ONE READER FOR THE ACCEPTING ADDRESS (24 Sep 2026, sales_engineer). supplier_api fell back to
// cf-connecting-ip and x-real-ip when x-forwarded-for was absent; kyc accept_terms read x-forwarded-for
// only, so the same acceptance could be stored with an IP on one path and none on the other, and the
// certificate then prints "Not recorded". Both paths now read the address here.
export function clientIp(req: Request): string {
  return (req.headers.get('x-forwarded-for') || '').split(',')[0].trim()
    || (req.headers.get('cf-connecting-ip') || '').trim() || (req.headers.get('x-real-ip') || '').trim();
}

// 24 Sep 2026 (sales_engineer): the record said when, which version, from which IP and which text, but not
// from which browser - leads had no user-agent column, so the certificate could not print one. The
// User-Agent header of the accepting request is now kept beside the IP (clipped; null when absent).
/** The acceptance row for now, or null when no version is configured (refuse rather than invent one). */
export async function supplierTermsRecord(sec: (k: string) => Promise<string | null>, ip: string, userAgent = ''): Promise<TermsRecord | null> {
  const v = await currentSupplierTermsVersion(sec);
  if (!v) return null;
  if (v !== SUPPLIER_AGREEMENT_VERSION) console.error(`supplier terms ${v} have no exported agreement text (module is ${SUPPLIER_AGREEMENT_VERSION}); hash not stored`);
  return {
    accepted_terms_at: new Date().toISOString(),
    accepted_terms_version: v,
    accepted_terms_ip: ip || null,
    accepted_terms_sha256: v === SUPPLIER_AGREEMENT_VERSION ? SUPPLIER_AGREEMENT_SHA256 : null,
    accepted_terms_user_agent: String(userAgent || '').trim().slice(0, 500) || null,
  };
}

// THE PERSON WHO ACCEPTS FOR THE COMPANY (12 Nov 2026, ruling 1672; supplier_api accept_terms and save_profile, kyc accept_terms): his full name as typed, spaces
// folded, at most 120 characters, and at least two words with letters in them (a first name alone is what the founder's own certificate
// printed as "Full name" and "Authorised signatory"). Any script. Anything shorter is null, and the step asks again in plain words.
export const personName = (v: unknown): string | null => {
  const s = String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, 120);
  return s.split(' ').filter((w) => /\p{L}/u.test(w)).length >= 2 && /\p{L}{2}/u.test(s) ? s : null;
};

/**
 * Whether recording a FIRST acceptance for this supplier needs the accepting person's full name (review of #1987, S5): it does when no
 * acceptance was ever on file and no full name is held as the signatory. A re-acceptance of a new version by a supplier who accepted
 * before is never stopped for a name (his stored signatory stands). Every door that records a supplier acceptance asks this first.
 */
export function acceptanceNeedsName(lead: { accepted_terms_at?: unknown; signatory_name?: unknown } | null | undefined, fullName: string | null): boolean {
  return !lead?.accepted_terms_at && !fullName && !personName(lead?.signatory_name);
}
export const FULL_NAME_REQUIRED = { error: 'Please enter your full name: your first name and your family name. It is the name your signed acceptance is issued under.', code: 'full_name_required' } as const;
