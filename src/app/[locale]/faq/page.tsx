import { setRequestLocale } from 'next-intl/server';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { FaqInner } from '@/components/FaqInner';
import mk from '@/content/marketing.json';
import { buildMeta, textFromHtml, ldHtml, faqLd, faqPairs } from '@/lib/seo';

const doc = (locale: string) => { const e = (mk as any).faq; return e[locale] || e.en; };

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const d = doc(locale);
  return buildMeta({ locale, path: '/faq', title: d.title,
    description: textFromHtml(d.html).replace(d.title, '').trim() });
}
export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  // FAQPage from the same html FaqInner renders, so the markup can never disagree with the page.
  return (<>
    <script type="application/ld+json" dangerouslySetInnerHTML={ldHtml(faqLd(faqPairs(doc(locale).html), locale))} />
    <SiteHeader /><FaqInner locale={locale} /><SiteFooter />
  </>);
}
