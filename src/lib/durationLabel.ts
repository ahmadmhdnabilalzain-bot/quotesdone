// A supplier's free-text duration ("12 months", "2 years", "10 days") in the reader's language.
// On an Arabic page the raw "12 months" rendered as "months 12": an English run inside RTL text,
// with the number on the wrong side (portal audit 14 Sep 2026). Text that is not a plain
// "<number> <unit>" is returned unchanged rather than guessed at.
const AR: Record<string, [string, string, string, string]> = {
  // [1, 2, 3-10, 11+]
  day: ['يوم واحد', 'يومان', 'أيام', 'يومًا'],
  week: ['أسبوع واحد', 'أسبوعان', 'أسابيع', 'أسبوعًا'],
  month: ['شهر واحد', 'شهران', 'أشهر', 'شهرًا'],
  year: ['سنة واحدة', 'سنتان', 'سنوات', 'سنة'],
};

// A count of days in Arabic with the number agreeing (0 = today, 1, 2, 3-10, 11+). The ONE helper every Arabic
// day count uses (review of #818: "${n} يومًا" was printed for 1, 2 and 3-10 too).
// Tested in durationLabel.test.mjs. Its edge twin is supabase/functions/_shared/ar_days.ts and its SQL twin
// public.fn_ar_days(int); every_arabic_message_is_written_not_translated.test.mjs keeps the three equal and
// fails on a template that prints a day count by hand.
// THE DUAL AFTER A PREPOSITION IS 'يومين', NOT 'يومان' (string audit 22 Sep 2026, CP-I18N-06).
// arDays(2) is the nominative dual, which is correct on its own ("يومان") and wrong after خلال,
// قبل or نحو, where Arabic needs the genitive: "خلال يومان" is the one form a native reader stops
// at. `genitive` changes THAT FORM ONLY — every other count is identical, which is why the edge twin
// (supabase/functions/_shared/ar_days.ts) and public.fn_ar_days need no change: they are only ever
// called without it, and the parity test compares the default.
export function arDays(n: number | string, opts?: { genitive?: boolean }): string {
  const k = Math.abs(Math.trunc(Number(n)));
  if (k === 0) return 'اليوم'; // "0 days left" reads as today
  // The genitive dual (main, CP-I18N-06) is the ONE form arCount cannot give: it depends on the
  // preposition in front of the count, not on the number. Every other count goes through arCount so
  // the two rules cannot drift, and the default is byte-identical to arCount(k, AR.day) — which is
  // what the edge twin, public.fn_ar_days and the parity test compare.
  if (k === 2 && opts && opts.genitive) return 'يومين';
  return arCount(k, AR.day);
}

/**
 * ARABIC NUMBER AGREEMENT FOR ANY COUNTED NOUN, NOT JUST DAYS.
 *
 * Audit 22 Sep 2026 (SP-I-04): the supplier portal printed "{n} استفسارًا" for every n, so one
 * inquiry read "1 استفسارًا" instead of "استفسار واحد" and two read "2 استفسارًا" instead of
 * "استفساران"; the same in InquiriesTab (bill-of-quantities lines, drawing pages) and in
 * QuoteReviewChat's open-point count. The four forms are the ones Arabic actually distinguishes,
 * and they are the same four `arDays` has always used — this is that rule, lifted out so a second
 * counted noun does not start a second, wrong, rule.
 *
 * forms = [singular (1), dual (2), plural genitive (3–10), accusative singular (11+)].
 * 1 and 2 return the noun WITHOUT a digit, because Arabic does not write one.
 */
export type ArForms = readonly [string, string, string, string];
export function arCount(n: number | string, forms: ArForms): string {
  const k = Math.abs(Math.trunc(Number(n)));
  if (k === 1) return forms[0];
  if (k === 2) return forms[1];
  return `${k} ${k <= 10 ? forms[2] : forms[3]}`;
}

export function durationLabel(text: string | null | undefined, lang: string): string {
  const s = String(text ?? '').trim();
  if (lang !== 'ar') return s;
  const m = s.match(/^(\d+)\s*(day|week|month|year|yr|mo)s?\.?$/i);
  if (!m) return s;
  const n = Number(m[1]);
  const unit = { yr: 'year', mo: 'month' }[m[2].toLowerCase()] ?? m[2].toLowerCase();
  const f = AR[unit];
  if (n === 1) return f[0];
  if (n === 2) return f[1];
  return `${n} ${n <= 10 ? f[2] : f[3]}`;
}
