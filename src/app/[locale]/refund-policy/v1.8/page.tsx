// The Refund Policy as it read in version 1.8 (24 September 2026), kept readable after 1.9 replaced it on 19 October 2026.
// Anyone who read 1.8 can still read exactly what it said.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('refund-policy-v1.8', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="refund-policy-v1.8" locale={locale} />;
}
