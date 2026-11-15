// line_specs/vat.ts — the price the customer compares and pays 3% on is the price EXCLUDING VAT.
//
// The founder, 14 Sep 2026: "for suppliers quotations, we definetely hide the vat details when
// sharing the quotes with the customer". QuotesDone is not VAT-registered. So the supplier's VAT
// treatment, VAT amount and TRN are captured for the record (quotes.vat_treatment / vat_amount /
// supplier_trn, never served to a customer), and quotes.price_ex_vat is the one figure that is
// compared and that the reveal fee is taken on. A price whose ex-VAT value cannot be determined
// exactly is a missing detail: the quote is held and the supplier is asked to state it.
//
// Deterministic, in this order: the supplier's own ex-VAT figure from the portal; "not VAT
// registered"; a stated subtotal plus a VAT amount; "excluding VAT"; "including VAT" with the VAT
// amount or rate stated (or, with no rate, the supplier's TRN or his own lines adding up to the total less exactly 5%: the
// UAE rate). A stated basis his own figures contradict is not settled (basis_conflict, below). Anything else — including
// silence — is not stated, never assumed.
import { normText } from './model.ts';
import { findTrn } from '../identity_numbers.ts';

export type VatTreatment = 'exclusive' | 'inclusive' | 'not_registered' | 'zero_rated' | 'exempt' | 'not_stated' | 'confirmed_on_portal';
export type VatRead = {
  treatment: VatTreatment; price_ex_vat: number | null; vat_amount: number | null; vat_rate: number | null; trn: string | null;
  /** The supplier's stated basis contradicts his own figures: a total exactly 5% above his line amounts, called "before VAT".
   *  Not settled: no ex-VAT figure, the quote is held and he is asked the VAT question (accountant, 15 Nov 2026). */
  basis_conflict?: true;
};

