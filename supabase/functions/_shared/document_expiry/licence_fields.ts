// The licence's name and fields read by code (split out of document_expiry.ts, 9 Nov 2026; a pure move).
import { esc, parseDate } from './dates.ts';
import { expiryFromText } from './expiry_text.ts';
import { ISSUE_DATE_LABELS } from './tables.ts';
import { pdfText } from './pdf_text.ts';

// THE NAME A LICENCE PRINTS (24 Sep 2026, sales_engineer). The review compares it with the registered
// company name (fn_supplier_licence_name_mismatch). Read the same way as the expiry: a value on the SAME
// line as a name label, nothing inferred. Legal name is preferred over trade name, which a UAE licence
// may print without the legal form. No label = null ("not read"), never a guess.
// 7 Oct 2026 (accuracy suite): an Ajman sole establishment prints "Establishment Name"; with no label for it the
// reader fell through to "Trade Name" and recorded the trade name as the licence's name.
const LEGAL_NAME_LABELS = ['legal name', 'company name', 'name of company', 'name of the company', 'establishment name', 'name of establishment',
  'الاسم القانوني', 'اسم الشركة', 'اسم المؤسسة'];
const TRADE_NAME_LABELS = ['trade name', 'trading name', 'الاسم التجاري'];
export const NAME_LABELS = [...LEGAL_NAME_LABELS, ...TRADE_NAME_LABELS];
export function licenceNameFromText(text: string): string | null {
  for (const label of NAME_LABELS) {
    const re = new RegExp('^[ \\t]*' + label + '[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'im');
    const v = re.exec(String(text || ''))?.[1]?.trim().slice(0, 200);
    if (v && /\p{L}{2}/u.test(v)) return v;
  }
  return null;
}
/** The licence's printed company name from a text-layer PDF, or null. Images return null (no OCR). */
export async function readLicenceName(bytes: Uint8Array, mime: string): Promise<string | null> {
  if (!/pdf/i.test(mime)) return null;
  const text = await pdfText(bytes);
  return text ? licenceNameFromText(text) : null;
}

// EVERY FIELD A LICENCE PRINTS, READ BY CODE (7 Oct 2026, sales_engineer; founder gate ledger 1162: "not a single
// mistake in any trade licence"). Measured before this on the 50-licence synthetic corpus of
// scripts/e2e/document_intake_accuracy.mjs: code read the name and the expiry only, so the licence number, the
// issuing authority, the legal form, the issue date, the emirate and the activities of a text licence were read by
// nothing at all (process_docs's model switch is off), and trades were proposed from the company's NAME line
// ("Horizon Floor LLC" -> floor cleaners) instead of its licensed activities. Same rule as the name: a value is
// taken only from the same line as its label; no label, no value. Labels are each authority's own vocabulary.
export type LicenceFields = {
  licence_no: string | null; legal_name_en: string | null; trade_name: string | null; legal_form: string | null;
  authority: string | null; emirate: string | null; issue_date: string | null; expiry_date: string | null; activities: string[] | null;
  legal_name_ar: string | null;
};
const LABELS: Record<'licence_no' | 'legal_form' | 'authority' | 'emirate' | 'issue_date' | 'activities', string[]> = {
  licence_no: ['trade licence number', 'trade license number', 'trade licence no', 'trade license no', 'commercial licence no', 'commercial license no',
    'licence number', 'license number', 'licence no', 'license no', 'registered number', 'registration number', 'registration no', 'رقم الرخصة'],
  legal_form: ['legal form', 'legal type', 'legal status', 'company type', 'الشكل القانوني'],
  authority: ['issuing authority', 'licensing authority', 'issued by', 'جهة الإصدار'],
  emirate: ['emirate', 'الإمارة'],
  issue_date: ISSUE_DATE_LABELS,
  activities: ['business activities', 'licensed activities', 'activities', 'activity', 'الأنشطة', 'النشاط'],
};
/** The value on the same line as the first label that has one. A label is a whole word: "Licence No" never reads "Licence Number". */
function labelled(text: string, labels: string[]): string | null {
  for (const label of labels) {
    const re = new RegExp('^[ \\t]*' + esc(label) + '(?![\\p{L}])\\.?[ \\t]*[:：\\-]?[ \\t]*(.+)$', 'imu');
    const v = re.exec(text)?.[1]?.trim().slice(0, 300);
    if (v && /[\p{L}\p{N}]/u.test(v)) return v;
  }
  return null;
}
const EMIRATES = ['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
const EMIRATE_AR: Record<string, string> = { 'دبي': 'Dubai', 'أبوظبي': 'Abu Dhabi', 'ابوظبي': 'Abu Dhabi', 'الشارقة': 'Sharjah', 'عجمان': 'Ajman', 'أم القيوين': 'Umm Al Quwain', 'رأس الخيمة': 'Ras Al Khaimah', 'الفجيرة': 'Fujairah' };
export function emirateOf(s: string | null | undefined): string | null {
  const t = String(s ?? '');
  for (const e of EMIRATES) if (new RegExp('\\b' + e + '\\b', 'i').test(t)) return e;
  for (const [ar, e] of Object.entries(EMIRATE_AR)) if (t.includes(ar)) return e;
  return null;
}
// Where a licence prints no emirate (most free zones), the issuing authority decides it: each of these is in one emirate.
const AUTHORITY_EMIRATE: [RegExp, string][] = [
  [/abu dhabi global market|\badgm\b/i, 'Abu Dhabi'], [/ras al khaimah|\brakez\b/i, 'Ras Al Khaimah'], [/sharjah|\bshams\b|\bsaif\b|hamriyah/i, 'Sharjah'],
  [/jebel ali|\bjafza\b|multi commodities|\bdmcc\b|airport free ?zone|\bdafza\b|silicon oasis|\bdso\b|international free zone|\bifza\b|meydan|international financial centre|\bdifc\b|economy and tourism|dubai/i, 'Dubai'],
  [/abu dhabi/i, 'Abu Dhabi'], [/ajman/i, 'Ajman'], [/umm al quwain/i, 'Umm Al Quwain'], [/fujairah/i, 'Fujairah'],
];
export function emirateOfAuthority(a: string | null | undefined): string | null {
  for (const [re, e] of AUTHORITY_EMIRATE) if (re.test(String(a ?? ''))) return e;
  return null;
}
// ACTIVITIES PRINTED ONE PER LINE UNDER THEIR LABEL (3 Nov 2026, sales_engineer; scripts/e2e/document_reading_qualification.ts). A DET
// licence lists its activities as rows under "Business Activities"; the label's own line then holds no value, so `labelled` read
// nothing and a four-activity licence proposed no trade at all ("no activities line could be read"). The label alone on its line
// now takes the lines under it, up to a blank line or the next labelled field, each line one activity (never split at a comma:
// an activity name may hold one, "Air-Conditioning, Ventilation & Air Filtration ...").
const ALL_FIELD_LABELS = () => [...Object.values(LABELS).flat(), ...NAME_LABELS, 'expiry date', 'valid until', 'تاريخ الانتهاء'];
function activitiesBlock(text: string): string[] | null {
  const lines = text.split(/\r?\n/);
  for (const label of LABELS.activities) {
    const re = new RegExp('^[ \\t]*' + esc(label) + '[ \\t]*[:：\\-]?[ \\t]*$', 'iu');
    const i = lines.findIndex((l) => re.test(l));
    if (i < 0) continue;
    const isLabel = (l: string) => ALL_FIELD_LABELS().some((k) => new RegExp('^[ \\t]*' + esc(k) + '(?![\\p{L}])', 'iu').test(l));
    // The content-stream reader puts a blank line between lines that each have their own BT..ET (most generators), so ONE
    // blank line is a line break and TWO end the list. ponytail: layout rule; a list followed by an unlabelled paragraph after a
    // single break would take it in (measured on none so far).
    const out: string[] = [];
    let blank = 0;
    for (let k = i + 1; k < lines.length && out.length < 30; k++) {
      const l = lines[k].replace(/^[ \t]*(?:[-•*·]|\d{1,2}[.)])[ \t]*/, '').trim();
      if (!l) { if (++blank >= 2 && out.length) break; continue; }
      blank = 0;
      if (isLabel(lines[k]) || /^\(/.test(l)) break;
      if (l.length >= 3 && /\p{L}{2}/u.test(l)) out.push(l);
    }
    if (out.length) return out;
  }
  return null;
}
export function licenceFieldsFromText(text: string): LicenceFields {
  const t = String(text || '');
  const noRaw = labelled(t, LABELS.licence_no);
  const licence_no = noRaw ? (/[A-Z0-9][A-Z0-9\-/.]*\d[A-Z0-9\-/.]*/i.exec(noRaw)?.[0].replace(/[.\-/]+$/, '') ?? null) : null;
  const legal = labelled(t, LEGAL_NAME_LABELS);
  const authority = labelled(t, LABELS.authority);
  const emirateRaw = labelled(t, LABELS.emirate);
  const issueRaw = labelled(t, LABELS.issue_date);
  const acts = labelled(t, LABELS.activities);
  const name = legal && /\p{L}{2}/u.test(legal) ? legal : null;
  return {
    licence_no, legal_name_en: name && !/[؀-ۿ]/.test(name) ? name : null,
    legal_name_ar: name && /[؀-ۿ]/.test(name) ? name : null,
    trade_name: labelled(t, TRADE_NAME_LABELS), legal_form: labelled(t, LABELS.legal_form), authority,
    emirate: emirateOf(emirateRaw) ?? emirateOfAuthority(authority),
    issue_date: issueRaw ? parseDate(issueRaw) : null, expiry_date: expiryFromText(t)?.expiry ?? null,
    activities: acts ? acts.split(/[,،;؛]/).map((a) => a.trim()).filter((a) => a.length >= 3) : activitiesBlock(t),
  };
}
const NO_FIELDS: LicenceFields = { licence_no: null, legal_name_en: null, legal_name_ar: null, trade_name: null, legal_form: null, authority: null, emirate: null, issue_date: null, expiry_date: null, activities: null };
/** A licence file's fields by code; an image or a PDF with no text layer reads as all null ("not read"). */
export async function readLicenceFields(bytes: Uint8Array, mime: string): Promise<LicenceFields> {
  if (!/pdf/i.test(mime)) return { ...NO_FIELDS };
  const text = await pdfText(bytes);
  return text ? licenceFieldsFromText(text) : { ...NO_FIELDS };
}
export { NO_FIELDS };
