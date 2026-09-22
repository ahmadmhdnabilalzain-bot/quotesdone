// A count of days in Arabic with the number agreeing: 0 today, 1, 2, 3-10, 11+ (review of #818).
// The edge-function twin of arDays() in src/lib/durationLabel.ts and of public.fn_ar_days(int) in
// scripts/sql/every_arabic_message_is_written_not_translated.sql. Edge functions cannot import from
// src/, so the three are kept identical by scripts/checks/every_arabic_message_is_written_not_translated.test.mjs.
export function arDays(n: number | string): string {
  const k = Math.abs(Math.trunc(Number(n)));
  if (k === 0) return 'اليوم';
  if (k === 1) return 'يوم واحد';
  if (k === 2) return 'يومان';
  return `${k} ${k <= 10 ? 'أيام' : 'يومًا'}`;
}
