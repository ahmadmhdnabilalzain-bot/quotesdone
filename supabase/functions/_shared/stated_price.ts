// stated_price.ts — the supplier's price EXACTLY as the supplier stated it, and the one figure our fee is taken on.
// Seat: sales_engineer (the quotation and the comparison); the fee wording is the accountant's.
//
// FOUNDER RULING 1207 (13 Oct 2026). A supplier's quotation may state anything — a discount, VAT or no VAT, any
// terms. QuotesDone redoes it in its own template and shows the customer EXACTLY what the supplier stated
// ("AED 2,000, after discount AED 1,700"), and says plainly that QuotesDone is not responsible for the supplier's
// quotation details. "No card fee / no VAT" is about OUR fee only. This SUPERSEDES the 14 Sep 2026 ruling that hid
// the supplier's VAT from the customer: the supplier's VAT treatment and amount are now shown as written. The
// supplier's TRN is still never shown — it names the company, which the customer pays to reveal (maskContacts).
//
// FOUNDER RULING 1208 (13 Oct 2026). Our 3% is taken on the supplier's FINAL quoted price BEFORE VAT, after any
// discount the supplier states: AED 2,000 → after discount 1,700, + VAT → fee = 3% × 1,700. Never the gross.
// quotes.price_ex_vat holds that figure and quotes.quote_amount (what revealCharge reads) is set from it.
//
// THE COMPARISON BASIS. The ranking and every "cheapest" in the comparison use the same figure: the price after
// the stated discount, excluding VAT (fee_base). One basis for the ranking and for the fee, so the quote ranked
// cheapest is also the one whose fee is lowest.
//
// Pure: no I/O. prevented by: _shared/stated_price.test.ts
import { readVat, type VatRead, type VatTreatment } from './line_specs/vat.ts';
import { aed, figure } from './money.ts';
import { normText } from './line_specs/model.ts';

/** "after discount", "net total": the figure written after the discount. */
export const AFTER_DISCOUNT = /after\s*(?:the\s*)?discount|net\s*(?:total|amount|price|value)|بعد\s*الخصم|الصافي|صافي/i;
const r2 = (n: number) => Math.round(n * 100) / 100;
const pos = (v: unknown): number | null => { const n = Number(v); return v != null && v !== '' && Number.isFinite(n) && n > 0 ? n : null; };

/** A discount written in words: "Discount 10%", "Less: special discount AED 300", "خصم 15%". The amount wins over a rate. */
export function readDiscount(text: string): { amount: number | null; pct: number | null; label: string } | null {
  const t = normText(String(text || ''));
  const m = t.match(/((?:special\s+|trade\s+|project\s+|cash\s+|early[\s-]payment\s+)?(?:discount|rebate)|خصم(?:\s+خاص)?)\s*(?:of\s*|بنسبة\s*|[:\-–]\s*)?(?:\(?\s*(\d+(?:\.\d+)?)\s*%\s*\)?)?\s*[:\-–=]?\s*(?:less\s*)?(?:AED|Dhs?\.?|درهم|د\.إ\.?)?\s*\(?-?\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)?/i);
  if (!m) return null;
  // A CONDITIONAL discount ("2% discount for payment within 7 days") is a payment term, not the quoted price: the
  // fee is never reduced on a condition the customer may not meet. It stays in the supplier's terms as written.
  const at = m.index ?? 0;
  const sentence = t.slice(Math.max(0, t.lastIndexOf('\n', at), t.lastIndexOf('. ', at)), (t.indexOf('.', at + m[0].length) + 1 || t.length));
  if (/early[\s-]*payment|advance\s+payment|\bif\b|\bwithin\s+\d+\s*days|subject\s+to|\bfor\s+(?:payment|orders?\s+(?:above|over))|إذا|في حال|عند\s+الدفع|بشرط/i.test(sentence)) return null;
  const pct = m[2] ? Number(m[2]) : null;
  const amount = m[3] ? Number(m[3].replace(/,/g, '')) : null;
  if (!(pct && pct > 0 && pct < 100) && !(amount && amount > 0)) return null;
  return { amount: amount && amount > 0 ? amount : null, pct: pct && pct > 0 && pct < 100 ? pct : null, label: m[0].replace(/\s+/g, ' ').trim().slice(0, 80) };
}

