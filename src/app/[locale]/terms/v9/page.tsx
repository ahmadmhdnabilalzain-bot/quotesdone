// The Customer Terms as they read in version v9 (23 September 2026), kept readable after v10
// replaced them on 6 October 2026. Customers who accepted v9 can still read exactly what they accepted.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('terms-v9', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="terms-v9" locale={locale} />;
}
