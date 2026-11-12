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
// WHAT IS HOLDING THE REGISTRATION, SAID AS WHAT TO DO (12 Nov 2026, customer_support; founder ruling 1645, browser walk finding
// M12). Every hold read "Your trade licence is on hold", sending him to a notice on an overview: shown on Documents beside a licence
// marked Valid, to a supplier held only for his unconfirmed services, and pointing at an overview the portal no longer has. Each
// leads.licence_gate_reason now says its own reason; the step left after Submit has one name everywhere: "Confirm your services".
const CLEARER = 'Upload a clearer copy of your trade licence (a PDF, or a sharp photo of the whole page)';
const HOLD_SAYS: Record<string, string> = {
  services_unconfirmed: 'Confirm your services on the Services tab',
  reg_terms: 'Your signed Supplier Agreement is not on file yet',
  documents_being_read: 'We are still reading your company profile or catalogue; nothing is needed from you',
  licence_being_read: 'We are still reading your trade licence; nothing is needed from you',
  no_licence: 'Upload your trade licence',
  licence_expired: 'Upload your renewed trade licence',
  licence_unreadable: CLEARER, licence_name_unread: CLEARER, licence_expiry_unread: CLEARER, licence_number_unread: CLEARER,
  licence_authority_unread: CLEARER,
  licence_authority_unconfirmed: 'Tell us which UAE authority or free zone issued your trade licence',
  licence_authority_not_uae: 'Upload your current UAE trade licence',
  licence_name_mismatch: 'Upload your own company’s trade licence, or contact us if your registered name should change',
};
const ON_HOLD_OTHER = 'Your registration is being checked by QuotesDone';
/** The one sentence a supplier reads for a hold reason (leads.licence_gate_reason); an unknown reason is never guessed at. */
export const holdSays = (reason: unknown): string => HOLD_SAYS[String(reason ?? '').trim()] || ON_HOLD_OTHER;

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
    else if (held) licenceNeed = [holdSays(lead.licence_gate_reason)];
    else licenceNeed = [AWAITING];
  }
  const docsNeed = [...missing];
  if (!docsNeed.length && held) docsNeed.push(holdSays(lead.licence_gate_reason));
  else if (!docsNeed.length && !verified) docsNeed.push(AWAITING);
  return {
    licence_verified,
    documents_complete: missing.length === 0 && verified && !held,
    // What earns each badge, in the order a supplier would fix it.
    to_earn: { licence_verified: licenceNeed, documents_complete: docsNeed },
  };
}
