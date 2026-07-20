import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { FaqInner } from '@/components/FaqInner';
import mk from '@/content/marketing.json';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) { const e = (mk as any).faq; return { title: (e[locale] || e.en).title }; }
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return (<><SiteHeader /><FaqInner /><SiteFooter /></>);
}
