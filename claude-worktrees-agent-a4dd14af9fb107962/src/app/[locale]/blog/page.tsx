import { setRequestLocale } from 'next-intl/server';
import { mkMeta } from '@/components/MarketingDoc';
import { BlogIndex } from '@/components/BlogIndex';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  return mkMeta('blog', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  setRequestLocale(locale);
  return <BlogIndex locale={locale} />;
}
