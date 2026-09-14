'use client';
import { useEffect } from 'react';
import { useLocale } from 'next-intl';
import mk from '@/content/marketing.json';
import { arDoc } from '@/lib/arabicDoc';
import { PageHero, ContentsRail, splitHero, anchorHeadings } from '@/components/DocFrame';

// Styles: globals.css §9 (.mk-faq) for the questions and the search box; the hero and the
// category rail are the Sealed frame (DocFrame). The search box keeps its ids (#q, #nm), so the
// filter below finds it wherever it is rendered.
const L = {
  en: { kicker: 'FAQ · 150 answers', rail: 'Topics' },
  ar: { kicker: 'الأسئلة الشائعة · 150 إجابة', rail: 'المواضيع' },
};
export function FaqInner() {
  const locale = useLocale();
  const t = locale === 'ar' ? L.ar : L.en;
  const entry = (mk as any).faq; const d = entry[locale] || entry.en;
  const hero = splitHero(arDoc(d.html as string, locale));
  const { html: rest, list } = anchorHeadings(hero.rest, 'h2', 'topic');
  useEffect(() => {
    const q = document.getElementById('q') as HTMLInputElement | null;
    const nm = document.getElementById('nm') as HTMLElement | null;
    if (!q) return;
    const items = Array.from(document.querySelectorAll('details.qa')) as HTMLElement[];
    const secs = Array.from(document.querySelectorAll('.sec')) as HTMLElement[];
    const run = () => {
      const t = q.value.trim().toLowerCase();
      let any = false;
      items.forEach((el) => {
        const show = !t || (el.textContent || '').toLowerCase().includes(t);
        el.style.display = show ? '' : 'none';
        if (show) any = true;
        (el as HTMLDetailsElement).open = !!(t && show);
      });
      secs.forEach((s) => { const vis = Array.from(s.querySelectorAll('details.qa')).some((el: any) => el.style.display !== 'none'); s.style.display = vis ? '' : 'none'; });
      if (nm) nm.style.display = any ? 'none' : 'block';
    };
    q.addEventListener('input', run); run();
    return () => q.removeEventListener('input', run);
  }, [locale]);
  return (
    <main id="main" dir={locale === 'ar' ? 'rtl' : 'ltr'}>
      <PageHero center kicker={t.kicker} title={<span dangerouslySetInnerHTML={{ __html: hero.title ?? d.title }} />}
        lead={hero.lead ? <span dangerouslySetInnerHTML={{ __html: hero.lead }} /> : undefined}>
        {hero.extra ? <div className="mk mk-faq [&_.search]:!mb-0 [&_.search]:!mt-10" dangerouslySetInnerHTML={{ __html: hero.extra }} /> : null}
      </PageHero>
      <div className="container-x grid gap-10 pb-beat-s pt-10 lg:grid-cols-[230px_minmax(0,1fr)] lg:gap-16">
        <aside className="min-w-0"><ContentsRail title={t.rail} list={list} /></aside>
        <div className="mk mk-faq min-w-0 [&_.content]:!pt-0 [&_.fwrap]:!max-w-[860px] [&_.fwrap]:!px-0 [&_.sec:first-child]:!mt-0 [&_.sec_h2]:scroll-mt-28" dangerouslySetInnerHTML={{ __html: rest }} />
      </div>
    </main>
  );
}
