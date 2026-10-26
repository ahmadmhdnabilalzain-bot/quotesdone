import { setRequestLocale } from 'next-intl/server';
import { MarketingDoc, mkMeta } from '@/components/MarketingDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  return mkMeta('about', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  setRequestLocale(locale);
  return <MarketingDoc slug="about" locale={locale} />;
}
