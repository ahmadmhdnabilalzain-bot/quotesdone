import { setRequestLocale } from 'next-intl/server';
import { MarketingDoc, mkMeta } from '@/components/MarketingDoc';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) { return mkMeta('services', locale); }
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return <MarketingDoc slug="services" locale={locale} />;
}
