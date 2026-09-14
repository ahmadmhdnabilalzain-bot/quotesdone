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
