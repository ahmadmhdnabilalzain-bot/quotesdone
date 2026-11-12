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

// A REJECTED REGISTRATION IS NEVER A DEAD END (12 Nov 2026, customer_support; round-2 review: a rejected supplier saw no card, the
// badge "Not approved", no reason and no next step). The card says it was not approved, the reason when the dashboard carries one
// (leads.licence_gate_reason, in the same words the held states use: serverCopy srvText, injected as `say`; an internal code is
// never shown), and the one next step the product has for every rejection today: writing to the address the portal already gives
// (COMPANY_ALREADY_REGISTERED, REGISTER_FAILED). No new promise: we say where to write, not what will happen.
export const NOT_APPROVED = 'Your registration was not approved.';
export const SUPPORT_EMAIL = 'management@quotesdone.com';
export const REJECTED_NEXT = 'If you think this is a mistake, write to us at ' + SUPPORT_EMAIL + ' from the e-mail address you registered with.';
// Only a registration closed for being incomplete re-opens, and only by saving the profile (review note c, read 12 Nov 2026 in
// fn_sales_engineer_verifies_supplier: p_source save_profile; an upload alone runs it as mandatory_item_changed and the rejection
// stands). The dashboard says which kind it is: supplierCard.rejected_missing (the codes) or null.
export const REOPEN = 'Add what is missing on your Profile (in the Account menu) and press Save changes: your registration is then looked at again.';
const listOf = (xs: string[]) => (xs.length < 2 ? xs.join('') : xs.slice(0, -1).join(', ') + ' and ' + xs[xs.length - 1]);
const words = (code: string, say: (c: string) => string) => { const w = String(say(code) ?? '').trim(); return !w || w === code || /^[a-z0-9_]+$/.test(w) ? '' : w; };
const cap = (x: string) => x.charAt(0).toUpperCase() + x.slice(1);
const stop = (x: string) => (/[.!?]$/.test(x) ? x : x + '.');
/** The lines of a rejected registration's card, after its title. `say` is the reason-to-words map (srvText). Pure. */
export function rejectedLines(o: { missing: string[] | null | undefined; reason: string | null | undefined }, say: (code: string) => string): string[] {
  if (o.missing && o.missing.length) {
    const named = o.missing.map((c) => words(c, say)).filter(Boolean);
    return [...(named.length ? [stop('Missing: ' + listOf(named.map((w, i) => (i ? w.charAt(0).toLowerCase() + w.slice(1) : cap(w)))))] : []), REOPEN, REJECTED_NEXT];
  }
  const line = rejectedReason(o.reason, say);
  return [...(line ? [line] : []), REJECTED_NEXT];
}
const MISSING = /^(reg_[a-z_]+)$/;
/** The one reason line the dashboard carries for any other rejection (leads.licence_gate_reason), or null. A missing item is the
 *  FIRST the gate found, so it is said as "starting with", never as the only one. */
export function rejectedReason(reason: string | null | undefined, say: (code: string) => string): string | null {
  const r = String(reason ?? '').trim();
  if (!r) return null;
  const w = words(r, say);
  if (!w) return null;
  return stop((MISSING.test(r) ? 'Missing, starting with: ' : 'Reason: ') + cap(w));
}
