import type { Metadata } from 'next';
import { preload } from 'react-dom';
import { NextIntlClientProvider } from 'next-intl';
import { getMessages, setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { routing } from '@/i18n/routing';
import { CookieConsent } from '@/components/CookieConsent';
import { COOKIE_ASK } from '@/lib/cookieAsk';
import { FirstTouch } from '@/components/FirstTouch';
import { WebAnalytics } from '@/components/WebAnalytics';
import { ChatWidget } from '@/components/ChatWidget';
import { RouteProgress } from '@/components/ui/route-progress';
import { NodeField } from '@/components/NodeField';
import { OfflineBanner } from '@/components/OfflineBanner';
import { ldHtml, siteLd } from '@/lib/seo';
import '../globals.css';

// FONTS: ONE LOCALE, ONE SET OF PRELOADS (website audit 14 Sep 2026).
//
// These were four next/font/local declarations in this module. next/font emits a preload for every
// font a layout module declares, and both locales share this one layout, so EVERY page preloaded all
// 11 files — measured on the live head of `/`: 11 <link rel=preload as=font>. English pages fetched
// the 8 Tajawal files (~77 KB) they never render; /ar fetched the 3 Latin variable fonts (~90 KB).
// next/font cannot preload per request param, so the faces are now plain @font-face rules in
// globals.css (same files in public/fonts, and Tajawal becomes ONE family split by unicode-range —
// the native answer the old two-family workaround stood in for) and this layout preloads only the
// current locale's files. An @font-face that nothing uses is never downloaded.
//
// The files are still self-hosted (see scripts/fetch_fonts.mjs) — nothing is fetched at build time,
// which was the reason for leaving next/font/google on 12 Aug 2026.
//
// 14 Sep 2026, brand direction A "Sealed": Geist / Geist Mono / Readex Pro, all variable, 4 files in
// total. Only the first-screen face is preloaded (the hero headline's): English preloads Geist
// (29 KB), Arabic preloads the Readex Pro Arabic half (23 KB). Geist Mono and the Readex Latin half
// (digits) load on first use under font-display:swap.
const FONTS: Record<'en' | 'ar', string[]> = {
  en: ['geist-latin'],
  ar: ['readex-pro-arabic'],
};

const SKIP = { en: 'Skip to content', ar: 'انتقل إلى المحتوى الرئيسي' };

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

// Per-page generateMetadata supplies title/description/canonical/hreflang.
// Only the template lives here so pages never inherit an English title in Arabic.
export const metadata: Metadata = {
  title: { default: 'QuotesDone', template: '%s' },
  applicationName: 'QuotesDone',
  appleWebApp: { capable: true, title: 'QuotesDone', statusBarStyle: 'black-translucent' },
  manifest: '/manifest.webmanifest',
};

// viewport-fit=cover (launch checklist, 19 Nov 2026): lets the page draw under the notch and the home bar on
// iPhones; the fixed bottom elements of the portal shell pad themselves with env(safe-area-inset-*).
export const viewport = {
  themeColor: '#0A1720',
  viewportFit: 'cover' as const,
};

export default async function LocaleLayout(props: { children: React.ReactNode; params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const { children } = props;

  if (!routing.locales.includes(locale as 'en' | 'ar')) notFound();
  setRequestLocale(locale);
  const messages = await getMessages();
  const lang = locale === 'ar' ? 'ar' : 'en';
  for (const f of FONTS[lang]) preload(`/fonts/${f}.woff2`, { as: 'font', type: 'font/woff2', crossOrigin: 'anonymous' });

  // suppressHydrationWarning: the first-visit mark (COOKIE_ASK) sets html[data-qd-cookie] before React hydrates (review, item 4).
  return (
    <html lang={locale} dir={lang === 'ar' ? 'rtl' : 'ltr'} suppressHydrationWarning>
      <body className="font-sans">
        {/* First focusable element on every page, before the header (pages render #main). */}
        <a href="#main" className="skip-link">{SKIP[lang]}</a>
        {/* Before any content is parsed: no cookie choice stored -> html[data-qd-cookie="ask"], so the notice below is laid out in the
            first paint and nothing moves when the page has loaded (CookieConsent.tsx; 12 Nov 2026). */}
        <script dangerouslySetInnerHTML={{ __html: COOKIE_ASK }} />
        <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml(siteLd(locale))} />
        <div className="aurora" aria-hidden />
        <NodeField />
        {/* The top bar for route changes — the one loading system, see src/components/ui/busy.tsx. */}
        <RouteProgress label={lang === 'ar' ? 'جارٍ التحميل' : 'Loading'} />
        <NextIntlClientProvider messages={messages}><OfflineBanner lang={lang} /><CookieConsent />{children}<FirstTouch /><WebAnalytics /><ChatWidget /></NextIntlClientProvider>
      </body>
    </html>
  );
}