export type StatedPrice = VatRead & {
  /** The supplier's price before its discount, as stated. Null when no discount is stated. */
  gross_amount: number | null;
  /** The discount the supplier stated, in AED. */
  discount_amount: number | null;
  /** The supplier's own words for it ("Special discount 15%"). */
  discount_label: string | null;
  /** The supplier's final total as written (after the discount; with VAT when the supplier added it). */
  total_as_stated: number | null;
  /** Ruling 1208: the price after the discount, excluding VAT. Our fee and the comparison ranking use this. */
  fee_base: number | null;
};

/**
 * Inputs, as the supplier stated them:
 *   amount     — the quotation's final total as written (may be before the discount when no after-discount
 *                figure was written; `amount_is_gross` says so)
 *   subtotal   — an ex-VAT subtotal, BEFORE the discount when a discount follows it
 *   vat_amount — the VAT the supplier added
 *   gross_amount / discount_amount / discount_pct / discount_label — the discount, when stated
 *   net_amount — an explicit "after discount" / "net" figure, ex-VAT
 */
export function statedPrice(i: {
  amount: number | null; subtotal?: number | null; vat_amount?: number | null; text?: string | null; stated?: string | null;
  price_ex_vat?: number | null; gross_amount?: number | null; discount_amount?: number | null; discount_pct?: number | null;
  discount_label?: string | null; net_amount?: number | null; amount_is_gross?: boolean;
}): StatedPrice {
  const read = (!pos(i.discount_amount) && !pos(i.discount_pct)) ? readDiscount(String(i.text ?? '')) : null;
  const pct = pos(i.discount_pct) ?? read?.pct ?? null;
  let gross = pos(i.gross_amount) ?? pos(i.subtotal);
  const net = pos(i.net_amount);
  let disc = pos(i.discount_amount) ?? read?.amount ?? null;
  if (disc == null && pct != null && gross != null) disc = r2(gross * pct / 100);
  if (disc == null && gross != null && net != null && gross > net) disc = r2(gross - net);
  const label = (String(i.discount_label ?? '').trim() || read?.label || (pct != null ? `Discount ${pct}%` : disc != null ? 'Discount' : '')).slice(0, 80) || null;

  if (disc == null || !(disc > 0)) {
    const v = readVat({ amount: pos(i.amount), subtotal: pos(i.subtotal), vat_amount: pos(i.vat_amount), text: i.text, stated: i.stated, price_ex_vat: pos(i.price_ex_vat) });
    return { ...keepStated(v, i.stated), gross_amount: null, discount_amount: null, discount_label: null, total_as_stated: pos(i.amount), fee_base: v.price_ex_vat };
  }
  // The figure after the discount, ex-VAT, when the supplier wrote enough to know it.
  if (gross == null && net != null) gross = r2(net + disc);
  let total = pos(i.amount);
  // A discount written AFTER the total in the supplier's own text, with no after-discount figure, discounts that total.
  const tx = normText(String(i.text ?? ''));
  const totalFirst = !!read && !AFTER_DISCOUNT.test(tx) && (() => { const a = tx.search(/\btotal\b|الإجمالي|المجموع/i); const d = tx.search(/discount|rebate|خصم/i); return a >= 0 && d > a; })();
  if (total != null && (i.amount_is_gross || totalFirst || (gross != null && Math.abs(total - gross) <= 0.01 && !pos(i.vat_amount)))) {
    // The only total written is the price before the discount: the final total is that less the discount.
    if (gross == null) gross = total;
    total = r2(total - disc);
  }
  if (total == null && gross != null) total = r2(gross - disc);
  const afterSub = pos(i.subtotal) != null ? r2(pos(i.subtotal)! - disc) : net;
  // The VAT basis is read on the figures AFTER the discount: a subtotal is an ex-VAT figure, so the subtotal less
  // the discount is the price ex-VAT; an inclusive total is already after the discount.
  const v = readVat({ amount: total, subtotal: afterSub, vat_amount: pos(i.vat_amount), text: i.text, stated: i.stated, price_ex_vat: pos(i.price_ex_vat) });
  if (gross == null && v.price_ex_vat != null) gross = r2(v.price_ex_vat + disc);
  return { ...keepStated(v, i.stated), gross_amount: gross, discount_amount: disc, discount_label: label, total_as_stated: total, fee_base: v.price_ex_vat };
}

