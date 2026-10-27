// The Supplier Agreement as it read in version v15 (6 October 2026), kept readable after v16
// replaced it on 19 October 2026. Suppliers who accepted v15 can still read exactly what they accepted.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('supplier-agreement-v15', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="supplier-agreement-v15" locale={locale} />;
}
