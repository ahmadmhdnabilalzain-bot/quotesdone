import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SectionHeader } from '@/components/SectionHeader';
import { TradeCount } from '@/components/Counters';
import { GetQuotesFor } from '@/components/GetQuotesFor';
import s from '@/components/home/sealed.module.css';

// ONE TAXONOMY. Each row carries the service slug it opens, the intake category "Get quotes for
// this" pre-fills, and the trade code whose licence-verified supplier count shows only when it is
// real (> 0). Set as an index of trades — a typographic list, not a grid of icon cards.
type Item = { title: string; tags: string | string[]; slug: string; category: string; trade: string };

const toTags = (t: Item['tags']): string[] =>
  (Array.isArray(t) ? t : String(t ?? '').split('·')).map((x) => x.trim()).filter(Boolean);

export function Categories() {
  const t = useTranslations('cats');
  const items = t.raw('items') as Item[];
  return (
    <section id="cats" className="container-x scroll-mt-20 py-beat-s md:py-beat">
      <SectionHeader
        eyebrow={t('eyebrow')}
        index="06"
        title={t('title')}
        sub={t('sub')}
        aside={
          <Link href="/services#all-trades" className="text-[14.5px] font-semibold text-teal-light underline-offset-4 hover:underline">
            {t('allTrades')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
          </Link>
        }
      />
      {/* These eight are GUIDES for common jobs, never the scope (founder, 14 Sep 2026): the full list
          of trades lives on /services#all-trades and the heading above says every trade is covered. */}
      <p className="mt-12 font-mono text-label uppercase tracking-caps text-faint">{t('guides')}</p>
      <ul className={`reveal mt-4 grid border-t border-[var(--line2)] md:grid-cols-2 md:gap-x-10`}>
        {items.map((it, i) => (
          <li key={it.slug} className="group flex items-center gap-5 border-b border-[var(--line)] py-5">
            <span className="w-6 shrink-0 font-mono text-[12px] tabular text-faint transition-colors duration-300 group-hover:text-teal-light">
              {String(i + 1).padStart(2, '0')}
            </span>
            <div className="min-w-0 flex-1">
              <Link href={`/services/${it.slug}`} className="font-head text-[clamp(17px,1.7vw,20px)] font-semibold tracking-[-0.02em] text-white transition-colors duration-300 hover:text-teal-light rtl:tracking-normal">
                {it.title}
              </Link>
              <p className="mt-1 text-[13px] text-faint">{toTags(it.tags).join(' · ')}</p>
              <TradeCount trade={it.trade} template={t('suppliersN')} />
            </div>
            <div className="hidden shrink-0 sm:block">
              <GetQuotesFor category={it.category} label={t('getQuotes')} draft={t('draft', { trade: it.title })} />
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
