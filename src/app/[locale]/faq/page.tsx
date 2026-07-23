import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { FaqInner } from '@/components/FaqInner';
import mk from '@/content/marketing.json';
import { buildMeta, textFromHtml } from '@/lib/seo';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  const e = (mk as any).faq;const d = e[locale] || e.en;
  return buildMeta({ locale, path: '/faq', title: d.title,
    description: textFromHtml(d.html).replace(d.title, '').trim() });
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  setRequestLocale(locale);
  return (<><SiteHeader /><FaqInner /><SiteFooter /></>);
}
