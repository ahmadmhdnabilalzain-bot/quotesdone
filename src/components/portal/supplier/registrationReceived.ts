// WHAT THE "REGISTRATION RECEIVED" CARD SAYS, FOR EVERY STATE A SUBMITTED REGISTRATION CAN BE IN (12 Nov 2026, customer_support;
// founder ruling 1645, browser walk finding H9, and the review of its first version).
// The first version said "We are checking it now. Nothing is needed from you" under an amber line asking for a clearer licence
// (licence_expiry_unread), which is ruling 1230's defect again, and showed the card to a rejected company. Now:
//   - the card is shown only to a submitted registration that is pending (approval_status null or 'pending');
//   - "Nothing is needed from you" only when nothing is: no hold reason, our reader still at work (licence_being_read,
//     documents_being_read), or only the Supplier Agreement certificate being signed;
//   - the services step left after Submit has its own sentence and one button;
//   - every other hold reason asks for something, and the card says so and points at the line above it.
// Prevented by: scripts/checks/the_supplier_is_told_his_registration_was_received.test.mjs (every reason the gate writes).
export const RECEIVED = 'Registration received.';
export const ONE_STEP = 'One step left: confirm your services.';
export const ONE_STEP_HERE = 'One step left: confirm your services below.';
export const NOTHING_NEEDED = 'We are checking it now. Nothing is needed from you; this page updates by itself.';
export const ONE_THING_NEEDED = 'One thing is needed from you: see the note above.';
const NOTHING_TO_DO = new Set(['', 'licence_being_read', 'documents_being_read']);

export type ReceivedInput = { approvalStatus: string | null | undefined; submitted: boolean; reason: string | null | undefined; signingOnly: boolean; scopeOpen: boolean };
export type ReceivedCard = null | { kind: 'services' | 'nothing' | 'needed'; text: (onServicesTab: boolean) => string };

/** The card for this registration, or null when no card is shown. Pure. */
export function registrationReceived(o: ReceivedInput): ReceivedCard {
  const st = o.approvalStatus ?? null;
  if (!o.submitted || !(st === null || st === 'pending')) return null;
  const reason = String(o.reason ?? '').trim();
  if (reason === 'services_unconfirmed' || (o.signingOnly && o.scopeOpen)) return { kind: 'services', text: (here) => (here ? ONE_STEP_HERE : ONE_STEP) };
  if (NOTHING_TO_DO.has(reason) || o.signingOnly) return { kind: 'nothing', text: () => NOTHING_NEEDED };
  return { kind: 'needed', text: () => ONE_THING_NEEDED };
}
