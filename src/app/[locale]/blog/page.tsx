import { setRequestLocale } from 'next-intl/server';
import { MarketingDoc, mkMeta } from '@/components/MarketingDoc';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) { return mkMeta('blog', locale); }
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return <MarketingDoc slug="blog" locale={locale} />;
}
