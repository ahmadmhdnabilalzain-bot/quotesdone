// THE DOCUMENT'S LANGUAGE AND DIRECTION, DECIDED IN ONE PLACE (14 Sep 2026, agent: sales_engineer).
//
// Measured by the e2e harness, journey a, 14 Sep 2026: the Arabic customer portal rendered with
// document dir=ltr on desktop and mobile. The [locale] layout server-renders <html dir="rtl"> on /ar,
// and then the customer portal overwrote it: its language came from localStorage and the NEXT_LOCALE
// cookie only, both empty in a fresh browser, so it decided 'en' on /ar and stamped dir=ltr. The
// supplier portal read the URL instead, and each portal wrote the root element in its own effect.
//
// Now both portals take the language BEFORE sign-in from the URL (which is what the layout rendered,
// so nothing flips), take it AFTER sign-in from the registered language (customers.locale /
// leads.locale, founder 14 Sep 2026: "if someone registered while the language was arabic then arabic
// follows through the whole workflow"), and write the root element only through applyDocumentLocale.
// Tested in documentLocale.test.mjs.
export type Lang = 'en' | 'ar';

/** The language the URL names: /ar and /ar/... are Arabic, everything else English. */
export const urlLocale = (pathname: string | null | undefined): Lang => (/^\/ar(\/|$)/.test(String(pathname || '')) ? 'ar' : 'en');

/** The only writer of <html lang> and <html dir>: a screen reader, hyphenation and every element
 *  without a dir of its own read the root. */
export function applyDocumentLocale(lang: Lang, doc: { documentElement: { lang: string; dir: string } } | undefined = (globalThis as { document?: Document }).document) {
  if (!doc) return;
  doc.documentElement.lang = lang === 'ar' ? 'ar' : 'en';
  doc.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
}
