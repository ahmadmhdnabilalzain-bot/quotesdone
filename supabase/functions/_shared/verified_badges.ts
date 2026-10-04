// VERIFIED BADGES (backlog T3, ledger 1019). Two badges, both derived from facts already on the
// supplier's leads row, never from a claim:
//   licence_verified   — leads.verified (set when the trade licence was checked).
//   documents_complete — every REQUIRED document (REQUIRED_DOC_KEYS: trade licence + company profile)
//                        is on file AND the licence has not expired.
// The supplier sees both with what is missing (English only); customers see only the badge on an
// anonymised quote, which names nobody.
import { REQUIRED_DOC_KEYS } from './supplier_registration.ts';

export type BadgeLead = {
  verified?: boolean | null;
  license_doc_path?: string | null; license_expiry?: string | null;
  company_profile_doc_path?: string | null;
};

const PATH: Record<string, keyof BadgeLead> = { license: 'license_doc_path', profile: 'company_profile_doc_path' };
const LABEL: Record<string, string> = { license: 'Upload your trade licence', profile: 'Upload your company profile' };


export function verifiedBadges(l: BadgeLead | null | undefined, today: Date = new Date()) {
  const lead = l || {};
  const missing: string[] = [];
  for (const k of REQUIRED_DOC_KEYS) if (!lead[PATH[k]]) missing.push(LABEL[k] || `Upload ${k}`);
  const day = new Date(today); day.setUTCHours(0, 0, 0, 0);
  const expired = !!lead.license_expiry && new Date(lead.license_expiry).getTime() < day.getTime();
  if (lead.license_doc_path && expired) missing.push('Upload your renewed trade licence (the one on file has expired)');
  const licence_verified = lead.verified === true && !expired;
  return {
    licence_verified,
    documents_complete: missing.length === 0,
    // What earns each badge, in the order a supplier would fix it.
    to_earn: {
      licence_verified: licence_verified ? [] : (expired ? ['Upload your renewed trade licence'] : (lead.license_doc_path ? ['Your trade licence is awaiting verification by QuotesDone'] : ['Upload your trade licence'])),
      documents_complete: missing,
    },
  };
}
