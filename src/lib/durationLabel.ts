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
// The dual after a preposition is 'يومين', not 'يومان' (string audit 22 Sep 2026, CP-I18N-06); see
// the note inside the function for what this wrapper decides and what countedNoun.ts decides.
export function arDays(n: number | string, opts?: { genitive?: boolean }): string {
  const k = Math.abs(Math.trunc(Number(n)));
  if (k === 0) return 'اليوم'; // "0 days left" reads as today
  // THE COUNTING RULE IS OWNED BY src/lib/countedNoun.ts. THIS IS A WRAPPER, AND IT DOES NOT IMPORT
  // IT (re-review of #858, 23 Sep 2026, measured on node v24.16).
  //
  // #858 exported a SECOND four-form `arCount` from this file. countedNoun.ts had owned that rule
  // since CP-I18N-05 on 22 Sep, with the oblique dual and — the defect — a zero branch the copy
  // lacked, so an empty list printed the 3-10 plural. Every one of #858's six call sites now calls
  // countedNoun, and the export is gone; only this one-noun wrapper is left.
  //
  // WHY IT STILL SPELLS THE FOUR BRANCHES OUT INSTEAD OF DELEGATING. This file is loaded straight
  // into node by durationLabel.test.mjs, where an extensionless relative import is
  // ERR_MODULE_NOT_FOUND, and './countedNoun.ts' is TS5097 under the repo's tsconfig
  // (allowImportingTsExtensions is off) — both measured, in that order. The same constraint is
  // documented in supplier/workspaceCopy.ts. So the equality is asserted in the TEST, which can
  // import both: durationLabel.test.mjs requires arDays(n) === arCount(n, AR_NOUN.day) for every n
  // but 0, and arDays(2, {genitive}) === the owner's oblique dual. Drift fails there.
  //
  // Its own two decisions: 0 reads "today" rather than "0 days", and the genitive dual after خلال /
  // قبل / نحو (main, CP-I18N-06) — "خلال يومان" is the one form a native reader stops at.
  // The edge twin supabase/functions/_shared/ar_days.ts and public.fn_ar_days are only ever called
  // without `genitive`, and the parity test compares the default, so neither needs to change.
  const f = AR.day;
  if (k === 1) return f[0];
  if (k === 2) return opts && opts.genitive ? 'يومين' : f[1];
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
