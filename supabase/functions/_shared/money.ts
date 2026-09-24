// money.ts — the ONE way a customer document writes an amount of dirhams, in either language.
// Seat: sales_engineer (the quotation and comparison documents).
//
// 23 Sep 2026. The quotation had three formatters (the totals, the line table and the comparison's price
// range), each its own toLocaleString call. The figures agreed only because the three happened to be
// written alike. Both languages now take the digits from figure(): Western digits, en-AE grouping, the
// same decimals — the Arabic page differs from the English one only in the unit's word and its side.
// Pure: no I/O.

export type MoneyLang = 'en' | 'ar';

/** The figure alone: "118,520.00" (dec) or "118,520". Not a positive number → "—". */
export function figure(v: unknown, dec = false): string {
  const n = Number(v);
  if (v == null || v === '' || !Number.isFinite(n) || !(n > 0)) return '—';
  return n.toLocaleString('en-AE', { minimumFractionDigits: dec ? 2 : 0, maximumFractionDigits: dec ? 2 : 0 });
}

/** The amount with its unit in the page's language: "AED 118,520.00" / "118,520.00 درهم". */
export function aed(v: unknown, lang: MoneyLang, dec = false): string {
  const f = figure(v, dec);
  if (f === '—') return f;
  return lang === 'ar' ? `${f} درهم` : `AED ${f}`;
}

/** A price range: "AED 90,000–112,000" / "90,000–112,000 درهم"; fils are kept when either end has them. */
export function aedRange(lo: unknown, hi: unknown, lang: MoneyLang): string {
  const dec = !Number.isInteger(Number(lo)) || !Number.isInteger(Number(hi));
  const r = `${figure(lo, dec)}–${figure(hi, dec)}`;
  return lang === 'ar' ? `${r} درهم` : `AED ${r}`;
}
