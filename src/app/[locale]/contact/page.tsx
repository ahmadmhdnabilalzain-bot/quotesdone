import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { ContactInner } from '@/components/ContactInner';
import { mkMeta } from '@/components/MarketingDoc';
export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  // mkMeta drops the breadcrumb before taking the description: this read "Home · Contact Contact
  // QuotesDone…" in both languages (WEB-03).
  return mkMeta('contact', locale);
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const params = await props.params;

  const {
    locale
  } = params;

  setRequestLocale(locale);
  return (<><SiteHeader /><ContactInner /><SiteFooter /></>);
}
