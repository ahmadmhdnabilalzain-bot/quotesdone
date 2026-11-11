// licenceExpiry — what the licence step says when the licence it just read has already expired (11 Nov 2026, customer_support;
// supplier registration certification, finding 6).
//
// Measured in the free round (J8, fixture L8: RAK DED, expired 31 Aug 2026): the licence step said only "Read your licence —
// ZZ-261150, expires 2026-08-31." The supplier went on to fill the profile, open the agreement and accept it, and learned at
// Submit ("Still needed to register: the trade licence on file has expired"). It is said at the upload now, plainly, with
// what to do. English only: suppliers are always written to in English (ruling 1008), and the portal renders English.
// The date is compared as a DUBAI calendar date (UTC+4), the way the server's licence gate reads it: a licence that expires
// today is still in date today.
// Prevented by: src/components/portal/supplier/licenceExpiry.test.mjs.

const DUBAI_OFFSET_MS = 4 * 3600_000;
const ISO_DAY = /^(\d{4})-(\d{2})-(\d{2})/;

/** Today's date in Dubai, as YYYY-MM-DD. */
export function dubaiToday(now: number = Date.now()): string {
  return new Date(now + DUBAI_OFFSET_MS).toISOString().slice(0, 10);
}

/** True only for a readable date strictly before today in Dubai. An unread or malformed date is never called expired. */
export function licenceHasExpired(expiry: string | null | undefined, now: number = Date.now()): boolean {
  const m = ISO_DAY.exec(String(expiry ?? '').trim());
  if (!m) return false;
  return `${m[1]}-${m[2]}-${m[3]}` < dubaiToday(now);
}

/** "31 Aug 2026" from "2026-08-31". */
export function licenceDate(expiry: string): string {
  const m = ISO_DAY.exec(expiry);
  if (!m) return expiry;
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${Number(m[3])} ${MON[Number(m[2]) - 1]} ${m[1]}`;
}

/** The sentence the licence step shows for an expired licence: that it has expired, and what to do. */
export function expiredLicenceNote(expiry: string, licenceNo?: string | null): string {
  const no = String(licenceNo ?? '').trim();
  return `This trade licence${no ? ' (' + no + ')' : ''} expired on ${licenceDate(expiry)}, so we cannot register it. `
    + 'Please upload your renewed trade licence here. If the renewal is still with the licensing authority, '
    + 'you can save your other details now and upload the renewed licence as soon as it is issued.';
}

// WHILE OUR READER HAS NOT FINISHED (11 Nov 2026, customer_support; registration certification, second free round, J4 and J5).
// A phone photo or a scan has no text for code to read, so the model reads it; when the model cannot (an outage, or a run with
// models off), supplier_api / supplier_portal store licence_read_state 'ours_failed', hold the registration as licence_being_read,
// and the sweep reads the licence again (#1909). The servers answer this sentence; the registration form showed "if any of them
// cannot be read, we will e-mail you for a clearer copy" and the Documents tab "please upload a clear PDF of the full licence":
// both ask the supplier for something that is ours to do. This is _shared/licence_read_state.ts LICENCE_BEING_READ_NOTE, word
// for word (licenceExpiry.test.mjs holds the two equal).
export const LICENCE_BEING_READ_NOTE =
  'Our document reader has not finished reading your trade licence yet. That is on our side, not yours: we read it again automatically and tell you if anything is needed. Nothing was guessed.';
/** True when a licence answer says our reader has not finished (process_docs license_read_state, or a Documents read's being_read). */
export const licenceBeingRead = (j: { license_read_state?: unknown; being_read?: unknown } | null | undefined): boolean =>
  !!j && (j.license_read_state === 'ours_failed' || j.being_read === true);