/** A figure confirmed on the portal keeps the treatment the supplier stated (inclusive / exclusive / not registered):
 * the customer is shown the supplier's VAT as stated (ruling 1207); the price is the same either way. */
function keepStated(v: VatRead, stated: string | null | undefined): VatRead {
  return v.treatment === 'confirmed_on_portal' && ['exclusive', 'inclusive', 'not_registered'].includes(String(stated)) ? { ...v, treatment: stated as VatTreatment } : v;
}

// ── What the customer reads ──────────────────────────────────────────────────────────────────────
export type PriceRow = {
  quote_amount?: number | null; price_ex_vat?: number | null; gross_amount?: number | null; discount_amount?: number | null;
  discount_label?: string | null; vat_treatment?: string | null; vat_amount?: number | null; amount_as_stated?: number | null;
};
type L = 'en' | 'ar';
const money = (v: unknown, lang: L) => aed(v, lang, !Number.isInteger(Number(v)));

/** Ruling 1208: the figure our fee is taken on — after the stated discount, excluding VAT. It is quotes.quote_amount,
 * the column every charge path (revealCharge in customer_api, stripe_checkout, element_pay) reads, so what a page
 * says the fee is taken on is the figure the card is charged on. storedPrice() writes it from the ex-VAT price. */
export function feeBaseOf(q: PriceRow): number | null { return pos(q.quote_amount) ?? pos(q.price_ex_vat); }

/** "AED 2,000, after discount AED 1,700" — or the one price when no discount was stated. Ex-VAT figures. */
export function priceStated(q: PriceRow, lang: L): string {
  const fin = feeBaseOf(q); const g = pos(q.gross_amount); const d = pos(q.discount_amount);
  if (fin == null) return '—';
  if (g != null && d != null && g > fin) return lang === 'ar' ? `${money(g, lang)}، وبعد الخصم ${money(fin, lang)}` : `${money(g, lang)}, after discount ${money(fin, lang)}`;
  return money(fin, lang);
}

/** The supplier's VAT, exactly as stated: the treatment and the amount. Never the TRN. */
export function vatStated(q: PriceRow, lang: L): string {
  const t = String(q.vat_treatment || 'not_stated') as VatTreatment; const vat = pos(q.vat_amount); const fin = feeBaseOf(q);
  const ar = lang === 'ar';
  if (t === 'not_registered') return ar ? 'يذكر المورّد أنه غير مسجّل في ضريبة القيمة المضافة، فلا تُضاف ضريبة على سعره.' : 'The supplier states it is not VAT-registered, so no VAT is added to its price.';
  if (t === 'inclusive') return ar ? `يذكر المورّد أن إجماليه شامل ضريبة القيمة المضافة${vat ? ` (${money(vat, lang)})` : ''}${pos(q.amount_as_stated) ? `، والإجمالي كما ذكره ${money(q.amount_as_stated, lang)}` : ''}.` : `The supplier states its total includes VAT${vat ? ` (${money(vat, lang)})` : ''}${pos(q.amount_as_stated) ? `; total as stated ${money(q.amount_as_stated, lang)}` : ''}.`;
  if (t === 'exclusive' || t === 'confirmed_on_portal') {
    if (vat && fin) return ar ? `يضيف المورّد ضريبة القيمة المضافة ${money(vat, lang)}، فيصبح الإجمالي شاملًا الضريبة ${money(r2(fin + vat), lang)} كما ذكره.` : `The supplier adds VAT of ${money(vat, lang)}: total including VAT ${money(r2(fin + vat), lang)}, as stated.`;
    return ar ? 'يذكر المورّد أن سعره غير شامل ضريبة القيمة المضافة.' : 'The supplier states its price excludes VAT.';
  }
  return ar ? 'لم يذكر المورّد معالجة ضريبة القيمة المضافة.' : 'The supplier did not state how VAT applies.';
}

