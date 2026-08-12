import type { Metadata } from 'next';
import { NextIntlClientProvider } from 'next-intl';
import { getMessages, setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';
import localFont from 'next/font/local';
import { routing } from '@/i18n/routing';
import { CookieConsent } from '@/components/CookieConsent';
import { ChatWidget } from '@/components/ChatWidget';
import { NodeField } from '@/components/NodeField';
import '../globals.css';

// SELF-HOSTED, BECAUSE `next/font/google` FETCHES AT BUILD TIME (12 Aug 2026).
//
// These four were `Plus_Jakarta_Sans/Space_Grotesk/JetBrains_Mono/Tajawal` from 'next/font/google',
// and Next fetches every one of them from Google during `next build`. A single failed fetch emits a
// CSS module referencing font files that do not exist and the build dies. Vercel, 11 Aug 2026:
// 21:01 UTC failed on `space_grotesk`, 21:16 UTC failed on `plus_jakarta_sans` — different fonts,
// unchanged src/ tree. Four network calls per build is the flake; no individual font is at fault,
// which is why "redeploy and it passes" was the only known remedy.
//
// The files are in public/fonts, fetched once by scripts/fetch_fonts.mjs from Google's own CSS at
// the same unicode ranges the old `subsets:` options asked for — nothing re-encoded, nothing
// re-subsetted. Re-run that script only to take a font version bump; it is deliberately NOT part of
// the build, because a build that fetches is the defect.
//
// The three Latin families are VARIABLE fonts, so one file each covers the whole weight range that
// used to need four separate downloads. `weight` is a range for exactly that reason.
const body = localFont({
  src: '../../../public/fonts/plus-jakarta-sans-latin.woff2',
  weight: '400 800', display: 'swap', variable: '--font-body-latin',
});
const head = localFont({
  src: '../../../public/fonts/space-grotesk-latin.woff2',
  weight: '300 700', display: 'swap', variable: '--font-head-latin',
});
const mono = localFont({
  src: '../../../public/fonts/jetbrains-mono-latin.woff2',
  weight: '100 800', display: 'swap', variable: '--font-mono-latin',
});
// TAJAWAL IS TWO FAMILIES ON PURPOSE, AND THE SECOND ONE IS NOT OPTIONAL.
//
// Tajawal has no variable cut, and Google serves its Arabic and Latin coverage as SEPARATE files
// under different unicode-ranges. `next/font/local` has no unicode-range option, so two @font-face
// rules with the same family and weight would leave the browser using whichever came last and the
// other half of the alphabet would render in a fallback face.
//
// Declaring them as two families and listing both in the CSS font stack is the native answer: the
// browser already falls through per GLYPH when the first family does not contain one. That matters
// here specifically because of the note below — the Arabic locale renders its mono content in
// Tajawal so that AED figures and region codes have digits, and digits live in the LATIN file.
// WRITTEN OUT LONGHAND, AND IT HAS TO BE. This was a `tajawalSrc(range)` helper mapping over a
// weights array, which is tidier and does not work: next/font/local is a WEBPACK/TURBOPACK LOADER
// that statically parses this call site at build time, so `src` must be a literal. It cannot call a
// function. The build still exited 0 — it emitted three woff2 files instead of eleven, logged
// "font_options_from_query_map failed" with `arguments:[{display,variable}]` and no src, and both
// Arabic families silently vanished. A green build that dropped half the fonts is the same shape of
// defect as the one this whole change is fixing, so: eight literal entries, no cleverness.
const tajawal = localFont({
  src: [
    { path: '../../../public/fonts/tajawal-400-arabic.woff2', weight: '400', style: 'normal' },
    { path: '../../../public/fonts/tajawal-500-arabic.woff2', weight: '500', style: 'normal' },
    { path: '../../../public/fonts/tajawal-700-arabic.woff2', weight: '700', style: 'normal' },
    { path: '../../../public/fonts/tajawal-800-arabic.woff2', weight: '800', style: 'normal' },
  ],
  // adjustFontFallback:false ON THE ARABIC FAMILY ONLY, AND IT IS LOAD-BEARING.
  //
  // next/font emits a metrics-adjusted `"<name> Fallback"` family beside every font, so `--font-ar`
  // expands to `tajawal, "tajawal Fallback"` and the full stack became
  //   tajawal, "tajawal Fallback", tajawalLatin, "tajawalLatin Fallback"
  // "tajawal Fallback" is a size-adjusted system face and it covers EVERY character, so the browser
  // matched Latin digits against it and never fell through to tajawalLatin. MEASURED in the dev
  // server on /ar: with a Latin string forced through var(--font-body), all four tajawalLatin faces
  // stayed `unloaded` and document.fonts.check('700 16px tajawalLatin','AED 12,400') returned false.
  // A fallback family between two real families defeats the per-glyph fall-through the pair exists
  // for. The LAST family in the stack (tajawalLatin) keeps its adjusted fallback, so there is still
  // a metrics-matched face if neither file loads.
  display: 'swap', variable: '--font-ar', adjustFontFallback: false,
});
const tajawalLatin = localFont({
  src: [
    { path: '../../../public/fonts/tajawal-400-latin.woff2', weight: '400', style: 'normal' },
    { path: '../../../public/fonts/tajawal-500-latin.woff2', weight: '500', style: 'normal' },
    { path: '../../../public/fonts/tajawal-700-latin.woff2', weight: '700', style: 'normal' },
    { path: '../../../public/fonts/tajawal-800-latin.woff2', weight: '800', style: 'normal' },
  ],
  display: 'swap', variable: '--font-ar-latin',
});

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

export const viewport = {
  themeColor: '#0C2330',
};

export default async function LocaleLayout(props: { children: React.ReactNode; params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  const {
    children
  } = props;

  if (!routing.locales.includes(locale as 'en' | 'ar')) notFound();
  setRequestLocale(locale);
  const messages = await getMessages();
  const dir = locale === 'ar' ? 'rtl' : 'ltr';
  const fontVars = locale === 'ar'
    ? `${tajawal.variable} ${tajawalLatin.variable} ${mono.variable}`
    : `${body.variable} ${head.variable} ${mono.variable}`;
  // Arabic first, Latin second: the browser falls through per glyph, so Arabic text takes the
  // Arabic file and the digits in "AED 12,400" take the Latin one. See the Tajawal note above.
  const arVar = 'var(--font-ar), var(--font-ar-latin)';
  const headVar = locale === 'ar' ? arVar : 'var(--font-head-latin)';
  const bodyVar = locale === 'ar' ? arVar : 'var(--font-body-latin)';
  // JetBrains Mono is Latin-only, so Arabic in any mono class renders as tofu.
  // Tajawal covers Latin + tabular figures, so data (AED, region codes) is safe.
  const monoVar = locale === 'ar' ? arVar : 'var(--font-mono-latin)';

  return (
    <html lang={locale} dir={dir} className={fontVars}
          style={{ ['--font-head' as string]: headVar, ['--font-body' as string]: bodyVar,
                   ['--font-mono' as string]: monoVar } as React.CSSProperties}>
      <body className="font-sans">
        <div className="aurora" aria-hidden />
        <NodeField />
        <NextIntlClientProvider messages={messages}>{children}<CookieConsent /><ChatWidget /></NextIntlClientProvider>
      </body>
    </html>
  );
}
