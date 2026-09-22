// The two pure rules public_site applies to what it serves, kept apart from index.ts (which starts a
// server on import) so rules.test.ts can run them.

// ONE COMPLIANCE LINE IN THE READER'S LANGUAGE.
// Measured 22 Sep 2026 (production walk): /ar/services/solar and 14 other Arabic service pages showed
// "the relevant emirate authority", "DEWA", "Dubai Municipality" in English. category_specs already
// carries authority_ar on every item of the 22 public trades
// (every_service_trade_names_its_documents_in_english_and_arabic.sql); this function read item_ar and
// never authority_ar. An item or authority with no Arabic falls back to the English, as before.
export function documentLine(x: any, lang: 'en' | 'ar'): { item: string; authority: string | null } {
  const ar = lang === 'ar';
  const item = String((ar && x?.item_ar) || x?.item || (typeof x === 'string' ? x : '') || '').slice(0, 160);
  const auth = (ar && x?.authority_ar) || x?.authority;
  return { item, authority: auth ? String(auth).slice(0, 80) : null };
}

// THE SERVICE PAGES' PRICE QUESTION IS A PAGE LOAD, NOT A VISITOR'S QUESTION.
// Measured 22 Sep 2026: a crawl at 6 concurrent pages got 429 from public_site on 116 of 472 loads,
// every one a /services/* page. Each service page asks price_guidance for its own trade on mount
// (src/components/PriceGuide.tsx SERVICE_TOPIC), and Googlebot renders that script too, so one crawler
// IP spent the 60/hour visitor budget meant for the free-text box. These fixed topics are published
// guide bands, the same answer for everyone, and are served before the limiter like trade_needs.
// Free text (`question`, or any topic not on this list) stays behind it.
// Must equal the non-null values of SERVICE_TOPIC — rules.test.ts reads both files and fails if not.
export const PAGE_TOPICS: ReadonlySet<string> = new Set([
  'false ceiling', 'pest control', 'movers', 'flooring', 'interior design', 'HVAC maintenance',
  'swimming pools', 'solar', 'cctv security', 'joinery kitchens', 'AC duct cleaning', 'waterproofing',
  'electrical work', 'plumbing', 'smart home automation', 'aluminium glass', 'curtains blinds',
  'tiling marble', 'painting', 'signage', 'landscaping', 'cleaning services',
]);
export const isPageTopic = (b: any): boolean =>
  !String(b?.question || '').trim() && PAGE_TOPICS.has(String(b?.topic || ''));
