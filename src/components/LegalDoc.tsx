import legal from '@/content/legal.json';
import { LEGAL_CSS } from '@/content/legalCss';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { notFound } from 'next/navigation';
type Doc = { title: string; html: string };
const DOCS = legal as unknown as Record<string, { en: Doc; ar: Doc }>;
export function metaFor(slug: string, locale: string) { const e = DOCS[slug]; const d = e ? ((e as any)[locale] || e.en) : null; return { title: d ? d.title : 'QuotesDone' }; }
export function LegalDoc({ slug, locale }: { slug: string; locale: string }) {
  const e = DOCS[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  return (
    <>
      <SiteHeader />
      <style dangerouslySetInnerHTML={{ __html: LEGAL_CSS }} />
      <main id="main" className="legalx" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <div className="docwrap" dangerouslySetInnerHTML={{ __html: d.html }} />
      </main>
      <SiteFooter />
    </>
  );
}
