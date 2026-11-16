// _shared/customer_question_words.ts -- the few words every customer question shares ("Not sure", the Arabic frame, the
// Arabic of a tapped option), without the question tables (16 Nov 2026, sales_engineer). Moved out of customer_questions.ts
// so the interview's readers (inquiry_intake/interview.ts, which supplier_api bundles through intake_requirements.ts) do not
// pull ~430 KB of tables into supplier_api: its deploy of 16 Nov 02:30 UTC was refused at the 5 MB limit.
// customer_questions.ts re-exports everything here, so every other importer is unchanged.
import { SPEC_OPTION_AR } from './spec_options_ar.ts';

export type Lang = 'en' | 'ar';
export const NOT_SURE: Readonly<Record<Lang, string>> = { en: 'Not sure', ar: 'لست متأكدًا' };

export function plainFrame(label: string): string {
  const s = String(label ?? '').replace(/\s*\([^)]*\)/g, '').replace(/\s+/g, ' ').trim();
  if (!s) return '';
  return `${s.charAt(0).toUpperCase() + s.slice(1)}? If you are not sure, tap "${NOT_SURE.en}" and the supplier will advise.`;
}
/** The Arabic card for a spec with no Arabic of its own and no plain wording from the model this turn: an Arabic sentence
 *  that asks for the detail without naming it in English, with "Not sure" (the reply names it in Arabic when it is written). */
export const ARABIC_FRAME = 'يحتاج المورّد إلى تفصيلة أخرى عن هذا العمل ليعطيكم سعرًا دقيقًا: صِفوها بكلماتكم، أو أرسلوا صورة. إن لم تكونوا متأكدين فاختاروا «لست متأكدًا» وسيقترح المورّد.';

const ARABIC_LETTER = /[\u0600-\u06FF]/;
const SPEC_OPTION_AR_LOWER = new Map(Object.entries(SPEC_OPTION_AR).map(([k, v]) => [k.trim().toLowerCase(), v]));
/** The Arabic label of an English option, or null when there is none. */
export function optionAr(o: string): string | null {
  const k = String(o ?? '').trim();
  const v = SPEC_OPTION_AR[k] ?? SPEC_OPTION_AR_LOWER.get(k.toLowerCase()) ?? null;
  return v && ARABIC_LETTER.test(v) ? v : null;
}
/** Two Arabic labels are the same words whatever their diacritics ("متأكداً" and "متأكدًا"). */
export const sameArabic = (a: string, b: string): boolean => {
  const n = (x: string) => String(x ?? '').replace(/[\u064B-\u0652\u0640]/g, '').replace(/\s+/g, ' ').trim();
  return n(a) === n(b);
};
export const saysNotSureAr = (a: string): boolean => {
  const n = (x: string) => String(x ?? '').replace(/[\u064B-\u0652\u0640]/g, '');
  return n(a).includes(n(NOT_SURE.ar));
};
