import { setRequestLocale } from 'next-intl/server';
import { ServiceDoc, svcParams, svcMeta } from '@/components/ServiceDoc';
export function generateStaticParams() { return svcParams().map((slug) => ({ slug })); }
export function generateMetadata({ params: { locale, slug } }: { params: { locale: string; slug: string } }) { return svcMeta(slug, locale); }
export default function Page({ params: { locale, slug } }: { params: { locale: string; slug: string } }) {
  setRequestLocale(locale);
  return <ServiceDoc slug={slug} locale={locale} />;
}