const NOT_REG = /not\s*(?:vat\s*)?registered(?:\s*for\s*vat)?|no\s*vat\s*(?:applicable|charged)?\b|vat\s*(?:is\s*)?not\s*applicable|غير مسجل(?:ة)?\s*(?:في|ب|لدى)?\s*(?:ضريبة|الضريبة)|بدون ضريبة|لا توجد ضريبة/i;
// 15 Sep 2026: "prices exclude VAT" read as not stated — INCL already took "include(s)", EXCL did not.
// THE VAT BASIS, CLAUSE BY CLAUSE (sales_engineer, 12 Nov 2026; final-audit fix review rounds 4-5). A whole-text match read a
// negation anywhere in the sentence: "Prices do not include 5% VAT." was inclusive (main: a 6,120 quotation compared and
// charged 3% on 5,828.57), and "Our offer does not include VAT exemption certificates; prices include VAT" was exclusive
// (round 4). Now the text is cut into clauses (sentence ends, ";", "but", and a comma before a part that names VAT); a
// clause states a basis only when the tax itself is the object ("VAT exemption certificates" is not), and a negation counts
// only directly before "include ... VAT" / "inclusive of VAT" in that clause. An exclusive clause wins, as before.
const TAX = String.raw`(?:vat|value\s+added\s+tax|ضريبة(?:\s+القيمة\s+المضافة)?)(?!\s+(?:exemption|certificate|certificates|registration|number|invoice|refund|return|consultant)\b)`;
const PCT = String.raw`(?:\(?\s*\d+(?:\.\d+)?\s*%\s*\)?\s*)?`;
const FILL = String.raw`(?:(?:the|any|applicable|all)\s+)*`;
const EXCL = new RegExp([
  String.raw`(?:do(?:es)?\s*not|don'?t|doesn'?t|not)\s*includ(?:e|es|ed|ing)\s+${FILL}${PCT}${TAX}`,
  String.raw`not\s+inclusive\s+of\s+${FILL}${PCT}${TAX}`,
  String.raw`${TAX}\s*${PCT}(?:is\s*|are\s*)?not\s*included`,
  String.raw`(?<!not\s)excl(?:uding|usive|udes?|\.)?\s*(?:of\s*)?${FILL}${PCT}${TAX}`,
  String.raw`${TAX}\s*(?:is\s*)?(?:excluded|extra|additional)`, String.raw`${TAX}[^.;]{0,30}\bin\s+addition`, String.raw`\+\s*${TAX}`, String.raw`plus\s*${TAX}`,
  String.raw`before\s*${TAX}`, String.raw`without\s*${TAX}`,
  'غير شامل\\s*(?:ل)?(?:ال)?ضريبة', 'قبل (?:ال)?ضريبة', 'لا يشمل\\s*(?:ال)?ضريبة', '\\+\\s*(?:ال)?ضريبة',
].join('|'), 'i');
const INCL = new RegExp([
  String.raw`not\s+exclusive\s+of\s+${FILL}${PCT}${TAX}`,
  String.raw`(?<!not\s)incl(?:uding|usive|udes?|\.)?\s*(?:of\s*)?${FILL}${PCT}${TAX}`,
  String.raw`${TAX}\s*(?:at\s*)?${PCT}(?:,[^,.;]{0,40},\s*)?(?:is\s*|are\s*)?(?:included|inclusive)`, String.raw`with\s*${TAX}`,
  'شامل\\s*(?:ل)?(?:ال)?ضريبة', 'يشمل\\s*(?:ال)?ضريبة', 'متضمن\\s*(?:ال)?ضريبة',
].join('|'), 'i');
const TAX_WORD = new RegExp(TAX, 'i');
// ZERO-RATED AND EXEMPT ARE STATED ANSWERS, NOT SILENCE (sales_engineer, 13 Nov 2026, workflow audit build item 10). Both
// mean no VAT is added to the supplier's price, so the price as written is the ex-VAT figure; they were held as "not stated".
// "VAT exemption certificate(s)" names a document, not the supply's treatment, so "exempt" must not be followed by "ion".
const ZERO_RATED = /zero[\s-]*rated|\b0(?:\.0+)?\s*%\s*(?:vat|value\s+added\s+tax)|(?:vat|value\s+added\s+tax)\s*(?:@|at|rate(?:\s+of)?)?\s*0(?:\.0+)?\s*%|نسبة\s*صفر|بنسبة\s*0\s*%|خاضع(?:ة)?\s*لنسبة\s*الصفر/i;
const EXEMPT = /(?:vat|value\s+added\s+tax)[\s-]*exempt(?!ion)|exempt(?!ion)(?:ed)?\s+(?:from\s+)?(?:vat|value\s+added\s+tax)|exempt\s+supply|معفا?ة?\s*من\s*(?:ال)?ضريبة/i;
/** 'exclusive' | 'inclusive' | null: the basis the text's clauses state. */
function clauseBasis(t: string): 'exclusive' | 'inclusive' | null {
  const parts: string[] = [];
  for (const sentence of t.split(/[;\n]+|(?<!\b(?:incl|excl|no|nos|approx|qty))\.+(?=\s|$)|\s+but\s+/i)) {
    for (const piece of sentence.split(/,\s*/)) {
      // a comma piece that names no tax belongs to the clause before it ("VAT, where applicable, is included")
      if (parts.length && !TAX_WORD.test(piece) && TAX_WORD.test(parts[parts.length - 1])) parts[parts.length - 1] += ', ' + piece;
      else parts.push(piece);
    }
  }
  const seen = new Set(parts.map((c) => (EXCL.test(c) ? 'exclusive' : INCL.test(c) ? 'inclusive' : null)));
  return seen.has('exclusive') ? 'exclusive' : seen.has('inclusive') ? 'inclusive' : null;
}
const RATE = /(\d+(?:\.\d+)?)\s*%\s*(?:vat|ضريبة)|(?:vat|ضريبة(?: القيمة المضافة)?)\s*(?:@|at|بنسبة|of)?\s*(\d+(?:\.\d+)?)\s*%/i;
const r2 = (n: number) => Math.round(n * 100) / 100;

// ── A TOTAL THAT IS EXACTLY THE LINES PLUS 5% IS A TOTAL WITH VAT IN IT (accountant, 15 Nov 2026) ──────────────────────────
// Measured on the live site (journey A, run 8288bec3): Polar Tech Contracting's quotation carried a TRN and one total, "Total
// price (inclusive of VAT) AED 18,854.85", over six lines adding up to AED 17,957.00 (17,957.00 x 1.05 = 18,854.85). Its
// reading failed (HTTP 503), the form said "before VAT", and readVat took the stated basis (and a portal figure equal to the
// total) over the figures: stored as excluding VAT 18,854.85, VAT none. The comparison ranked it 5% too high and the reveal
// fee would have been 3% of 18,854.85 instead of 17,957.00. A free-text "explanation" of the 5% gap then released it.
// Now: the supplier's own lines, when they add up to the total less exactly the UAE 5% VAT, are evidence of the basis.
//   - stated (or written) INCLUSIVE + the lines fit       -> price excluding VAT = total / 1.05 (the lines' own sum, to the fils)
//   - stated INCLUSIVE + a valid UAE TRN, no rate written  -> total / 1.05: a VAT-registered UAE supplier charges the 5% rate
//   - stated EXCLUSIVE (or a portal ex-VAT figure equal to the total) + the lines fit -> NOT settled (basis_conflict): held,
//     and the supplier is asked the one VAT question, unless he has already answered that question on the hold desk
//   - inclusive with no TRN, no rate, no VAT amount and no lines that fit -> not settled, as before: never guessed
/** Rounding of VAT to the fils, line by line, drifts by at most a few fils: the same tolerance the reading uses (model_reading.ts). */
export const VAT_GAP_TOLERANCE = 0.05;
/** True when `total` is `linesSum` plus exactly the UAE 5% VAT (to the fils, within VAT_GAP_TOLERANCE). */
export function vatOnTopOfLines(linesSum: number | null | undefined, total: number | null | undefined): boolean {
  const s = Number(linesSum), t = Number(total);
  if (!(s > 0) || !(t > 0) || t <= s) return false;
  return Math.abs(t - s * 1.05) <= VAT_GAP_TOLERANCE;
}
const UAE_RATE = 5;

