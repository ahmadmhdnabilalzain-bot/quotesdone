// THE ONE MONEY FORMATTER FOR THE SUPPLIER PORTAL.
//
// Audit 22 Sep 2026 (SP-I-10): the same amount was written three ways on the same supplier's screen
// — `aed()` in SupplierPortal.tsx ("AED 1,200" in both languages), `aedIn()` in quoteReviewApi.ts
// ("1,200 د.إ" on /ar) and a hard-coded "AED " + n in SpecHold.tsx:161. Ten other places called
// `toLocaleString()` with no locale at all, so the group separator was the VIEWER's browser locale,
// not the page's: a supplier reading /ar in a de-DE browser saw "1.200".
//
// One rule: Arabic pages read "1,200 د.إ", English pages "AED 1,200", the digits are always Western
// (UAE invoices and Stripe are, and a quotation total has to match the PDF), and the locale is
// always named. Wrap the output in <Ltr> where it sits inside an RTL sentence.
export type Lang = 'en' | 'ar';

/** A money amount in the reader's language. `decimals` for a figure that must balance to the fils. */
export function aed(lang: Lang | string, n: number | null | undefined, decimals = 0): string {
  const v = Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  return lang === 'ar' ? v + ' د.إ' : 'AED ' + v;
}

/** A plain count (no currency) with a named locale, so the separator does not follow the browser. */
export const num = (n: number | null | undefined, decimals = 0): string =>
  Number(n || 0).toLocaleString('en-AE', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });

/**
 * A MARKET PRICE, WHICH IS NOT THE SAME THING AS AN AMOUNT OWED.
 *
 * MarketIntelligence and SupplierQuoteBuilder each carried a byte-identical private copy of this —
 * the fourth and fifth AED format on the supplier's screen. It differs from `aed` in three ways
 * that are all deliberate, so folding it into `aed` would lose them: a missing figure renders as an
 * em dash rather than as zero (a price the platform has not computed is NOT "AED 0"); the figure is
 * rounded to the dirham because the sample behind a market median cannot support the fils; and the
 * currency is whatever the routine returned, since a quotation may be priced in USD.
 */
export const price = (lang: Lang | string, n: number | null | undefined, currency = 'AED'): string => {
  // NOT JUST null/undefined (review of #858, 23 Sep 2026). The guard used to name those two, and an
  // NaN fell past it into `aed`, where `Number(n || 0)` turns NaN into 0 — so a price the routine
  // could not compute printed "AED 0", the exact sentence this function exists to avoid. A market
  // median arrives as NaN whenever the payload's figure is a string the JSON carried unparsed.
  const v = Number(n);
  if (!Number.isFinite(v)) return '—';
  if (currency === 'AED') return aed(lang, Math.round(v));
  return currency + ' ' + num(Math.round(v));
};

/** THE SUPPLIER'S OWN QUOTED FIGURE (sales_engineer, 13 Nov 2026). A quotation held for its VAT basis stores no fee base
 * (quote_amount NULL, stated_price.ts storedPrice), and aed() prints NULL as 0, so the supplier read "AED 0" for his own
 * quotation. It shows the total as he stated it, and says it waits for his VAT answer. English: suppliers read English only. */
export function quotedAmount(lang: Lang | string, q: { quote_amount?: number | null; amount_as_stated?: number | null }): string {
  if (q.quote_amount != null && Number(q.quote_amount) > 0) return aed(lang, q.quote_amount);
  if (q.amount_as_stated != null && Number(q.amount_as_stated) > 0) return `${aed(lang, q.amount_as_stated)} as stated, waiting for your VAT answer`;
  return '—';
}
