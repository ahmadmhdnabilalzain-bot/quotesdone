// The Disclaimer as it read in version 1.3 (23 September 2026), kept readable after 1.4 replaced it on 19 October 2026.
// Anyone who read 1.3 can still read exactly what it said.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('disclaimer-v1.3', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="disclaimer-v1.3" locale={locale} />;
}
