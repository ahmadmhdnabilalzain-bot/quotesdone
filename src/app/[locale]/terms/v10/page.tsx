// The Customer Terms as they read in version v10 (6 October 2026), kept readable after v11
// replaced them on 19 October 2026. Customers who accepted v10 can still read exactly what they accepted.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('terms-v10', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="terms-v10" locale={locale} />;
}
