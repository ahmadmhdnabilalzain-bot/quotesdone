import legal from '@/content/legal.json';
import { LEGAL_CSS } from '@/content/legalCss';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { CompanyIdentity } from '@/components/CompanyIdentity';
import { notFound } from 'next/navigation';
import { buildMeta, textFromHtml } from '@/lib/seo';
import { arDoc } from '@/lib/arabicDoc';
type Doc = { title: string; html: string };
const DOCS = legal as unknown as Record<string, { en: Doc; ar: Doc }>;
export function metaFor(slug: string, locale: string) {
  const e = DOCS[slug];
  const d = e ? ((e as any)[locale] || e.en) : null;
  if (!d) return { title: 'QuotesDone' };
  // strip the repeated document title, then take the opening prose
  const body = textFromHtml(d.html).replace(d.title, '').trim();
  return buildMeta({ locale, path: '/' + slug, title: d.title, description: body });
}
export function LegalDoc({ slug, locale }: { slug: string; locale: string }) {
  const e = DOCS[slug];
  if (!e) return notFound();
  const d = (e as any)[locale] || e.en;
  return (
    <>
      <SiteHeader />
      <style dangerouslySetInnerHTML={{ __html: LEGAL_CSS }} />
      <main id="main" className="legalx" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
        <div className="docwrap" dangerouslySetInnerHTML={{ __html: arDoc(d.html, locale) }} />
        {slug === 'privacy' && <div className="docwrap"><CompanyIdentity locale={locale} /></div>}
      </main>
      <SiteFooter />
    </>
  );
}
