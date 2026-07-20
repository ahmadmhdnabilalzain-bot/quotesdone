import mk from '@/content/marketing.json';
import css from '@/content/marketingCss.json';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { notFound } from 'next/navigation';
type Doc = { title: string; html: string };
const M = mk as unknown as Record<string, { en: Doc; ar: Doc }>;
const CSS = css as unknown as Record<string, string>;
export function mkMeta(slug: string, locale: string) { const e = M[slug]; const d = e ? ((e as any)[locale] || e.en) : null; return { title: d ? d.title : 'QuotesDone' }; }
export function MarketingDoc({ slug, locale }: { slug: string; locale: string }) {
  const e = M[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  return (
    <>
      <SiteHeader />
      <style dangerouslySetInnerHTML={{ __html: CSS[slug] || '' }} />
      <main id="main" className="mk" dir={locale === 'ar' ? 'rtl' : 'ltr'} dangerouslySetInnerHTML={{ __html: d.html }} />
      <SiteFooter />
    </>
  );
}
