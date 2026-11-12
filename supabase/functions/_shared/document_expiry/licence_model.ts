// The read ceiling, merging code and model reads, the model payload (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { emirateOf, emirateOfAuthority, type LicenceFields, NO_FIELDS } from './licence_fields.ts';
import { checkLicenceRead, normDate } from '../licence_extract.ts';

// A FILE TOO LARGE TO READ IS REFUSED BEFORE IT IS PARSED (3 Nov 2026, sales_engineer; defect of the 28 Oct document walk,
// docs/reports/supplier_documents_28_oct). A 24 MB licence ended supplier_portal at the edge's CPU cap (HTTP 546), and after #1721
// supplier_api process_docs still did at 19.3 MB (9.66 MB passed both, measured on production 1 Nov). The browser refuses above 10 MB
// (#1720); this is the same ceiling on the server, so a caller that skips the browser cannot reach the parse. Suppliers read English.
export const READ_MAX_BYTES = 10 * 1024 * 1024;
/** The decoded size of a base64 string (a data: prefix ignored), without decoding it. */
export const b64Size = (b64: unknown) => { const s = String(b64 ?? '').replace(/^data:[^,]*,/, '').replace(/\s/g, ''); return Math.floor(s.length * 3 / 4) - (s.endsWith('==') ? 2 : s.endsWith('=') ? 1 : 0); };
export const tooLargeToRead = (bytes: number, what: string) =>
  ({ error: 'file_too_large_read', code: 'file_too_large_read', message: `That ${what} is ${(bytes / 1048576).toFixed(1)} MB. We can read files of up to 10 MB. Please upload a smaller copy: a compressed PDF, or a clear photo of each page.` });

/** The model is asked whenever code left one of the four fields the gate stands on unread. */
export const licenceNeedsModel = (c: Partial<LicenceFields> | null | undefined) => !c?.legal_name_en || !c?.licence_no || !c?.expiry_date || !c?.authority;

/** A model reading that is sure enough to be THE reading: 'medium' or 'high' (licence_extract.normaliseLicence's scale). */
export const modelIsSure = (m: { confidence?: unknown } | null | undefined) => m?.confidence === 'medium' || m?.confidence === 'high';

/**
 * THE AI'S READING IS THE READING, AND THE ONLY ONE (12 Nov 2026, sales_engineer; founder rulings 1663 and 1664: "Trade license
 * reading ... there's no code first, 100%"; independent review of #1978, F1 and F3). One rule, used by the accuracy suite and the
 * qualification run and, through modelReadingToRow, by both licence doors (supplier_api process_docs, supplier_portal
 * save_documents):
 *   - every field is the model's reading (licence_extract.normaliseLicence's answer). Code's reading takes no part in any field:
 *     not to fill a blank, not to stand beside the issue/expiry pair. A field the model did not read is unread.
 *   - the one hard check: the model's expiry must be after its own issue date (checkLicenceRead; license_extract has already asked
 *     once more); otherwise both dates are unread: held for a person or asked again, never "expired".
 *   - `code` is evidence only: `disagreements` lists the fields code read differently, for our reviewer (recordLicenceReadNote).
 * Measured before (12 Nov 2026): the founder's DET licence, code expiry 2026-10-30 (the register's Reg. Date) kept over the model's
 * 2027-10-29, and the portal refused the licence as expired. The first version of this fix still let code fill blanks and still
 * wrote code's reading before the model answered; the review drove a licence code read as 2028-01-01 and a model that failed: code's
 * date was stored, state 'read', and never read again. Prevented by _shared/a_licence_is_refused_as_expired_only_on_the_models_checked_reading.test.ts.
 */
// deno-lint-ignore no-explicit-any
export function mergeLicenceReads(code: Partial<LicenceFields> | null | undefined, model: any): { merged: LicenceFields; source: Record<string, 'code' | 'model'>; disagreements: { field: string; code: unknown; model: unknown }[] } {
  const c = { ...NO_FIELDS, ...(code || {}) };
  let m = model || {};
  // a model date is a licence date only as a real calendar day (licence_extract.normDate: a timestamp's own day, no Hijri year)
  if (model) m = { ...m, issue_date: normDate(m.issue_date), expiry_date: normDate(m.expiry_date) };
  // the one hard check on the model's own pair (an expiry not after its issue date is no reading); never a layout rule
  if (model) { const { doc } = checkLicenceRead({ license_number: String(m.license_number ?? ''), issue_date: m.issue_date || null, expiry_date: m.expiry_date || null }, null); m = { ...m, issue_date: doc.issue_date, expiry_date: doc.expiry_date }; }
  const conf = m.confidence !== 'low';
  const fromModel: Partial<LicenceFields> = {
    licence_no: String(m.license_number ?? '').trim() || null,
    legal_name_en: conf ? (licenceNameFromModel(m) && !/[؀-ۿ]/.test(String(m.legal_name)) ? licenceNameFromModel(m) : null) : null,
    legal_name_ar: conf ? (String(m.legal_name_ar ?? '').trim() || null) : null,
    trade_name: String(m.trade_name ?? '').trim() || null, legal_form: String(m.legal_form ?? '').trim() || null,
    authority: String(m.license_authority ?? '').trim() || null, emirate: emirateOf(m.emirate) ?? emirateOfAuthority(m.license_authority),
    issue_date: m.issue_date || null, expiry_date: m.expiry_date || null,
    activities: Array.isArray(m.activities) && m.activities.length ? m.activities.map((a: unknown) => String(a).trim()).filter(Boolean) : null,
  };
  const merged = { ...NO_FIELDS }; const source: Record<string, 'code' | 'model'> = {};
  const disagreements: { field: string; code: unknown; model: unknown }[] = [];
  const has = (v: unknown) => v != null && v !== '' && !(Array.isArray(v) && !v.length);
  const same = (a: unknown, b: unknown) => JSON.stringify(a).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '') === JSON.stringify(b).toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
  for (const k of Object.keys(NO_FIELDS) as (keyof LicenceFields)[]) {
    const cv = c[k], mv = fromModel[k];
    if (has(cv) && has(mv) && !same(cv, mv)) disagreements.push({ field: k, code: cv, model: mv });
    // deno-lint-ignore no-explicit-any
    if (has(mv)) { (merged as any)[k] = mv; source[k] = 'model'; }
  }
  return { merged, source, disagreements };
}

