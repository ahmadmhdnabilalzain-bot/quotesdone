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

/** next-intl's middleware reads this on an unprefixed path (/me, /portal) and serves the matching
 *  locale, so the [locale] layout paints <html dir> correctly from the first frame. */
export const LOCALE_COOKIE = 'NEXT_LOCALE';

/** The same page in the other language: '/me' <-> '/ar/me', '/' <-> '/ar'. */
export function localisedPath(pathname: string | null | undefined, lang: Lang): string {
  const bare = String(pathname || '/').replace(/^\/ar(?=\/|$)/, '') || '/';
  return lang === 'ar' ? '/ar' + (bare === '/' ? '' : bare) : bare;
}

type Win = { document: { cookie: string }; location: { pathname: string; search: string; hash: string }; history: { state: unknown; replaceState: (s: unknown, t: string, u: string) => void } };

/** ADOPT THE ACCOUNT'S REGISTERED LANGUAGE (review of #651, 14 Sep 2026). Called at sign-in (login_otp
 *  returns the account's locale) and whenever the registered value arrives or changes. It remembers the
 *  language in the cookie the middleware reads, so the next visit to /me or /portal is SERVED in it and
 *  paints in the right direction before any fetch (an Arabic-registered customer on /me used to paint
 *  ltr, then flip); it moves the URL to the matching locale without a reload; and it hands the language
 *  to the portal's state, whose effect calls applyDocumentLocale, still the only writer of <html>. A
 *  cookie that disagrees with the registered value is overwritten here, every time the value arrives. */
export function adoptLocale(lang: unknown, setLang: (l: Lang) => void, win: Win | undefined = (globalThis as { window?: Win }).window) {
  if (lang !== 'ar' && lang !== 'en') return;
  if (win) {
    try { win.document.cookie = `${LOCALE_COOKIE}=${lang};path=/;max-age=31536000;samesite=lax`; }
    catch (e) { console.error('adoptLocale: the language cookie could not be written; the next visit may paint in the other direction first', e); }
    try {
      const want = localisedPath(win.location.pathname, lang);
      if (want !== win.location.pathname) win.history.replaceState(win.history.state, '', want + win.location.search + win.location.hash);
    } catch (e) { console.error('adoptLocale: the URL could not be moved to the ' + lang + ' locale', e); }
  }
  setLang(lang);
}

/** The only writer of <html lang> and <html dir>: a screen reader, hyphenation and every element
 *  without a dir of its own read the root. */
export function applyDocumentLocale(lang: Lang, doc: { documentElement: { lang: string; dir: string } } | undefined = (globalThis as { document?: Document }).document) {
  if (!doc) return;
  doc.documentElement.lang = lang === 'ar' ? 'ar' : 'en';
  doc.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
}
