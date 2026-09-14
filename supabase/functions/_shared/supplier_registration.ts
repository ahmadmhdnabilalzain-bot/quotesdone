// THE MANDATORY SIX — the single definition of "required to register" as a supplier.
//
// Founder decision (memory: supplier-verification-mandatory-six): name, mobile, email, trade licence,
// company profile, signed T&C. Everything else is extra. Mobile and email must be VERIFIED.
//
// Before 14 Sep 2026 the same account was held to three different sets (website audit 2026-09-14,
// supplier portal "Degrades"): the portal refused to save without a company profile; supplier_portal's
// Documents payload marked only the licence required (`required: key === 'license'`) while the same
// tab's heading listed licence + profile + catalogues; and save_profile checked the licence alone.
// supplier_api (save_profile), supplier_portal (documents + eligibility) and, through the eligibility
// payload, the portal all read this file now, so the three cannot drift apart again.
//
// LICENCE = the document OR the number. The upload is accepted as present on its own: extraction is
// enrichment that may arrive later, and under the OpenRouter hold license_extract returns nothing, so
// requiring the extracted number would refuse every supplier who uploaded a licence.

export const REGISTRATION_COLS =
  'company_name,owner_phone_verified,owner_email_verified,license_doc_path,trade_license_no,company_profile_doc_path,accepted_terms_at';

// Documents-tab keys that are part of the six. Catalogues are optional (they were in the old
// "required" group only because an 8 Aug note listed them; the mandatory six superseded it).
export const REQUIRED_DOC_KEYS = ['license', 'profile'];

export type RegItem = { code: string; done: boolean; fix: 'profile' | 'documents' };

const has = (v: unknown) => v != null && String(v).trim() !== '';

export function registrationChecklist(r: Record<string, unknown>): RegItem[] {
  return [
    { code: 'reg_name',    done: has(r.company_name),                              fix: 'profile' },
    { code: 'reg_mobile',  done: r.owner_phone_verified === true,                  fix: 'profile' },
    { code: 'reg_email',   done: r.owner_email_verified === true,                  fix: 'profile' },
    { code: 'reg_licence', done: has(r.license_doc_path) || has(r.trade_license_no), fix: 'documents' },
    { code: 'reg_profile', done: has(r.company_profile_doc_path),                  fix: 'documents' },
    { code: 'reg_terms',   done: has(r.accepted_terms_at),                         fix: 'profile' },
  ];
}

export const registrationMissing = (r: Record<string, unknown>) =>
  registrationChecklist(r).filter((i) => !i.done).map((i) => i.code);
