import type { Metadata } from 'next';
import { NextIntlClientProvider } from 'next-intl';
import { getMessages, setRequestLocale } from 'next-intl/server';
import { notFound } from 'next/navigation';
import { Space_Grotesk, Plus_Jakarta_Sans, JetBrains_Mono, Tajawal } from 'next/font/google';
import { routing } from '@/i18n/routing';
import { CookieConsent } from '@/components/CookieConsent';
import { ChatWidget } from '@/components/ChatWidget';
import { NodeField } from '@/components/NodeField';
import '../globals.css';

const body = Plus_Jakarta_Sans({ subsets: ['latin'], weight: ['400','500','600','700'], variable: '--font-body-latin' });
const head = Space_Grotesk({ subsets: ['latin'], weight: ['500','600','700'], variable: '--font-head-latin' });
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['400','500','600'], variable: '--font-mono-latin' });
const tajawal = Tajawal({ subsets: ['arabic'], weight: ['400','500','700','800'], variable: '--font-ar' });

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

// Per-page generateMetadata supplies title/description/canonical/hreflang.
// Only the template lives here so pages never inherit an English title in Arabic.
export const metadata: Metadata = {
  title: { default: 'QuotesDone', template: '%s' }
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
    ? `${tajawal.variable} ${mono.variable}`
    : `${body.variable} ${head.variable} ${mono.variable}`;
  const headVar = locale === 'ar' ? 'var(--font-ar)' : 'var(--font-head-latin)';
  const bodyVar = locale === 'ar' ? 'var(--font-ar)' : 'var(--font-body-latin)';

  return (
    <html lang={locale} dir={dir} className={fontVars}
          style={{ ['--font-head' as string]: headVar, ['--font-body' as string]: bodyVar,
                   ['--font-mono' as string]: 'var(--font-mono-latin)' } as React.CSSProperties}>
      <body className="font-sans">
        <NodeField />
        <NextIntlClientProvider messages={messages}>{children}<CookieConsent /><ChatWidget /></NextIntlClientProvider>
      </body>
    </html>
  );
}
