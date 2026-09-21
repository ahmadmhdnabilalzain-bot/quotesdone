// classify — the deterministic trade, emirate and urgency reading of a customer's words. No model.
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
export { KW, detectCat, detectTrades, tradeHits, tradePhrases } from '../_shared/trade_classify.ts';

export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'Al Ain'];
export function detectEmirate(text: string): string | null { const t = String(text || '').toLowerCase(); for (const e of EMIRATES) if (t.includes(e.toLowerCase())) return e; if (t.includes('rak')) return 'Ras Al Khaimah'; return null; }
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
