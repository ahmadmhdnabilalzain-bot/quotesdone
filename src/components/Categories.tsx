import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Stagger, StaggerItem } from '@/components/motion/reveal';
import { SectionHeader } from '@/components/SectionHeader';
import { TradeCount } from '@/components/Counters';
import { GetQuotesFor } from '@/components/GetQuotesFor';

// ONE TAXONOMY. The tiles were plain divs with names that matched none of the 24 service pages, and
// the only link went to the sign-in gate (website audit, IA section). Each tile now carries the
// service slug it opens, the intake category "Get quotes for this" pre-fills, and the trade code
// whose licence-verified supplier count shows only when it is real (> 0).
type Item = { title: string; tags: string | string[]; slug: string; category: string; trade: string };

const toTags = (t: Item['tags']): string[] =>
  (Array.isArray(t) ? t : String(t ?? '').split('·')).map((x) => x.trim()).filter(Boolean);

export function Categories() {
  const t = useTranslations('cats');
  const items = t.raw('items') as Item[];
  return (
    <section id="cats" className="container-x scroll-mt-20 py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="06" title={t('title')} sub={t('sub')} />

      <Stagger className="mt-14 grid grid-cols-1 gap-3 sm:grid-cols-2 md:mt-16 lg:grid-cols-4 lg:gap-4">
        {items.map((it, i) => (
          <StaggerItem key={it.slug}>
            <div className="tile neon-edge group relative flex h-full flex-col overflow-hidden rounded-[18px] border border-[var(--line2)] bg-navy-deep/50 backdrop-blur-sm hover:border-teal/40">
              <Link href={`/services/${it.slug}`} className="flex flex-1 flex-col p-5 md:p-6">
                <div className="flex items-center justify-between">
                  <span className="font-mono text-[12px] tabular text-faint transition-colors duration-300 group-hover:text-teal-light">
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <span className="corners h-3.5 w-3.5 opacity-40 transition-opacity duration-300 group-hover:opacity-100" aria-hidden />
                </div>
                <h3 className="mt-7 font-head text-[17px] font-semibold leading-snug tracking-[-0.02em] text-white transition-colors duration-300 group-hover:text-teal-light md:text-[18px]">
                  {it.title}
                </h3>
                <ul className="mt-3 flex flex-wrap gap-1.5">
                  {toTags(it.tags).map((tag) => (
                    <li key={tag} className="rounded-full border border-[var(--line)] bg-teal-light/[0.03] px-2.5 py-0.5 text-[12px] text-muted">{tag}</li>
                  ))}
                </ul>
                <TradeCount trade={it.trade} template={t('suppliersN')} />
              </Link>
              <div className="border-t border-[var(--line)] px-5 py-3 md:px-6">
                <GetQuotesFor category={it.category} label={t('getQuotes')} draft={t('draft', { trade: it.title })} />
              </div>
            </div>
          </StaggerItem>
        ))}

        <StaggerItem className="sm:col-span-2 lg:col-span-4">
          <Link
            href="/services"
            className="press group flex items-center justify-center gap-3 rounded-[18px] border border-dashed border-teal/40 bg-teal/[0.05] px-6 py-6 text-center transition-colors duration-300 hover:border-teal hover:bg-teal/[0.09]"
          >
            <span className="font-head text-[17px] font-semibold tracking-[-0.02em] text-teal-light md:text-[19px]">{t('more')}</span>
            <span aria-hidden className="text-teal-light transition-transform duration-300 ease-expo group-hover:translate-x-1.5 rtl:rotate-180 rtl:group-hover:-translate-x-1.5">&rarr;</span>
          </Link>
        </StaggerItem>
      </Stagger>
    </section>
  );
}
