// The Supplier Agreement as it read in version v17 (2 November 2026), kept readable after v18 replaced it on
// 15 November 2026 (v18 changed clause 12 only: a quotation is valid for the period the supplier states in it). Suppliers
// who accepted v17 can still read exactly what they accepted, and their acceptance record (version v17, SHA-256 of this
// exact text) still points here.
import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  return metaFor('supplier-agreement-v17', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  return <LegalDoc slug="supplier-agreement-v17" locale={locale} />;
}