/** "3% of AED 1,700 = AED 51; no card fee, no VAT on our fee" — beside our fee, the only place no-VAT is said. */
export function feeBasisLine(base: number | null, rate: number, lang: L): string {
  const b = pos(base); const r = pos(rate);
  if (b == null || r == null) return lang === 'ar' ? 'لا رسوم بطاقة ولا ضريبة قيمة مضافة على رسومنا.' : 'No card fee, no VAT on our fee.';
  const pctTxt = `${r2(r * 100)}%`; const fee = Math.round(b * r * 100) / 100;
  return lang === 'ar'
    ? `رسومنا ${pctTxt} من ${money(b, lang)} = ${money(fee, lang)}، بلا رسوم بطاقة ولا ضريبة قيمة مضافة على رسومنا.`
    : `Our fee: ${pctTxt} of ${money(b, lang)} = ${money(fee, lang)}; no card fee, no VAT on our fee.`;
}

/** Ruling 1207: QuotesDone is not responsible for the supplier's quotation details. */
export const NOT_RESPONSIBLE = {
  en: 'The prices, discounts, VAT and terms on this page are exactly as the supplier stated them. QuotesDone is not responsible for the supplier\'s quotation details.',
  ar: 'الأسعار والخصومات وضريبة القيمة المضافة والشروط الواردة هنا كما ذكرها المورّد تمامًا. ولا تتحمّل QuotesDone أي مسؤولية عن تفاصيل عرض المورّد.',
};

/** Exported for a test of a single figure; `figure` keeps one formatter for both languages. */
export const _figure = figure;

/** The supplier's VAT in a table cell: "+ VAT AED 85 (AED 1,785 with VAT)", "VAT included", "Not VAT-registered", "Not stated". */
export function vatShort(q: PriceRow, lang: L): string {
  const t = String(q.vat_treatment || 'not_stated'); const vat = pos(q.vat_amount); const fin = feeBaseOf(q); const ar = lang === 'ar';
  if (t === 'not_registered') return ar ? 'غير مسجّل في الضريبة' : 'Not VAT-registered';
  if (t === 'inclusive') return ar ? `شامل الضريبة${vat ? ` (${money(vat, lang)})` : ''}` : `VAT included${vat ? ` (${money(vat, lang)})` : ''}`;
  if (t === 'exclusive' || t === 'confirmed_on_portal') {
    if (vat && fin) return ar ? `+ ضريبة ${money(vat, lang)} (${money(r2(fin + vat), lang)} شاملًا الضريبة)` : `+ VAT ${money(vat, lang)} (${money(r2(fin + vat), lang)} with VAT)`;
    return ar ? 'غير شامل الضريبة' : 'Excludes VAT';
  }
  return ar ? 'غير مذكورة' : 'Not stated';
}

/** The quotes-row price columns for a stated price. quote_amount — what revealCharge reads — is the fee base
 * (ruling 1208); only when no ex-VAT figure is known (the quote is then held for its VAT basis) does it fall back to
 * the final total as stated, which is after the discount, never the gross. */
export function storedPrice(sp: StatedPrice, statedAmount: number | null) {
  return {
    quote_amount: sp.fee_base ?? sp.total_as_stated ?? statedAmount, price_ex_vat: sp.price_ex_vat, vat_treatment: sp.treatment, vat_amount: sp.vat_amount,
    amount_as_stated: sp.total_as_stated ?? statedAmount, gross_amount: sp.gross_amount, discount_amount: sp.discount_amount,
  };
}
