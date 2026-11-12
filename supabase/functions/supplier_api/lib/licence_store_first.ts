// THE LICENCE IS STORED AND RECORDED FIRST; READING IT NEVER HOLDS THE ANSWER (11 Nov 2026, customer_support; free supplier
// registration certification, run 2, J5 desktop, fixture L5_rakez_scan.pdf, an image-only scan).
//
// MEASURED ON PRODUCTION. process_docs execution 60c7eba6 ran 56,198 ms (agent_runs 4899809, "slow run: 55675ms"). The file was
// in storage at 14:45:30.985Z, 1.7 s in. Then the model read sat in the request: license_extract attempt 1 failed at 14:45:33
// (502, "every model route for this task class is open-circuit"), nothing logged for 50 s, attempt 2 failed at 14:46:25. Only then
// did the ONE row write name the file (PATCH leads?id=eq.157513, 14:46:25.073Z). The browser had been cut off at about 30 s
// (net::ERR_FAILED, no CORS header: an intermediary's error, not the function's), so the form said "We could not store your licence
// file" for a file that was stored, and Submit, 3 s later, refused "Still needed to register: Trade licence" while the row did not
// yet name it. In run 1 the same file answered in 6.5 s because both model attempts failed fast.
//
// THE RULE NOW:
//   1. the row names the stored file BEFORE anything reads it (licenceRecordedFirst), with the old licence's readings cleared
//      and the read state 'ours_failed' (our reader has not finished): if the request dies anywhere after this, the file is on
//      the supplier's row and the sweep (supplier_api docs_reread) reads it again;
//   2. code's own reading of the file is bounded (CODE_READ_BUDGET_MS); what it reads is written with the row as before;
//   3. the model is asked only AFTER that write, and the answer waits for it at most MODEL_ANSWER_BUDGET_MS. A model that
//      answers in time is shown back as before; one that does not finishes after the answer and writes its own fields.
// The whole answer is then bounded by roughly the scan, the upload and the two budgets: well under any 30 s cut.
// Prevented by: supplier_api/licence_store_first.test.ts (process_docs driven with a model that never answers).
import { pdfText, readExpiry, readLicenceFields, readLicenceName, type LicenceFields } from '../../_shared/document_expiry.ts';

/** Code's reading of the licence (pdf.js over a text layer) may hold the answer this long, no longer. */
export const CODE_READ_BUDGET_MS = 8_000;
/** The model's reading may hold the answer this long, no longer; it carries on after the answer when slower. One value for every reader. */
export { MODEL_ANSWER_BUDGET_MS } from '../../_shared/licence_read_state.ts';

/** `p`'s value when it settles within `ms`, else { done: false } (p keeps running; its result is the caller's to keep). */
export async function withinBudget<T>(p: Promise<T>, ms: number): Promise<{ done: true; value: T } | { done: false }> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<{ done: false }>((ok) => { timer = setTimeout(() => ok({ done: false }), ms); });
  try {
    return await Promise.race([p.then((value) => ({ done: true as const, value })), late]);
  } finally { clearTimeout(timer); }
}

/**
 * The row write that names a newly stored licence, before any reader runs. null when the row already names this file (the
 * sweep's re-read of the same licence: nothing new to record, and what code read earlier is kept until it is read again).
 * A new file clears what the OLD licence printed: its readings must never judge the new document.
 */
export function licenceRecordedFirst(path: string, rowPath: unknown, at = new Date().toISOString()): Record<string, unknown> | null {
  if (!path || String(rowPath ?? '') === path) return null;
  return {
    license_doc_path: path,
    licence_legal_name: null, license_expiry: null, doc_extracted_at: null, trade_license_no: null, license_authority: null,
    licence_read_state: 'ours_failed', licence_read_at: at, portal_updated_at: at,
  };
}

export type CodeRead = { name: string | null; fields: Partial<LicenceFields>; expiry: { expiry: string; keyword?: string } | null; expiryError: string | null; text: string | null };

/** Everything code reads off the licence file, each reader on its own so one failing never loses the others. */
export async function readLicenceByCode(bytes: Uint8Array, mime: string): Promise<CodeRead> {
  let name: string | null = null; let fields: Partial<LicenceFields> = {}; let expiry: CodeRead['expiry'] = null; let expiryError: string | null = null;
  try { name = await readLicenceName(bytes, mime); } catch (_e) { name = null; }
  try { fields = await readLicenceFields(bytes, mime); } catch (_e) { fields = {}; }
  try { expiry = await readExpiry(bytes, mime) as CodeRead['expiry']; } catch (e) { expiryError = String((e as Error)?.message || e).slice(0, 120); }
  // the text layer itself (pdfText keeps one read per bytes object): what license_extract's checks are compared with
  let text: string | null = null;
  try { text = /pdf/i.test(mime) ? await pdfText(bytes) : null; } catch (_e) { text = null; }
  return { name, fields, expiry, expiryError, text };
}

// The row rule for the model's reading lives with mergeLicenceReads (_shared/document_expiry/licence_model.ts), so supplier_portal's
// save_documents applies the same one (12 Nov 2026, rulings 1663/1664).
export { modelReadingToRow, type CodeReading } from '../../_shared/document_expiry.ts';

// THE MODEL'S LATE WRITE IS FOR ITS OWN FILE ONLY (12 Nov 2026, customer_support; final audit R3 = review F3, regcert_diagnosis F3;
// ledger 1642). Rule 3's write lands after the answer, up to 23 s later on production (11 Nov, run 2 J1); by then the supplier
// may have uploaded another licence, and the write was filtered by the lead id only: licence A's number, authority and expiry
// landed on the row that names file B (repro: a_late_licence_read_never_writes_onto_a_newer_licence.test.ts). Every leads
// update through this writer also asks that the row still names `path`; `superseded()` is true once one matched no row, and
// the caller then drops the reading (the newer file's own read writes).
type Res = PromiseLike<{ error: { message?: string; code?: string } | null }>;
// deno-lint-ignore no-explicit-any
export function writerForFile(db: any, path: string) {
  let missed = false;
  const writer = {
    from: (t: string) => {
      const q = db.from(t);
      if (t !== 'leads') return q;
      return {
        update: (v: Record<string, unknown>) => ({
          eq: (c: string, val: unknown): Res => q.update(v).eq(c, val).eq('license_doc_path', path).select('id')
            .then((r: { data?: unknown[] | null; error: { message?: string; code?: string } | null }) => { if (!r.error && !(r.data ?? []).length) missed = true; return { error: r.error }; }),
        }),
        insert: (v: Record<string, unknown>) => q.insert(v),
      };
    },
  };
  return { writer, superseded: () => missed };
}
