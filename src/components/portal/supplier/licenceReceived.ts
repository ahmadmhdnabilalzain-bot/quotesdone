// licenceReceived — a licence whose answer was lost is rechecked on the supplier's row, never called unstored (11 Nov 2026,
// customer_support; free supplier registration certification, run 2, J5 desktop).
//
// MEASURED ON PRODUCTION. supplier_api process_docs had the file in storage 1.7 s in and answered 200 after 56 s; the browser was
// cut off at ~30 s (net::ERR_FAILED, no CORS header: an intermediary's error, never the function's own). The form treated the lost
// answer as a refusal and said "We could not store your licence file. Please try again with a PDF or a clear photo.", and its
// own Submit check, built on that answer, refused "Still needed to register: Trade licence" 3 s later. process_docs now names the
// file on the row before it reads anything (supplier_api/lib/licence_store_first.ts), so a recheck finds it at once. Here:
//   * an answer that never came from our code (timeout, network, a platform 5xx) is NOT a refusal: the row is read again, and a
//     licence path that is new since the upload began is shown as received;
//   * a refusal our code gave (wrong type, malware, too large, upload_failed) is said as before;
//   * Submit asks the row before it lists the licence as missing, so a licence stored behind a lost answer never blocks it.
// Prevented by: src/components/portal/supplier/licenceReceived.test.mjs.

/** The codes the portal's call() gives when no answer from our own code arrived (supplier/api.ts: abort, throw, platform status). */
export const ANSWER_LOST_CODES = ['timeout', 'network', 'server_error', 'bad_response', 'worker_limit'] as const;

/** True when the call did not hear our function's own answer, so whether it stored the file is unknown until the row is read. */
export function answerWasLost(j: { ok?: unknown; code?: unknown } | null | undefined): boolean {
  if (!j) return true;
  if (j.ok === true) return false;
  return (ANSWER_LOST_CODES as readonly string[]).includes(String(j.code ?? ''));
}

/** True when the supplier's row now names a licence file other than the one it named before this upload began. */
export function licenceStoredSince(before: string | null | undefined, row: { license_doc_path?: unknown } | null | undefined): boolean {
  const now = String(row?.license_doc_path ?? '').trim();
  return now !== '' && now !== String(before ?? '').trim();
}

type Row = { license_doc_path?: unknown; [k: string]: unknown } | null | undefined;

/**
 * Reads the row up to `tries` times, `waitMs` apart, until it names a licence newer than `before`. The row the recheck found,
 * or null when it never did (then the upload is said to have failed, truthfully).
 */
export async function recheckLicenceStored(readRow: () => Promise<Row>, before: string | null | undefined,
    opts: { tries?: number; waitMs?: number; sleep?: (ms: number) => Promise<void> } = {}): Promise<Row> {
  const tries = opts.tries ?? 4; const waitMs = opts.waitMs ?? 2500;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((ok) => setTimeout(ok, ms)));
  for (let i = 0; i < tries; i++) {
    if (i) await sleep(waitMs);
    let row: Row = null;
    try { row = await readRow(); } catch (_e) { row = null; }
    if (licenceStoredSince(before, row)) return row;
  }
  return null;
}

/** What the licence step says when the recheck found the file: received, and the reading is ours. English (ruling 1008). */
export const LICENCE_RECEIVED_NOTE =
  'We have received your trade licence. Our document reader has not finished reading it yet. That is on our side, not yours: we read it automatically and tell you if anything is needed.';

// A LICENCE READ THAT LANDS AFTER THE ANSWER IS SHOWN WHEN IT LANDS (12 Nov 2026, customer_support; final audit R2 =
// regcert_diagnosis F2; ledger 1642). process_docs answers after at most MODEL_ANSWER_BUDGET_MS (10 s) and says
// licence_read_after_answer when the model's reading is still running; the reading then writes the row a moment later. The form
// showed "Our document reader has not finished reading your trade licence yet" and never looked again: paid round of 11 Nov, run 1
// J4 (a phone photo), answer 22:38:20.049, row written 22:38:20.593, and at Submit the number and authority were still empty.
// Measured, the model's licence reads: p50 8.4 s, p90 12-15.9 s, max 23.2 s that round; 37.3 s the longest of 102 reads over 8
// days. So after the answer the row is read again on this backoff, about 60 s in all (reads up to ~70 s from the upload), and
// the fields are filled once the read state is no longer 'ours_failed'. It stops when the supplier leaves the form or uploads
// another licence (`stop`), or when the row names another file. Nothing is said as a failure while it waits.
export const LATE_READ_WAITS_MS = [2000, 2000, 2000, 3000, 3000, 5000, 5000, 8000, 10000, 10000, 10000];

/** The row once the reading of `path` has landed (licence_read_state no longer 'ours_failed'), or null when it did not land in
 *  the waits, the row names another licence, or `stop()` became true. */
export async function awaitLateLicenceRead(readRow: () => Promise<Row>, path: string,
    opts: { stop?: () => boolean; waits?: number[]; sleep?: (ms: number) => Promise<void> } = {}): Promise<Row> {
  const stop = opts.stop ?? (() => false);
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((ok) => setTimeout(ok, ms)));
  for (const w of opts.waits ?? LATE_READ_WAITS_MS) {
    await sleep(w);
    if (stop()) return null;
    let row: Row = null;
    try { row = await readRow(); } catch (_e) { row = null; }
    if (stop()) return null;
    if (!row) continue;
    if (String(row.license_doc_path ?? '').trim() !== path) return null;
    if (row.licence_read_state !== 'ours_failed') return row;
  }
  return null;
}

/** True only when the answer left before the model AND our reader has not read the licence (state 'ours_failed'). When code
 *  already read it (a text PDF: state 'read'), what it read, or that it has EXPIRED, stands on screen and nothing is polled
 *  (review of the fix, 12 Nov 2026: J8, an expired text licence whose model read was late, must keep saying it has expired). */
export const waitsForLateRead = (x: { licence_read_after_answer?: unknown; license_read_state?: unknown } | null | undefined): boolean =>
  !!x && x.licence_read_after_answer === true && x.license_read_state === 'ours_failed';

/** What the licence step says while that reading is still running. It is ours, and nothing is asked of the supplier. English (ruling 1008). */
export const LICENCE_READING_NOTE =
  'Your trade licence is being read now. Its number and licensing authority will appear here in a moment; you can carry on filling in the form meanwhile.';
