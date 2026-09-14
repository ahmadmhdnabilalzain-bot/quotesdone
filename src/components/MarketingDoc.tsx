import mk from '@/content/marketing.json';
import css from '@/content/marketingCss.json';
import { SERVICES_CSS } from '@/content/servicesCss';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { CompanyIdentity } from '@/components/CompanyIdentity';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';
import { arDoc } from '@/lib/arabicDoc';
type Doc = { title: string; html: string };
const M = mk as unknown as Record<string, { en: Doc; ar: Doc }>;
const CSS = css as unknown as Record<string, string>;
export function mkMeta(slug: string, locale: string) {
  const e = M[slug];
  const d = e ? ((e as any)[locale] || e.en) : null;
  if (!d) return { title: 'QuotesDone' };
  const body = textFromHtml(d.html).replace(d.title, '').trim();
  return buildMeta({ locale, path: '/' + slug, title: d.title, description: body });
}
export function MarketingDoc({ slug, locale }: { slug: string; locale: string }) {
  const e = M[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  return (
    <>
      <SiteHeader />
      <style dangerouslySetInnerHTML={{ __html: CSS[slug] || SERVICES_CSS }} />
      <main id="main" className="mk" dir={locale === 'ar' ? 'rtl' : 'ltr'} dangerouslySetInnerHTML={{ __html: arDoc(d.html, locale) }} />
      {slug === 'about' && <div className="container-x"><CompanyIdentity locale={locale} /></div>}
      <SiteFooter />
    </>
  );
}
