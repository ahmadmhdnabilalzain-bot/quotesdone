// VERIFIED BADGES (backlog T3, ledger 1019). Two badges, both derived from facts already on the
// supplier's leads row, never from a claim (release-operator review of #1183, 18 Oct 2026):
//   licence_verified   — ALL of: leads.verified, no licence hold (licence_gate_reason null), a
//                        licence document on file, and license_expiry >= today. A null expiry or a
//                        missing document is no badge: an unknown expiry is not a valid licence.
//   documents_complete — every REQUIRED document (REQUIRED_DOC_KEYS: trade licence + company profile)
//                        is on file, the licence has not expired, AND the supplier is verified and
//                        not held. A held or unverified supplier never shows it.
// The supplier sees both with what is missing (English only); customers see only the badge on an
// anonymised quote, which names nobody.
import { REQUIRED_DOC_KEYS } from './supplier_registration.ts';

export type BadgeLead = {
  verified?: boolean | null; licence_gate_reason?: string | null;
  license_doc_path?: string | null; license_expiry?: string | null;
  company_profile_doc_path?: string | null;
};

const PATH: Record<string, keyof BadgeLead> = { license: 'license_doc_path', profile: 'company_profile_doc_path' };
const LABEL: Record<string, string> = { license: 'Upload your trade licence', profile: 'Upload your company profile' };
const AWAITING = 'Your trade licence is awaiting verification by QuotesDone';
const ON_HOLD = 'Your trade licence is on hold - see the notice on your overview';

export function verifiedBadges(l: BadgeLead | null | undefined, today: Date = new Date()) {
  const lead = l || {};
  const missing: string[] = [];
  for (const k of REQUIRED_DOC_KEYS) if (!lead[PATH[k]]) missing.push(LABEL[k] || `Upload ${k}`);
  const day = new Date(today); day.setUTCHours(0, 0, 0, 0);
  const expiryMs = lead.license_expiry ? new Date(lead.license_expiry).getTime() : NaN;
  const expired = Number.isFinite(expiryMs) && expiryMs < day.getTime();
  const expiryValid = Number.isFinite(expiryMs) && !expired;
  if (lead.license_doc_path && expired) missing.push('Upload your renewed trade licence (the one on file has expired)');
  const held = !!(lead.licence_gate_reason && String(lead.licence_gate_reason).trim());
  const verified = lead.verified === true;
  const licence_verified = verified && !held && !!lead.license_doc_path && expiryValid;

  let licenceNeed: string[] = [];
  if (!licence_verified) {
    if (!lead.license_doc_path) licenceNeed = ['Upload your trade licence'];
    else if (expired) licenceNeed = ['Upload your renewed trade licence'];
    else if (!expiryValid) licenceNeed = ['Your trade licence expiry date has not been read yet'];
    else if (held) licenceNeed = [ON_HOLD];
    else licenceNeed = [AWAITING];
  }
  const docsNeed = [...missing];
  if (!docsNeed.length && held) docsNeed.push(ON_HOLD);
  else if (!docsNeed.length && !verified) docsNeed.push(AWAITING);
  return {
    licence_verified,
    documents_complete: missing.length === 0 && verified && !held,
    // What earns each badge, in the order a supplier would fix it.
    to_earn: { licence_verified: licenceNeed, documents_complete: docsNeed },
  };
}
