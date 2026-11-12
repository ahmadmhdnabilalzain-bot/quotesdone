// The read ceiling, merging code and model reads, the model payload (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { emirateOf, emirateOfAuthority, type LicenceFields, NO_FIELDS } from './licence_fields.ts';
import { checkLicenceRead } from '../licence_extract.ts';

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
/** Today's date in Dubai (UTC+4, no daylight saving), as YYYY-MM-DD: the calendar the licence gate reads an expiry on. */
export const dubaiToday = (now = Date.now()) => new Date(now + 4 * 3600_000).toISOString().slice(0, 10);
/**
 * WHILE THE MODEL HAS NOT ANSWERED, CODE'S EXPIRY MAY STAND ONLY WHERE IT CANNOT REFUSE (12 Nov 2026, sales_engineer; founder
 * ruling 1663). Code's reading of a text licence is written with the row before the model answers (median 6.5 s, up to the
 * after-answer write), and is shown back on the form. An expiry is refused as "expired" only on the model's checked reading
 * (checkLicenceRead), so code's expiry is written meanwhile only when it is today or later AND after the issue date code read:
 * then it can be wrong but can never refuse a licence, and the model's reading replaces it. Otherwise it is not written, the
 * expiry is unread, and the licence is ours to read (licence_read_state 'ours_failed' until the model answers).
 */
export const codeExpiryMayStand = (expiry: string | null | undefined, issue: string | null | undefined, today = dubaiToday()) =>
  !!expiry && (!issue || expiry > issue) && expiry >= today;

/**
 * THE AI'S READING IS THE READING (12 Nov 2026, sales_engineer; founder rulings 1663 and 1664, which replace "code first, LLM only
 * where code can't" for trade licences). One rule, used by the accuracy suite and the qualification run, the same rule process_docs
 * (supplier_api/lib/licence_store_first.ts modelReadingToRow) and save_documents apply to the row:
 *   - a model reading that is 'medium' or 'high' wins every field it read, over code's;
 *   - code's value stands only where the model read none, or read 'low' (as before: a 'low' read only fills gaps);
 *   - the model's own expiry must be after its own issue date (checkLicenceRead's one hard check), else both are unread;
 *   - the merged expiry must be after the merged issue date; otherwise the expiry is unread (held for a person, never refused).
 * Measured before (12 Nov 2026): the founder's DET licence, code expiry 2026-10-30 (the register's Reg. Date) kept over the
 * model's, and the portal refused a licence valid to 2027-10-29. `source` says who read each field; `disagreements` lists the
 * fields code and the model both read differently, for the record (process_docs writes them to agent_actions).
 */
// deno-lint-ignore no-explicit-any
export function mergeLicenceReads(code: Partial<LicenceFields> | null | undefined, model: any): { merged: LicenceFields; source: Record<string, 'code' | 'model'>; disagreements: { field: string; code: unknown; model: unknown }[] } {
  const c = { ...NO_FIELDS, ...(code || {}) };
  let m = model || {};
  // a model date may come as a timestamp ('2025-01-02T00:00:00Z'): only its day is a licence date
  const day = (v: unknown) => (v ? String(v).slice(0, 10) : null);
  if (model) m = { ...m, issue_date: day(m.issue_date), expiry_date: day(m.expiry_date) };
  // the one hard check on the model's own pair (an expiry not after its issue date is no reading); never a layout rule
  if (model) { const { doc } = checkLicenceRead({ license_number: String(m.license_number ?? ''), issue_date: m.issue_date || null, expiry_date: m.expiry_date || null }, null); m = { ...m, issue_date: doc.issue_date, expiry_date: doc.expiry_date }; }
  const conf = m.confidence !== 'low';
  const sure = modelIsSure(m);
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
    if (has(mv) && (sure || !has(cv))) { (merged as any)[k] = mv; source[k] = 'model'; } else if (has(cv)) { (merged as any)[k] = cv; source[k] = 'code'; }
  }
  if (merged.expiry_date && merged.issue_date && merged.expiry_date <= merged.issue_date) { merged.expiry_date = null; delete source.expiry_date; }
  return { merged, source, disagreements };
}

/** What code read, as the model step must respect it: code first, the model fills only what code left blank. */
export type CodeReading = { fields: Partial<LicenceFields>; expiry: string | null; name: string | null; issue: string | null | undefined };

/**
 * The model's licence reading as a row update. THE MODEL'S READING IS THE READING (12 Nov 2026, sales_engineer; founder rulings
 * 1663 and 1664: "Trade license reading ... there's no code first, 100%"). Until today code's reading came first and the model
 * only filled blanks; its expiry was "recorded beside code's, never over it". The founder's own DET licence was refused as
 * "expired on 30 Oct 2026": code had read the register's Reg. Date as the expiry and the model's 2027-10-29 was set aside. Now a
 * 'medium' or 'high' reading replaces what code read in every field it read (number, authority, emirate, issue date, expiry,
 * printed name); a 'low' one still fills only blanks. `disagreements` lists where code and the model read differently, for the
 * record (recordLicenceReadNote). The expiry written is always after the issue date kept: otherwise it is unread (held, never
 * "expired"). The licence's printed name is recorded, never copied over the registered name.
 */
// deno-lint-ignore no-explicit-any
export function modelReadingToRow(d: any, code: CodeReading, at = new Date().toISOString()) {
  // ONE RULE: the fields are decided by mergeLicenceReads, exactly as the accuracy suite measures it; this only maps them onto the row.
  const issueIn = code.issue ? String(code.issue).slice(0, 10) : null;
  const { merged, source, disagreements } = mergeLicenceReads({ licence_no: code.fields.licence_no ?? null, authority: code.fields.authority ?? null,
    emirate: code.fields.emirate ?? null, expiry_date: code.expiry, issue_date: issueIn, legal_name_en: code.name, activities: code.fields.activities ?? null }, d);
  const upd: Record<string, unknown> = {};
  if (source.licence_no === 'model') upd.trade_license_no = merged.licence_no;
  if (source.authority === 'model') upd.license_authority = merged.authority;
  if (d.city) upd.license_city = d.city;
  if (source.emirate === 'model') upd.emirate = merged.emirate;
  if (source.expiry_date === 'model') upd.license_expiry = merged.expiry_date;
  else if (code.expiry && !merged.expiry_date) upd.license_expiry = null;   // code's expiry fell to the one hard check
  let expiryDiffers: { code: string; model: unknown } | null = null;
  if (d.expiry_date && code.expiry && String(d.expiry_date) !== code.expiry) expiryDiffers = { code: code.expiry, model: d.expiry_date };
  const issue = source.issue_date === 'model' ? merged.issue_date : code.issue === undefined ? undefined : issueIn;
  if (d.trn) upd.trn = d.trn;
  upd.doc_extracted_at = at;
  if (source.legal_name_en === 'model') upd.licence_legal_name = merged.legal_name_en;
  const license = {
    legal_name: String(d.legal_name || '').trim(), license_number: d.license_number, authority: d.license_authority, city: d.city,
    expiry: merged.expiry_date, model_expiry: d.expiry_date, emirate: d.emirate, trn: d.trn,
    licence_name: (upd.licence_legal_name ?? code.name) ?? null, confidence: d.confidence, issue_date: issue ?? null,
    // the licensed activities as decided (the model's when it read them sure): where a trade reader can take them (string[] | null)
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
