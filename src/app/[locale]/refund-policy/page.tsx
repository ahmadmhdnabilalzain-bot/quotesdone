import { setRequestLocale } from 'next-intl/server';
import { LegalDoc, metaFor } from '@/components/LegalDoc';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) { return metaFor('refund-policy', locale); }
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return <LegalDoc slug="refund-policy" locale={locale} />;
}
