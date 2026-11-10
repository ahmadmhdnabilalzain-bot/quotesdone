// The read ceiling, merging code and model reads, the model payload (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { emirateOf, emirateOfAuthority, type LicenceFields, NO_FIELDS } from './licence_fields.ts';

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

/**
 * CODE FIRST, THE MODEL ONLY WHERE CODE COULD NOT READ (founder: "code first, LLM only where code can't"). One rule,
 * used by supplier_api.process_docs and by the accuracy suite, so what is measured is what runs. A field code read
 * is never overwritten by the model. The model's name counts only when it is confident (licenceNameFromModel).
 * `source` says, per field, who read it.
 */
// deno-lint-ignore no-explicit-any
export function mergeLicenceReads(code: Partial<LicenceFields> | null | undefined, model: any): { merged: LicenceFields; source: Record<string, 'code' | 'model'> } {
  const c = { ...NO_FIELDS, ...(code || {}) };
  const m = model || {};
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
  for (const k of Object.keys(NO_FIELDS) as (keyof LicenceFields)[]) {
    const cv = c[k], mv = fromModel[k];
    const has = (v: unknown) => v != null && v !== '' && !(Array.isArray(v) && !v.length);
    // deno-lint-ignore no-explicit-any
    if (has(cv)) { (merged as any)[k] = cv; source[k] = 'code'; } else if (has(mv)) { (merged as any)[k] = mv; source[k] = 'model'; }
  }
  return { merged, source };
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
