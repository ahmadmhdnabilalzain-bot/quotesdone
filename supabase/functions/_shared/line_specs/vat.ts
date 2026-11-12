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
// amount or rate stated. Anything else — including silence — is not stated, never assumed.
import { normText } from './model.ts';
import { findTrn } from '../identity_numbers.ts';

export type VatTreatment = 'exclusive' | 'inclusive' | 'not_registered' | 'not_stated' | 'confirmed_on_portal';
export type VatRead = { treatment: VatTreatment; price_ex_vat: number | null; vat_amount: number | null; vat_rate: number | null; trn: string | null };

const NOT_REG = /not\s*(?:vat\s*)?registered(?:\s*for\s*vat)?|no\s*vat\s*(?:applicable|charged)?\b|vat\s*(?:is\s*)?not\s*applicable|غير مسجل(?:ة)?\s*(?:في|ب|لدى)?\s*(?:ضريبة|الضريبة)|بدون ضريبة|لا توجد ضريبة/i;
// 15 Sep 2026: "prices exclude VAT" read as not stated — INCL already took "include(s)", EXCL did not.
// 12 Nov 2026 (sales_engineer, final-audit fix review round 4): a NEGATED "include" is exclusive. "Prices do not include 5% VAT."
// matched INCL ("include ... 5% VAT") and a 6,120 quotation was compared and charged 3% on 5,828.57. EXCL is tested first.
const EXCL = /(?:do(?:es)?\s*not|don'?t|doesn'?t|not)\s*includ(?:e|es|ed|ing)\s*(?:the\s*)?(?:\d+(?:\.\d+)?\s*%\s*)?vat|vat\s*(?:is\s*|are\s*)?not\s*included|excl(?:uding|usive|udes?|\.)?\s*(?:of\s*)?(?:the\s*)?(?:\d+(?:\.\d+)?\s*%\s*)?vat|vat\s*(?:is\s*)?(?:excluded|extra|additional|not\s*included)|\+\s*vat|plus\s*vat|before\s*vat|غير شامل\s*(?:ل)?(?:ال)?ضريبة|قبل (?:ال)?ضريبة|لا يشمل\s*(?:ال)?ضريبة|\+\s*(?:ال)?ضريبة/i;
const INCL = /incl(?:uding|usive|udes?|\.)?\s*(?:of\s*)?(?:the\s*)?(?:\d+(?:\.\d+)?\s*%\s*)?vat|vat\s*(?:is\s*)?included|with\s*vat|شامل\s*(?:ل)?(?:ال)?ضريبة|يشمل\s*(?:ال)?ضريبة|متضمن\s*(?:ال)?ضريبة/i;
const RATE = /(\d+(?:\.\d+)?)\s*%\s*(?:vat|ضريبة)|(?:vat|ضريبة(?: القيمة المضافة)?)\s*(?:@|at|بنسبة|of)?\s*(\d+(?:\.\d+)?)\s*%/i;
const r2 = (n: number) => Math.round(n * 100) / 100;

export function readVat(i: { amount: number | null; subtotal?: number | null; vat_amount?: number | null; text?: string | null; stated?: string | null; price_ex_vat?: number | null }): VatRead {
  const t = normText(String(i.text ?? ''));
  const trn = findTrn(String(i.text ?? ''));
  const rm = t.match(RATE); const rate = rm ? Number(rm[1] || rm[2]) : null;
  const amt = Number(i.amount) > 0 ? Number(i.amount) : null;
  const vat = Number(i.vat_amount) > 0 ? Number(i.vat_amount) : null;
  const sub = Number(i.subtotal) > 0 ? Number(i.subtotal) : null;
  const base = { vat_amount: vat, vat_rate: rate, trn };
  if (Number(i.price_ex_vat) > 0) return { treatment: 'confirmed_on_portal', price_ex_vat: r2(Number(i.price_ex_vat)), ...base };
  if (i.stated === 'not_registered' || NOT_REG.test(t)) return { treatment: 'not_registered', price_ex_vat: amt, ...base, vat_amount: null };
  if (sub && vat) return { treatment: 'exclusive', price_ex_vat: sub, ...base };
  if (i.stated === 'exclusive' || EXCL.test(t)) return { treatment: 'exclusive', price_ex_vat: amt, ...base };
  if (i.stated === 'inclusive' || INCL.test(t)) {
    if (amt && vat && vat < amt) return { treatment: 'inclusive', price_ex_vat: r2(amt - vat), ...base };
    if (amt && rate && rate > 0 && rate < 100) return { treatment: 'inclusive', price_ex_vat: r2(amt / (1 + rate / 100)), ...base };
    return { treatment: 'inclusive', price_ex_vat: null, ...base };
  }
  return { treatment: 'not_stated', price_ex_vat: null, ...base };
}
