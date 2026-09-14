import { setRequestLocale } from 'next-intl/server';
import { MarketingDoc, mkMeta } from '@/components/MarketingDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return mkMeta('how-we-verify', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <MarketingDoc slug="how-we-verify" locale={locale} />;
}
