import { setRequestLocale } from 'next-intl/server';
import { ServiceDoc, svcParams, svcMeta } from '@/components/ServiceDoc';
export function generateStaticParams() { return svcParams().map((slug) => ({ slug })); }
export async function generateMetadata(props: { params: Promise<{ locale: string; slug: string }> }) {
  const params = await props.params;

  const {
    locale,
    slug
  } = params;

  return svcMeta(slug, locale);
}
export default async function Page(props: { params: Promise<{ locale: string; slug: string }> }) {
  const params = await props.params;

  const {
    locale,
    slug
  } = params;

  setRequestLocale(locale);
  return <ServiceDoc slug={slug} locale={locale} />;
}
