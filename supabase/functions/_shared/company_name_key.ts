// THE NORMALISED KEY OF A COMPANY'S LEGAL NAME, IN TYPESCRIPT (12 Nov 2026, customer_support; founder ruling 1645, browser walk
// finding H10). The twin of public.fn_company_registration_name_key, the key leads_claimed_company_name_uidx refuses a second claimed
// company on. supplier_api/create_company.ts uses it to find the unclaimed directory listing a registration names. A normaliser: the
// Arabic in it is what people type (legal forms, letter variants), never a message.
// Pinned against the SQL in supplier_api/create_company.test.ts: 2,015 of 2,015 production names gave the same key, 12 Nov 2026.
const W = '[\\p{L}\\p{N}_]';
const word = (w: string) => new RegExp(`(?<!${W})${w}(?!${W})`, 'gu');
/**
 * The TypeScript twin of public.fn_company_registration_name_key (scripts/sql, full_schema 04_functions_fn_c.sql), step by
 * step: fn_ar_norm, lower, HTML entities, "&" is "and", dots and apostrophes vanish, any other run of non letters/digits is
 * one space, and the spelling of a legal form is folded (l l c -> llc ...). Pinned against the SQL in create_company.test.ts.
 */
export function companyNameKey(p: unknown): string | null {
  if (p == null) return null;
  const from = 'أإآٱىةؤئ٠١٢٣٤٥٦٧٨٩', to = 'اااايهوي0123456789';
  let s = [...String(p).replace(/[ً-ٰٕـۖ-ۭ]/g, '')].map((c) => { const i = from.indexOf(c); return i < 0 ? c : to[i]; }).join('').toLowerCase();
  s = s.replace(/&(amp|#0*38|#x0*26);/g, '&').replace(/&(apos|rsquo|lsquo|#0*39|#x0*27|#8216|#8217);/g, "'").replace(/&#?[a-z0-9]+;/g, ' ');
  s = s.replace(/&/g, ' and ').replace(/[.'’‘`]/g, '').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  for (const [a, b] of [['l l c', 'llc'], ['f z e', 'fze'], ['f z c o', 'fzco'], ['f ?z llc', 'fzllc'], ['establishment', 'est'], ['company', 'co'],
    ['ش ذ م م', 'شذمم'], ['ذ م م', 'llc'], ['ذمم', 'llc']] as const) s = s.replace(word(a), b);
  s = s.trim();
  return s || null;
}
export const LEGAL_FORMS = new Set(['llc', 'fze', 'fzco', 'fzllc', 'fz', 'est', 'co', 'ltd', 'plc', 'llp', 'inc', 'pjsc', 'psc', 'shjsc', 'شذمم', 'and']);
/** The key without its legal form: "x trading" for both "X Trading" and "X Trading L.L.C.". A near match, never a claim. */
export const companyNameCore = (key: string | null) => (key || '').split(' ').filter((w) => !LEGAL_FORMS.has(w)).join(' ');

// supplier_api/create_company.ts reads the open listings a registration may duplicate by the TWO longest words of the name that are not a legal form, each as a case-insensitive regular expression
// on the raw name that lets the characters the key drops sit between the letters ("Mu'min" keys "mumin") and accepts the letter
// variants fn_ar_norm folds. One word alone ("trading": 3,059 listings, read by the review) cut the page at its limit for 39% of names.
const SKIP = "[.'’‘`\u064B-\u0655\u0670\u0640]*";
const VARIANTS: Record<string, string> = { 'ا': '[اأإآٱ]', 'ي': '[يىئ]', 'ه': '[هة]', 'و': '[وؤ]' };
const letterRe = (c: string) => VARIANTS[c] || (/[0-9]/.test(c) ? `[${c}${String.fromCharCode(0x0660 + Number(c))}]` : c);
/** The regular expressions (one per word, at most two) the listing look-up reads by; none when the name has no word of 3+ letters. */
// Words most listings share are read last: "general" and "trading" together still matched 234 open listings for "Al Mumin General
// Trading LLC" (production, 12 Nov 2026), where the distinctive word narrows to a handful.
const COMMON = new Set(['trading', 'general', 'contracting', 'contractors', 'building', 'materials', 'services', 'technical', 'electrical',
  'mechanical', 'equipment', 'industries', 'industrial', 'international', 'group', 'engineering', 'construction', 'supplies', 'supply',
  'solutions', 'emirates', 'dubai', 'sharjah', 'abu', 'dhabi', 'ajman', 'gulf', 'middle', 'east', 'the', 'for', 'تجارة', 'للتجارة', 'للمقاولات', 'مقاولات']);
export function listingProbes(name: string): string[] {
  const all = [...new Set((companyNameKey(name) || '').split(' ').filter((x) => !LEGAL_FORMS.has(x) && x.length >= 3))];
  const words = all.sort((x, y) => (Number(COMMON.has(x)) - Number(COMMON.has(y))) || (y.length - x.length)).slice(0, 2);
  return words.map((w) => [...w].map(letterRe).join(SKIP));
}
