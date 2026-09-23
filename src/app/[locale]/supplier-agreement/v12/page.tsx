// The Supplier Agreement as it read in version v12 (14 September 2026), kept readable after v13
// replaced it on 23 September 2026. Suppliers who accepted v12 can still read exactly what they accepted.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('supplier-agreement-v12', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="supplier-agreement-v12" locale={locale} />;
}
