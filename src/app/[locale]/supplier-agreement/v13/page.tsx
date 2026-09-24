// The Supplier Agreement as it read in version v13 (23 September 2026), kept readable after v14
// replaced it on 24 September 2026. Suppliers who accepted v13 can still read exactly what they accepted.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('supplier-agreement-v13', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="supplier-agreement-v13" locale={locale} />;
}
