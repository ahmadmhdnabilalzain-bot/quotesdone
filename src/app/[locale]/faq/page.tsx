import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { FaqInner } from '@/components/FaqInner';
import mk from '@/content/marketing.json';
import { buildMeta, textFromHtml } from '@/lib/seo';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) {
  const e = (mk as any).faq; const d = e[locale] || e.en;
  return buildMeta({ locale, path: '/faq', title: d.title,
    description: textFromHtml(d.html).replace(d.title, '').trim() });
}
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return (<><SiteHeader /><FaqInner /><SiteFooter /></>);
}
