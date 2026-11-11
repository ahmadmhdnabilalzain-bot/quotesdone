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
