import { arUnit as glossaryUnit, arCount as glossaryCount, CATEGORY_AR, CATEGORY_EN, WORKING_FORMS, UNIT_FORMS, type Unit } from '../trade_glossary_ar.ts';

// ── Deterministic Arabic for what the platform knows ───────────────────────────────────────────────
const hasArabic = (s: unknown) => /[؀-ۿ]/.test(String(s ?? ''));
const norm = (s: unknown) => String(s ?? '').toLowerCase().replace(/[_]+/g, ' ').replace(/\s+/g, ' ').trim();
export const arCount = glossaryCount;
export const arUnit = glossaryUnit;

const EMIRATES: Record<string, string> = {
  'dubai': 'دبي', 'abu dhabi': 'أبوظبي', 'sharjah': 'الشارقة', 'ajman': 'عجمان', 'umm al quwain': 'أم القيوين',
  'umm al-quwain': 'أم القيوين', 'ras al khaimah': 'رأس الخيمة', 'ras al-khaimah': 'رأس الخيمة', 'rak': 'رأس الخيمة',
  'fujairah': 'الفجيرة', 'al ain': 'العين', 'uae': 'الإمارات العربية المتحدة', 'all emirates': 'جميع الإمارات',
};
export function arEmirate(s: unknown): string | null { if (hasArabic(s)) return String(s); return EMIRATES[norm(s)] ?? null; }

/** The English trade name as a person writes it: 'hvac' → 'HVAC', 'fit_out' → 'Fit Out'. */
export function enCategory(s: unknown): string {
  const code = String(s ?? '').toLowerCase().trim();
  if (CATEGORY_EN[code]) return CATEGORY_EN[code];
  const n = norm(s); if (!n) return '';
  if (/^(hvac|mep|cctv|it|ac)$/.test(n)) return n.toUpperCase();
  return n.replace(/\b[a-z]/g, (c) => c.toUpperCase());
}
export function arCategory(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const code = String(s ?? '').toLowerCase().trim();
  if (CATEGORY_AR[code]) return CATEGORY_AR[code];
  // A trade that is not one of our category keys is free text: the caller reasons it (k.loc), never a word list.
  return null;
}

const UNIT_OF: Record<string, Unit> = { day: 'day', days: 'day', week: 'week', weeks: 'week', wk: 'week', wks: 'week', month: 'month', months: 'month', mo: 'month', mos: 'month', year: 'year', years: 'year', yr: 'year', yrs: 'year' };
/** A duration that is ONLY a number (or range) and a unit — "2 weeks", "10-14 days", "3 working days" — in Arabic,
 * or null. This is format parsing of a number and its unit and nothing else (decision point
 * documents.quote_duration_emirates, 23 Sep 2026): anything a person wrote around it ("immediate", "from order",
 * "after approval") is their words, and the document reasons it (loc) instead of substituting phrases. */
export function arDuration(s: unknown): string | null {
  if (hasArabic(s)) return String(s);
  const t = norm(s).replace(/\.$/, '');
  if (!t) return null;
  const m = t.match(/^(\d{1,4})(?:\s*(?:-|–)\s*(\d{1,4}))?\s*(working |business )?(days?|weeks?|wks?|months?|mos?|years?|yrs?)$/);
  if (!m) return null;
  const a = Number(m[1]), b = m[2] ? Number(m[2]) : null, unit = UNIT_OF[m[4]], working = !!m[3];
  if (!unit) return null;
  if (b === null) return arCount(a, unit, working);
  const f = working && unit === 'day' ? WORKING_FORMS : UNIT_FORMS[unit];
  return `${a}–${b} ${b >= 3 && b <= 10 ? f[2] : f[3]}`;
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { norm };
