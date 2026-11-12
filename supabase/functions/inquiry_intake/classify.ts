// classify — the closed list of emirates the model's reading is checked against, each emirate's utility, and the urgency
// reading of a customer's words. No model.
//
// Moved out of index.ts on 14 Sep 2026 so it can be tested. The case that forced it: the founder
// typed "I need Generators work (generators)" in the portal at 08:42 and 08:43 UTC. `generators` is a
// category_specs slug, but this map had no entry for it, so detectCat returned null, the kb router
// found only a weak fragment ("Industrial Equipment Suppliers", score 2) and asked the customer to
// choose between that and "something else". The category fell to 'general', readiness sat at 10,
// and no inquiry was ever created (inquiry_intake e94c7678 and b08d3296). A slug that exists in
// category_specs and has no words here cannot be reached by an English request under the model hold.
//
// 14 Sep 2026 (later): the trade map and its matcher moved to _shared/trade_classify.ts, so the
// create_inquiry fallback in customer_api reads trades the same way. Why the matcher changed — a
// fire alarm drawing filed as flooring because of "ground floor" — is written there.
// 23 Sep 2026 (founder_instruction 886-903): the trade map is DELETED. The trade is reasoned among the real
// category_specs rows (think(): _shared/reasoned_decisions.ts tradeOf, _shared/reasoned_trades.ts), never read off words.

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'Al Ain'];
// THE EMIRATE IS THE MODEL'S READING, CHECKED AGAINST THIS LIST (12 Nov 2026, founder rulings 1664/1666; LLM-first audit A1).
// detectEmirate searched every customer message for an emirate's letters and its answer came before the model's: "rak" in
// "Mubarak" or "brake" filed and counted a request in Ras Al Khaimah, and "moving from Dubai to Abu Dhabi" was Dubai because
// Dubai is first in this list. It is deleted. What the customer said is understood by the model (brief.emirate in its JSON;
// the prompt tells it an area in one emirate IS that emirate, as a person would place it). Code accepts that value only when
// it is one of the emirates below. Spelling variants of the SAME name are exactness, not a guess, and are normalised
// ("Ras al-Khaimah", "Dubai, UAE", "Emirate of Sharjah", "إمارة دبي", "Abu Dhabi city"); an area ("Dubai Marina", "JLT",
// "DXB"), two emirates, or "UAE" is not an emirate, and with none held the location is asked (handle.ts, "NO EMIRATE, NO SILENT DEFAULT").
// Prevented by: ./the_emirate_is_the_models_reading_never_a_word_search.test.ts
export const SEVEN_EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain'];
const EMIRATE_NAMES: Record<string, string> = {
  'dubai': 'Dubai', 'abu dhabi': 'Abu Dhabi', 'abudhabi': 'Abu Dhabi', 'sharjah': 'Sharjah', 'ajman': 'Ajman', 'ras al khaimah': 'Ras Al Khaimah',
  'ras alkhaimah': 'Ras Al Khaimah', 'rak': 'Ras Al Khaimah', 'fujairah': 'Fujairah', 'al fujairah': 'Fujairah', 'umm al quwain': 'Umm Al Quwain',
  'umm al qaiwain': 'Umm Al Quwain', 'uaq': 'Umm Al Quwain', 'al ain': 'Al Ain',
  'دبي': 'Dubai', 'أبوظبي': 'Abu Dhabi', 'ابوظبي': 'Abu Dhabi', 'أبو ظبي': 'Abu Dhabi', 'ابو ظبي': 'Abu Dhabi', 'الشارقة': 'Sharjah', 'الشارقه': 'Sharjah',
  'عجمان': 'Ajman', 'رأس الخيمة': 'Ras Al Khaimah', 'راس الخيمة': 'Ras Al Khaimah', 'رأس الخيمه': 'Ras Al Khaimah', 'راس الخيمه': 'Ras Al Khaimah',
  'الفجيرة': 'Fujairah', 'الفجيره': 'Fujairah', 'أم القيوين': 'Umm Al Quwain', 'ام القيوين': 'Umm Al Quwain', 'العين': 'Al Ain',
};
/** The emirate the model named, when the whole value is one of EMIRATES in any spelling of that one name; otherwise null. */
export function emirateOf(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = v.toLowerCase()
    .replace(/[\u064B-\u0652]/g, '')                  // harakat
    .replace(/[-_'’.]/g, ' ').replace(/\s*,\s*(u\.?a\.?e|united arab emirates|الإمارات|الامارات)\s*$/, '')
    .replace(/^(the\s+)?emirate\s+of\s+/, '').replace(/^(إمارة|امارة)\s+/, '')
    .replace(/\s+(city|emirate)$/, '').replace(/^مدينة\s+/, '')
    .replace(/\s+/g, ' ').trim();
  return EMIRATE_NAMES[t] ?? null;
}
/** The seven, in their Arabic names, in the order of SEVEN_EMIRATES (the options of the emirate question, handle.ts). */
export const SEVEN_EMIRATES_AR = ['دبي', 'أبوظبي', 'الشارقة', 'عجمان', 'رأس الخيمة', 'الفجيرة', 'أم القيوين'];
// The electricity and water utility of each emirate, for the approvals list a request shows. The
// compliance checklists in category_specs are written "DEWA / the relevant emirate authority"; measured
// 21 Sep 2026 (customer audit, finding 8) an Abu Dhabi job printed DEWA. Al Ain is served by AADC, the
// rest of Abu Dhabi by ADDC; Ajman, UAQ, RAK and Fujairah by Etihad Water & Electricity (the former FEWA).
export const UTILITY_BY_EMIRATE: Record<string, { en: string; ar: string }> = {
  'Dubai': { en: 'DEWA', ar: 'هيئة كهرباء ومياه دبي' },
  'Abu Dhabi': { en: 'ADDC', ar: 'شركة أبوظبي للتوزيع' },
  'Al Ain': { en: 'AADC', ar: 'شركة العين للتوزيع' },
  'Sharjah': { en: 'SEWA', ar: 'هيئة كهرباء ومياه الشارقة' },
  'Ajman': { en: 'Etihad WE', ar: 'الاتحاد للماء والكهرباء' },
  'Umm Al Quwain': { en: 'Etihad WE', ar: 'الاتحاد للماء والكهرباء' },
  'Ras Al Khaimah': { en: 'Etihad WE', ar: 'الاتحاد للماء والكهرباء' },
  'Fujairah': { en: 'Etihad WE', ar: 'الاتحاد للماء والكهرباء' },
};
/** "DEWA / the relevant emirate authority" → the one utility of `emirate`; unchanged when the emirate is unknown. */
export function utilityText(text: string | null, emirate: string | null, lang: 'en' | 'ar' = 'en'): string | null {
  const u = emirate ? UTILITY_BY_EMIRATE[emirate] : null;
  if (!text || !u) return text;
  const name = lang === 'ar' ? u.ar : u.en;
  return text
    .replace(/DEWA(?:\s*(?:\/|or)\s*the relevant emirate (?:authority|utility))?/g, name)
    .replace(/هيئة كهرباء ومياه دبي(?:\s*(?:\/|أو)\s*(?:السلطة|هيئة الكهرباء) المختصة في الإمارة)?/g, name);
}
export function detectUrgency(text: string): string { const t = ' ' + String(text || '').toLowerCase() + ' '; if (/(emergency|urgent|asap|immediately|today|right now|flooding|burst|no power|sparking|gas leak|leaking badly)/.test(t)) return 'urgent'; return 'normal'; }
export function isArabic(text: string): boolean { return /[؀-ۿ]/.test(String(text || '')); }
