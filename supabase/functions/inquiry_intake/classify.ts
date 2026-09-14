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
export function detectUrgency(text: string): string { const t = ' ' + String(text || '').toLowerCase() + ' '; if (/(emergency|urgent|asap|immediately|today|right now|flooding|burst|no power|sparking|gas leak|leaking badly)/.test(t)) return 'urgent'; return 'normal'; }
export function isArabic(text: string): boolean { return /[؀-ۿ]/.test(String(text || '')); }
