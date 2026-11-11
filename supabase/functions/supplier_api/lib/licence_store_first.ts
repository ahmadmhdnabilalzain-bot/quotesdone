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
import { licenceNameFromModel, readExpiry, readLicenceFields, readLicenceName, type LicenceFields } from '../../_shared/document_expiry.ts';

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

export type CodeRead = { name: string | null; fields: Partial<LicenceFields>; expiry: { expiry: string; keyword?: string } | null; expiryError: string | null };

/** Everything code reads off the licence file, each reader on its own so one failing never loses the others. */
export async function readLicenceByCode(bytes: Uint8Array, mime: string): Promise<CodeRead> {
  let name: string | null = null; let fields: Partial<LicenceFields> = {}; let expiry: CodeRead['expiry'] = null; let expiryError: string | null = null;
  try { name = await readLicenceName(bytes, mime); } catch (_e) { name = null; }
  try { fields = await readLicenceFields(bytes, mime); } catch (_e) { fields = {}; }
  try { expiry = await readExpiry(bytes, mime) as CodeRead['expiry']; } catch (e) { expiryError = String((e as Error)?.message || e).slice(0, 120); }
  return { name, fields, expiry, expiryError };
}

/** What code read, as the model step must respect it: code first, the model fills only what code left blank. */
export type CodeReading = { fields: Partial<LicenceFields>; expiry: string | null; name: string | null; issue: string | null | undefined };

/**
 * The model's licence reading as a row update, by the rules process_docs has always applied (code first; the model's expiry is
 * recorded beside code's, never over it; the licence's printed name is recorded, never copied over the registered name).
 */
// deno-lint-ignore no-explicit-any
export function modelReadingToRow(d: any, code: CodeReading, at = new Date().toISOString()) {
  const upd: Record<string, unknown> = {};
  if (d.license_number && !code.fields.licence_no) upd.trade_license_no = d.license_number;
  if (d.license_authority && !code.fields.authority) upd.license_authority = d.license_authority;
  if (d.city) upd.license_city = d.city;
  let expiryDiffers: { code: string; model: unknown } | null = null;
  if (d.expiry_date) {
    if (code.expiry) { if (String(d.expiry_date) !== code.expiry) expiryDiffers = { code: code.expiry, model: d.expiry_date }; }
    else upd.license_expiry = d.expiry_date;
  }
  if (d.emirate && !code.fields.emirate) upd.emirate = d.emirate;
  let issue = code.issue;
  if (d.issue_date && !issue) issue = String(d.issue_date).slice(0, 10);
  if (d.trn) upd.trn = d.trn;
  upd.doc_extracted_at = at;
  const modelName = licenceNameFromModel(d);
  if (modelName && !code.name) upd.licence_legal_name = modelName;
  const license = {
    legal_name: String(d.legal_name || '').trim(), license_number: d.license_number, authority: d.license_authority, city: d.city,
    expiry: code.expiry || d.expiry_date, model_expiry: d.expiry_date, emirate: d.emirate, trn: d.trn,
    licence_name: (upd.licence_legal_name ?? code.name) ?? null, confidence: d.confidence, issue_date: issue ?? null,
  };
  return { upd, issue, expiryDiffers, license };
}
