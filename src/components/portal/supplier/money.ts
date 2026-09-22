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
  if (n === null || n === undefined) return '—';
  if (currency === 'AED') return aed(lang, Math.round(n));
  return currency + ' ' + num(Math.round(n));
};
