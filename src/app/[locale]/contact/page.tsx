import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { ContactInner } from '@/components/ContactInner';
import mk from '@/content/marketing.json';
export function generateMetadata({ params: { locale } }: { params: { locale: string } }) { const e = (mk as any).contact; return { title: (e[locale] || e.en).title }; }
export default function Page({ params: { locale } }: { params: { locale: string } }) {
  setRequestLocale(locale);
  return (<><SiteHeader /><ContactInner /><SiteFooter /></>);
}