export function readVat(i: {
  amount: number | null; subtotal?: number | null; vat_amount?: number | null; text?: string | null; stated?: string | null; price_ex_vat?: number | null;
  /** The sum of the supplier's priced lines (ex-VAT as itemised), single-option quotations only. */
  lines_sum?: number | null;
  /** The supplier's TRN when it came from his document but not through `text` (a model reading, the portal form). */
  trn?: string | null;
  /** He answered the VAT-basis question on the hold desk: his answer stands, the figures no longer reopen it. */
  answered?: boolean;
}): VatRead {
  const t = normText(String(i.text ?? ''));
  const trn = findTrn(String(i.text ?? '')) || (/^100\d{12}$/.test(String(i.trn ?? '')) ? String(i.trn) : null);
  const rm = t.match(RATE); const rate = rm ? Number(rm[1] || rm[2]) : null;
  const amt = Number(i.amount) > 0 ? Number(i.amount) : null;
  const vat = Number(i.vat_amount) > 0 ? Number(i.vat_amount) : null;
  const sub = Number(i.subtotal) > 0 ? Number(i.subtotal) : null;
  const base = { vat_amount: vat, vat_rate: rate, trn };
  // The figures say VAT is in the total, and nothing written says what it is: the supplier is asked (see the note above).
  const gap = !i.answered && !vat && !sub && vatOnTopOfLines(i.lines_sum, amt);
  const conflict = (): VatRead => ({ treatment: 'not_stated', price_ex_vat: null, ...base, basis_conflict: true });
  if (Number(i.price_ex_vat) > 0) {
    // A portal ex-VAT figure that IS the VAT-inclusive total (the lines plus exactly 5%) settles nothing.
    if (gap && amt && Math.abs(Number(i.price_ex_vat) - amt) <= VAT_GAP_TOLERANCE) return conflict();
    return { treatment: 'confirmed_on_portal', price_ex_vat: r2(Number(i.price_ex_vat)), ...base };
  }
  if (i.stated === 'not_registered' || NOT_REG.test(t)) return { treatment: 'not_registered', price_ex_vat: amt, ...base, vat_amount: null };
  if (sub && vat) return { treatment: 'exclusive', price_ex_vat: sub, ...base };
  if (i.stated === 'zero_rated' || (i.stated !== 'inclusive' && i.stated !== 'exclusive' && ZERO_RATED.test(t) && !(vat && vat > 0))) return { treatment: 'zero_rated', price_ex_vat: amt, ...base, vat_amount: null };
  if (i.stated === 'exempt' || (i.stated !== 'inclusive' && i.stated !== 'exclusive' && EXEMPT.test(t) && !(vat && vat > 0))) return { treatment: 'exempt', price_ex_vat: amt, ...base, vat_amount: null };
  const basis = clauseBasis(t);
  if (i.stated === 'exclusive' || (i.stated !== 'inclusive' && basis === 'exclusive')) {
    // "Subtotal 17,957 / total 18,854.85, prices exclude VAT": the VAT is added on top of the subtotal, which is the price.
    if (sub && vatOnTopOfLines(sub, amt)) return { treatment: 'exclusive', price_ex_vat: sub, ...base };
    return gap ? conflict() : { treatment: 'exclusive', price_ex_vat: amt, ...base };
  }
  if (i.stated === 'inclusive' || basis === 'inclusive') {
    if (amt && vat && vat < amt) return { treatment: 'inclusive', price_ex_vat: r2(amt - vat), ...base };
    if (amt && rate && rate > 0 && rate < 100) return { treatment: 'inclusive', price_ex_vat: r2(amt / (1 + rate / 100)), ...base };
    // No VAT amount and no rate written: the UAE rate applies when the document shows the supplier charges it, by his own
    // lines (they add up to the total less exactly 5%) or by his TRN (a VAT-registered UAE supplier charges 5%).
    if (amt && (vatOnTopOfLines(i.lines_sum, amt) || trn)) return { treatment: 'inclusive', price_ex_vat: r2(amt / (1 + UAE_RATE / 100)), ...base, vat_rate: UAE_RATE };
    return { treatment: 'inclusive', price_ex_vat: null, ...base };
  }
  return gap ? conflict() : { treatment: 'not_stated', price_ex_vat: null, ...base };
}
