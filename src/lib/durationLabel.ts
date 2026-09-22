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
export function arDays(n: number | string): string {
  const k = Math.abs(Math.trunc(Number(n)));
  const f = AR.day;
  if (k === 0) return 'اليوم'; // "0 days left" reads as today
  if (k === 1) return f[0];
  if (k === 2) return f[1];
  return `${k} ${k <= 10 ? f[2] : f[3]}`;
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
