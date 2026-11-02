// The Supplier Agreement as it read in version v16 (19 October 2026), kept readable after v17 replaced it on
// 2 November 2026 (v17 changed the contact line only). Suppliers who accepted v16 can still read exactly what
// they accepted, and their acceptance record (version v16, SHA-256 of this exact text) still points here.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('supplier-agreement-v16', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="supplier-agreement-v16" locale={locale} />;
}
