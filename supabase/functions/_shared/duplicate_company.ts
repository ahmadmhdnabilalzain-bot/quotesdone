// A CLAIMED COMPANY CANNOT BE REGISTERED TWICE (24 Sep 2026, sales_engineer).
//
// #944 gave supplier_api one answer for "this company already has an account": 409 with code
// company_already_registered, which the portal renders from serverCopy.ts in the supplier's language.
// scripts/sql/a_claimed_company_cannot_be_registered_twice_under_another_spelling_or_the_same_licence.sql
// adds the database's version of the same rule: two partial unique indexes over claimed leads, one on
// the normalised company name and one on the trade licence number. When either refuses a write, Postgres
// answers 23505 naming the index. This module is the one place that recognises it.
//
// SAFE BEFORE THE SQL IS APPLIED. Merging deploys the edge functions before the SQL is applied. Until the
// indexes exist no 23505 can name them, so every function here answers false / passes the write through
// unchanged, and nothing here calls a SQL routine (no 42883 to degrade from).
//
// Two kinds of write can trip the indexes, and they are treated differently:
//   * a REGISTRATION (create_company, claim) that would make a second claimed company -> refused with the
//     existing company_already_registered answer. No new copy was written;
//   * a DOCUMENT write (process_docs, supplier_portal save_documents, the e-mail and WhatsApp intakes)
//     that carries a licence number already held by another claimed company. Review of #962: failing
//     the whole update lost license_doc_path and the expiry read off the same document. The write is
//     retried WITHOUT the licence number, and the clash goes to a human through the review path the
//     services cross-check already uses (agent_actions, agent sales_engineer, status needs_review).
//     No licence-specific sentence exists in serverCopy.ts, so the supplier is shown the existing
//     company_already_registered sentence.
//
// Only these two indexes map here. Any other 23505 on leads (claimed_by, email, claim_token, place_id)
// means something else and keeps its own answer.
import { SANCTIONED_REGISTRATION_REFUSAL } from './sanctioned.ts';

export const DUPLICATE_NAME_INDEX = 'leads_claimed_company_name_uidx';
export const DUPLICATE_LICENCE_INDEX = 'leads_claimed_trade_licence_uidx';
export const DUPLICATE_COMPANY_INDEXES = [DUPLICATE_NAME_INDEX, DUPLICATE_LICENCE_INDEX] as const;

export const COMPANY_ALREADY_REGISTERED = {
  error: 'A company with this name is already registered on QuotesDone. If it is yours, sign in with the email used to register it, or write to management@quotesdone.com.',
  code: 'company_already_registered',
} as const;

/** A claim the database refused for any reason that has no answer of its own. Stable code, no Postgres text (SP-I-01). */
export const CLAIM_FAILED = {
  error: 'We could not attach this company to your account. Please try again, or write to management@quotesdone.com.',
  code: 'claim_failed',
} as const;

export type PgError = { code?: string | null; message?: string; details?: string | null } | null | undefined;

const names = (err: PgError): string => `${err?.message ?? ''} ${err?.details ?? ''}`;
const unique = (err: PgError): boolean => !!err && String(err.code ?? '') === '23505';

/** True when a PostgREST/Postgres error is a unique violation on either duplicate-company index. */
export function isDuplicateCompany(err: PgError): boolean {
  return unique(err) && DUPLICATE_COMPANY_INDEXES.some((n) => names(err).includes(n));
}

/** True when the violation is on the LICENCE index: the licence number belongs to another claimed company. */
export function isLicenceClash(err: PgError): boolean {
  return unique(err) && names(err).includes(DUPLICATE_LICENCE_INDEX);
}

/**
 * The answer to a refused registration write (create_company's insert, claim's update). The sanctions
 * trigger a01_leads_sanctioned_identity_cannot_re_register raises SANCTIONED_PARTY_BLOCKED; it gets the
 * same 403 create_company already gives it. Anything else gets a stable code, never the raw message.
 */
export function registrationRefusal(err: PgError): { body: Record<string, unknown>; status: number } {
  if (isDuplicateCompany(err)) return { body: { ...COMPANY_ALREADY_REGISTERED }, status: 409 };
  if (String(err?.message ?? '').includes('SANCTIONED_PARTY_BLOCKED')) return { body: { ...SANCTIONED_REGISTRATION_REFUSAL }, status: 403 };
  return { body: { ...CLAIM_FAILED }, status: 500 };
}

// The smallest surface of the Supabase client this needs, so a test can hand in a stub.
type Result = PromiseLike<{ error: PgError }>;
export type LeadWriter = {
  from(table: string): {
    update(values: Record<string, unknown>): { eq(column: string, value: unknown): Result };
    insert(values: Record<string, unknown>): Result;
  };
};

/**
 * Write a document's readings to a lead. If the licence number clashes with another claimed company,
 * write everything else, record the clash for a human, and say so. `licenceSetAside` is the number that
 * was not written (null when nothing was set aside); `error` is the error of the write that counts.
 */
export async function updateLeadSettingAsideClashingLicence(
  admin: LeadWriter, leadId: number | string, upd: Record<string, unknown>, source: string,
): Promise<{ error: PgError; licenceSetAside: string | null }> {
  const first = await admin.from('leads').update(upd).eq('id', leadId);
  if (!first.error) return { error: null, licenceSetAside: null };
  if (!isLicenceClash(first.error) || upd.trade_license_no == null) return { error: first.error, licenceSetAside: null };
  const { trade_license_no: number, ...rest } = upd;
  const second = await admin.from('leads').update(rest).eq('id', leadId);
  if (second.error) return { error: second.error, licenceSetAside: null };
  try {
    const { error } = await admin.from('agent_actions').insert({
      agent: 'sales_engineer',
      kind: 'supplier_licence_number_clash',
      status: 'needs_review',
      risk: 'medium',
      title: 'Licence number already held by another claimed company — supplier #' + String(leadId),
      recommendation: 'The licence document for supplier #' + String(leadId) + ' reads a trade licence number that another claimed company already holds, so the number was NOT written; the document and every other reading were. Compare the two licences: a misread number is corrected on this row, a genuine second account for one company is resolved with the supplier.',
      detail: { supplier_id: Number(leadId), licence_number_read: String(number), source, index: DUPLICATE_LICENCE_INDEX, checked_at: new Date().toISOString() },
      target_table: 'leads',
      target_id: String(leadId),
    });
    if (error) console.error('duplicate_company: review item not recorded —', String(error.message ?? ''));
  } catch (e) { console.error('duplicate_company: review item not recorded —', String((e as Error)?.message ?? e)); }
  return { error: null, licenceSetAside: String(number) };
}