/** What code read off the licence: evidence for the disagreement note only, never a value on the row (rulings 1663, 1664). */
export type CodeReading = { fields: Partial<LicenceFields>; expiry: string | null; name: string | null; issue: string | null | undefined };

/**
 * The model's licence reading as a row update (rulings 1663, 1664; review of #1978, F1). The row carries the model's reading only:
 * each field it read is written, a field it did not read stays as the first write left it (cleared for a new file), and code's
 * reading never reaches the row. `disagreements` lists where code read differently, for the record (recordLicenceReadNote). The
 * licence's printed name is recorded, never copied over the registered name.
 */
// deno-lint-ignore no-explicit-any
export function modelReadingToRow(d: any, code: CodeReading, at = new Date().toISOString()) {
  // ONE RULE: the fields are decided by mergeLicenceReads, exactly as the accuracy suite measures it; this only maps them onto the row.
  const { merged, source, disagreements } = mergeLicenceReads({ licence_no: code.fields.licence_no ?? null, authority: code.fields.authority ?? null,
    emirate: code.fields.emirate ?? null, expiry_date: code.expiry, issue_date: code.issue ? String(code.issue).slice(0, 10) : null,
    legal_name_en: code.name, activities: code.fields.activities ?? null }, d);
  const upd: Record<string, unknown> = {};
  if (merged.licence_no) upd.trade_license_no = merged.licence_no;
  if (merged.authority) upd.license_authority = merged.authority;
  if (d.city) upd.license_city = d.city;
  if (merged.emirate) upd.emirate = merged.emirate;
  upd.license_expiry = merged.expiry_date;   // the model's checked expiry, or unread: never code's
  let expiryDiffers: { code: string; model: unknown } | null = null;
  if (d.expiry_date && code.expiry && String(d.expiry_date) !== code.expiry) expiryDiffers = { code: code.expiry, model: d.expiry_date };
  const issue = merged.issue_date ?? (code.issue === undefined ? undefined : null);
  if (d.trn) upd.trn = d.trn;
  upd.doc_extracted_at = at;
  if (merged.legal_name_en) upd.licence_legal_name = merged.legal_name_en;
  const license = {
    legal_name: String(d.legal_name || '').trim(), license_number: d.license_number, authority: d.license_authority, city: d.city,
    expiry: merged.expiry_date, model_expiry: d.expiry_date, emirate: d.emirate, trn: d.trn,
    licence_name: merged.legal_name_en, confidence: d.confidence, issue_date: issue ?? null,
    // the licensed activities the model read: where a trade reader can take them (string[] | null)
    activities: merged.activities, activities_read_by: source.activities ?? null,
  };
  return { upd, issue, expiryDiffers, license, disagreements, merged, source };
}

// A SCANNED LICENCE STILL YIELDS ITS NAME (24 Sep 2026, sales_engineer). Code reads only a text layer, so a
// scan or a photo reaches the name through license_extract (vision, model_policy.document_extraction). These
// two are the whole rule, shared by every upload path (supplier_api, resend_inbound, wa_inbound):
/** The name the model read, or null. A 'low' confidence read (an unreadable scan, or a truncated reply) is not a name. */
export function licenceNameFromModel(doc: { legal_name?: unknown; confidence?: unknown } | null | undefined): string | null {
  if (!doc || doc.confidence === 'low') return null;
  const v = String(doc.legal_name ?? '').trim().slice(0, 200);
  return /\p{L}{2}/u.test(v) ? v : null;
}
export function toB64(u8: Uint8Array): string {
  let bin = ''; for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(bin);
}
/** What license_extract is sent: the images or file the request carried; otherwise, when code could not read a
 *  name, the STORED licence (a scan uploaded earlier, or by path). null = nothing to send. */
export function licenceModelPayload(lic: { images?: unknown[]; file_b64?: string; mime?: string; filename?: string },
    stored: { bytes: Uint8Array; mime: string } | null, codeName: string | null) {
  const images = Array.isArray(lic.images) ? lic.images : [];
  if (images.length || lic.file_b64) return { images, file_b64: lic.file_b64, mime: lic.mime, filename: lic.filename };
  if (codeName || !stored?.bytes?.length) return null;
  return /^image\//i.test(stored.mime)
    ? { images: [{ b64: toB64(stored.bytes), mime: stored.mime }], file_b64: undefined, mime: stored.mime, filename: lic.filename }
    : { images: [], file_b64: toB64(stored.bytes), mime: stored.mime || 'application/pdf', filename: lic.filename || 'licence.pdf' };
}
