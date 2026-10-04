import mk from '@/content/marketing.json';
import { arDoc } from '@/lib/arabicDoc';
import { PageHero, ContentsRail, splitHero, anchorHeadings } from '@/components/DocFrame';
import { FaqSearch } from '@/components/FaqSearch';

// Styles: globals.css §9 (.mk-faq) for the questions and the search box; the hero and the
// category rail are the Sealed frame (DocFrame). The search box keeps its ids (#q, #nm), so the
// filter finds it wherever it is rendered.
//
// SERVER-RENDERED SINCE 22 SEP 2026 (WEB-12). This was a client component, so the 150 answers were
// shipped twice — once as HTML and once as an RSC payload to hydrate — and /ar/faq measured 2,020 ms
// of total blocking time on Lighthouse 12 mobile. The answers are native <details>; only the filter
// needs the browser, and it now lives alone in FaqSearch.
const L = {
  en: { kicker: 'FAQ · 150 answers', rail: 'Topics' },
  ar: { kicker: 'الأسئلة الشائعة · 150 إجابة', rail: 'المواضيع' },
};
export function FaqInner({ locale }: { locale: string }) {
  const t = locale === 'ar' ? L.ar : L.en;
  const entry = (mk as any).faq; const d = entry[locale] || entry.en;
  const hero = splitHero(arDoc(d.html as string, locale));
  const { html: rest, list } = anchorHeadings(hero.rest, 'h2', 'topic');
  return (
    <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
      <PageHero center kicker={t.kicker} title={<span dangerouslySetInnerHTML={{ __html: hero.title ?? d.title }} />}
        lead={hero.lead ? <span dangerouslySetInnerHTML={{ __html: hero.lead }} /> : undefined}>
        {hero.extra ? <div className="mk mk-faq [&_.search]:mb-0! [&_.search]:mt-10!" dangerouslySetInnerHTML={{ __html: hero.extra }} /> : null}
      </PageHero>
      <div className="container-x grid gap-10 pb-beat-s pt-10 lg:grid-cols-[230px_minmax(0,1fr)] lg:gap-16">
        <aside className="min-w-0"><ContentsRail title={t.rail} list={list} /></aside>
        <div className="mk mk-faq min-w-0 [&_.content]:pt-0! [&_.fwrap]:max-w-[860px]! [&_.fwrap]:px-0! [&_.sec:first-child]:mt-0! [&_.sec_h2]:scroll-mt-28" dangerouslySetInnerHTML={{ __html: rest }} />
      </div>
      <FaqSearch />
    </main>
  );
}
