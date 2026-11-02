// Does a line still need Arabic? A SCRIPT test, not a meaning test (founder ruling 890: no word matching).
//
// 2 Nov 2026, journey run 41459344864: the Arabic comparison report answered 202 "held" and never arrived. Measured:
// 9 of the 15 lines its waiter waited on were ALREADY Arabic — quote_compare's own Arabic analysis ("المورّد C
// (مستبعد)", "الزجاج بلا طبقة Low-E") — held only because a supplier label (A, B, C) or a code (AWS 70, Low-E) put a
// Latin letter in them. No reader is asked to translate Arabic into Arabic, so no translation was ever stored, the
// waiter was never ready, and the customer never got the report (3 waiters open, 0 compare_report_ar notices in 14 days).
// A line whose letters are mostly Arabic IS Arabic, with its labels and codes kept as written; a line whose letters are
// mostly Latin still needs Arabic. One rule, read by the page builder (quote_documents.ts) and the translator
// (reasoned_governance.ts needsArabic), so the two can never disagree about what is missing.
// prevented by: _shared/arabic_script.test.ts
const count = (s: string, re: RegExp) => (s.match(re) || []).length;
export function needsArabic(s: string): boolean {
  const t = String(s ?? '');
  const latin = count(t, /[A-Za-z]/g);
  return latin > 0 && latin >= count(t, /[؀-ۿ]/g);
}
