// identity_numbers.ts — registration numbers that identify a supplier as surely as a phone number.
//
// The founder, 14 Sep 2026: supplier VAT details are hidden from the customer "cause simply the
// customer can reach out to the company if he knows their vat number". A UAE Tax Registration Number
// is public-register data: one search and the customer has the company, and the reveal fee the
// platform lives on is bypassed. The same is true of a trade-licence or commercial-registration
// number. Every scrubber that stands between a supplier's words and a customer imports these, so the
// patterns live in one place:
//   * _shared/anonymise.ts (redactText / residualScan)   * drawing_boq/boq_from_text.ts scrubIdentity
//   * _shared/quote_documents.ts maskContacts             * supplier_api scrubIdentity (form text)
//   * line_specs (the standardised quotation and the technical comparison)
//
// A UAE TRN is 15 digits, issued from 100…, written with or without spaces or dashes, in Latin or
// Arabic-Indic digits, and usually labelled TRN / Tax Registration Number / VAT No / رقم التسجيل
// الضريبي / الرقم الضريبي. The labelled form catches any 12-17 digit run after a label; the bare form
// catches a 15-digit 100-prefixed run with no label at all.
const D = '[\\d٠-٩]';
export const TRN_LABELLED = new RegExp(`(?:\\bTRN\\b|\\bT\\.R\\.N\\.?|Tax\\s*Registration\\s*(?:No\\.?|Number|#)?|VAT\\s*(?:Reg(?:istration)?\\.?\\s*)?(?:No\\.?|Number|#|ID)|VAT\\s*Reg(?:istration)?\\.?|رقم\\s*التسجيل\\s*الضريبي|الرقم\\s*الضريبي|رقم\\s*ضريبي|الرقم\\s*الضريبى)\\s*[:：#.\\-]?\\s*${D}(?:[\\s\\-]?${D}){11,16}`, 'gi');
export const TRN_BARE = new RegExp(`(?<![\\d٠-٩])[1١][\\s\\-]?[0٠][\\s\\-]?[0٠](?:[\\s\\-]?${D}){12}(?![\\d٠-٩])`, 'g');
// 3 Nov 2026 (second review of #1838): "رخصة تجارية رقم ١٢٣٤٥٦" and "السجل التجاري 765432" — the number AFTER the
// licence or register, with or without رقم — passed every scrubber; only "رقم الرخصة …" (the number word first) was read;
// and "رخصة رقم 123456" / "ترخيص رقم 123456". The adversarial re-review: the English value took any 4 letters ("License:
// Included", "Software License: Perpetual", "Vehicle registration: required") — a number carries at least four digits
// now — and the Arabic one read a year ("تجديد الرخصة التجارية 2026"): it needs five.
export const LICENCE_NO = /(?:(?:trade|commercial|business|industrial)\s*licen[cs]e|\blicen[cs]e|\bCR\b|commercial\s*reg(?:istration|\.)?|company\s*reg(?:istration|\.)?|\bregistration)(?:\s*(?:no\.?|number|#)\s*[:：#.\-]?|\s*[:：#\-])\s*(?=(?:[A-Z\-\/]*\d){4})[A-Z0-9][A-Z0-9\-\/]{3,}|(?:رقم\s*(?:الرخصة\s*التجارية|الرخصه\s*التجاريه|الرخصة|الرخصه|الترخيص|السجل\s*التجاري))\s*[:：]?\s*[A-Z0-9٠-٩][\w\-\/٠-٩]{2,}|(?:(?:ال)?رخص[ةه]\s*(?:ال)?تجاري[ةه]|(?:ال)?سجل\s*(?:ال)?تجاري)(?:\s*رقم)?\s*[:：#]?\s*[0-9٠-٩][0-9٠-٩\-\/]{4,}|(?:(?:ال)?رخص[ةه]|(?:ال)?ترخيص)\s*رقم\s*[:：#]?\s*[0-9٠-٩][0-9٠-٩\-\/]{3,}/gi;

const digits = (s: string) => s.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660)).replace(/\D/g, '');

/** The supplier's TRN as 15 plain digits, for the internal record only. Null when none is stated. */
export function findTrn(text: string): string | null {
  const s = String(text ?? '');
  for (const re of [TRN_LABELLED, TRN_BARE]) {
    for (const m of s.matchAll(new RegExp(re.source, re.flags))) {
      const d = digits(m[0]).slice(-15);
      if (d.length === 15 && d.startsWith('100')) return d;
    }
  }
  return null;
}

/** Remove TRNs and licence / registration numbers from customer-bound text. */
export function maskIdentityNumbers(text: unknown, replacement = ''): string {
  return String(text ?? '').replace(TRN_LABELLED, replacement).replace(TRN_BARE, replacement).replace(LICENCE_NO, replacement);
}
