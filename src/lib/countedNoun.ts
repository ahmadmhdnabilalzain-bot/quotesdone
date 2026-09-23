// A NUMBER AND ITS NOUN, AGREEING, IN EITHER LANGUAGE.
//
// Arabic takes a different form of the noun at 1, at 2 (the dual), at 3-10 (the plural) and from 11
// (the singular accusative) — and the dual itself changes when the noun is not the subject
// ('بندان' → 'بندين'). String audit 22 Sep 2026 (customer_support, CP-I18N-05): 22 templates in the
// customer portal printed ONE fixed form for every number — '2 بندًا', '3 صفحة', '1 عروض' — while
// arDays() (src/lib/durationLabel.ts) and the old supplierCount() had been
// doing it correctly for their own two nouns all along. supplierCount is folded in here (review of
// #853), so a new counted noun is a line in AR_NOUN and never a second implementation.
//
// English is here too, because the same call sites were writing 'page(s)' and 'area(s)'.
// Tested in src/lib/countedNoun.test.mjs.

export type ArForms = { one: string; two: string; twoOblique: string; few: string; many: string };
export type Noun = 'request' | 'quote' | 'line' | 'page' | 'area' | 'project' | 'hour' | 'category' | 'supplier'
  | 'day' | 'inquiry' | 'matchedInquiry' | 'drawingPage' | 'openPoint' | 'product' | 'unreadMessage' | 'document';

/** twoOblique is the dual after a verb it is the object of, or after a preposition ('قرأتُ بندين'). */
export const AR_NOUN: Record<Noun, ArForms> = {
  request: { one: 'طلب واحد', two: 'طلبان', twoOblique: 'طلبين', few: 'طلبات', many: 'طلبًا' },
  quote: { one: 'عرض واحد', two: 'عرضان', twoOblique: 'عرضين', few: 'عروض', many: 'عرضًا' },
  line: { one: 'بند واحد', two: 'بندان', twoOblique: 'بندين', few: 'بنود', many: 'بندًا' },
  page: { one: 'صفحة واحدة', two: 'صفحتان', twoOblique: 'صفحتين', few: 'صفحات', many: 'صفحة' },
  area: { one: 'منطقة واحدة', two: 'منطقتان', twoOblique: 'منطقتين', few: 'مناطق', many: 'منطقة' },
  project: { one: 'مشروع واحد', two: 'مشروعان', twoOblique: 'مشروعين', few: 'مشاريع', many: 'مشروعًا' },
  hour: { one: 'ساعة واحدة', two: 'ساعتان', twoOblique: 'ساعتين', few: 'ساعات', many: 'ساعة' },
  category: { one: 'فئة واحدة', two: 'فئتان', twoOblique: 'فئتين', few: 'فئات', many: 'فئة' },
  supplier: { one: 'مورّد واحد', two: 'مورّدان', twoOblique: 'مورّدين', few: 'مورّدين', many: 'مورّدًا' },
  // ── Added 23 Sep 2026, review of #858. That branch had declared these same eight nouns as private
  // four-form arrays in six files, next to a SECOND arCount in src/lib/durationLabel.ts whose only
  // difference was that it had no k === 0 branch — so an empty list read '0 استفسارات' where Arabic
  // takes the accusative singular, exactly as at 11+. This file already said so on the line below
  // arCount's zero branch. One rule, one table: the arrays are lines here now.
  day: { one: 'يوم واحد', two: 'يومان', twoOblique: 'يومين', few: 'أيام', many: 'يومًا' },
  inquiry: { one: 'استفسار واحد', two: 'استفساران', twoOblique: 'استفسارين', few: 'استفسارات', many: 'استفسارًا' },
  // The adjective follows the noun it describes, so it carries the same number and case.
  matchedInquiry: { one: 'استفسار واحد مطابق لكم', two: 'استفساران مطابقان لكم', twoOblique: 'استفسارين مطابقين لكم', few: 'استفسارات مطابقة لكم', many: 'استفسارًا مطابقًا لكم' },
  // A construct phrase: the dual drops its نون (صفحتا مخطط) and the 11+ singular takes no tanwin.
  drawingPage: { one: 'صفحة مخطط واحدة', two: 'صفحتا مخطط', twoOblique: 'صفحتي مخطط', few: 'صفحات مخطط', many: 'صفحة مخطط' },
  openPoint: { one: 'نقطة واحدة مفتوحة', two: 'نقطتان مفتوحتان', twoOblique: 'نقطتين مفتوحتين', few: 'نقاط مفتوحة', many: 'نقطة مفتوحة' },
  product: { one: 'منتج واحد', two: 'منتجان', twoOblique: 'منتجين', few: 'منتجات', many: 'منتجًا' },
  unreadMessage: { one: 'رسالة واحدة غير مقروءة', two: 'رسالتان غير مقروءتين', twoOblique: 'رسالتين غير مقروءتين', few: 'رسائل غير مقروءة', many: 'رسالة غير مقروءة' },
  document: { one: 'مستند واحد', two: 'مستندان', twoOblique: 'مستندين', few: 'مستندات', many: 'مستندًا' },
};

const EN_NOUN: Record<Noun, [string, string]> = {
  request: ['request', 'requests'],
  quote: ['quote', 'quotes'],
  line: ['line item', 'line items'],
  page: ['page', 'pages'],
  area: ['area', 'areas'],
  project: ['project', 'projects'],
  hour: ['hour', 'hours'],
  category: ['category', 'categories'],
  supplier: ['supplier', 'suppliers'],
  day: ['day', 'days'],
  inquiry: ['inquiry', 'inquiries'],
  matchedInquiry: ['inquiry matched to you', 'inquiries matched to you'],
  drawingPage: ['drawing page', 'drawing pages'],
  openPoint: ['open point', 'open points'],
  product: ['product', 'products'],
  unreadMessage: ['unread message', 'unread messages'],
  document: ['document', 'documents'],
};

/** arCount(2, AR_NOUN.line) = 'بندان'; with {oblique:true} = 'بندين'; arCount(3, …) = '3 بنود'. */
export function arCount(n: number | string | null | undefined, forms: ArForms, opts?: { oblique?: boolean }): string {
  const k = Math.abs(Math.trunc(Number(n) || 0));
  if (k === 0) return `0 ${forms.many}`; // '0 بندًا', as at 11+ — never the 3-10 plural
  if (k === 1) return forms.one;
  if (k === 2) return opts && opts.oblique ? forms.twoOblique : forms.two;
  return `${k} ${k <= 10 ? forms.few : forms.many}`;
}

/** '3 quotes' / 'عرضان' — the number and its noun, agreeing, in the reader's language. */
export function countPhrase(lang: string, n: number | string | null | undefined, noun: Noun, opts?: { oblique?: boolean }): string {
  const k = Math.abs(Math.trunc(Number(n) || 0));
  if (lang === 'ar') return arCount(k, AR_NOUN[noun], opts);
  return `${k} ${EN_NOUN[noun][k === 1 ? 0 : 1]}`;
}
