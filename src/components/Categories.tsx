import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Stagger, StaggerItem } from '@/components/motion/primitives';
import { SectionHeader } from '@/components/SectionHeader';

type Item = { title: string; tags: string | string[] };

/** `tags` ships as a '·'-delimited string in messages/*.json — normalise both shapes. */
const toTags = (t: Item['tags']): string[] =>
  (Array.isArray(t) ? t : String(t ?? '').split('·')).map((x) => x.trim()).filter(Boolean);

export function Categories() {
  const t = useTranslations('cats');
  const items = t.raw('items') as Item[];
  return (
    <section id="cats" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="04" title={t('title')} sub={t('sub')} />

      <Stagger className="mt-14 grid grid-cols-2 gap-3 md:mt-16 md:grid-cols-4 md:gap-4">
        {items.map((it, i) => (
          <StaggerItem key={it.title}>
            <div className="tile neon-edge group relative flex h-full flex-col overflow-hidden rounded-[18px] border border-[var(--line2)] bg-navy-deep/50 p-5 backdrop-blur-sm hover:border-teal/40 md:p-6">
              <div className="flex items-center justify-between">
                <span className="idx font-mono text-[11px] tabular text-faint transition-colors duration-300 group-hover:text-teal-light">
                  {String(i + 1).padStart(2, '0')}
                </span>
                <span
                  className="corners h-3.5 w-3.5 opacity-40 transition-opacity duration-300 group-hover:opacity-100"
                  aria-hidden
                />
              </div>
              <h3 className="mt-8 font-head text-[16.5px] font-semibold leading-snug tracking-[-0.02em] text-white transition-colors duration-300 group-hover:text-teal-light md:text-[18px]">
                {it.title}
              </h3>
              <ul className="mt-3 flex flex-wrap gap-1.5">
                {toTags(it.tags).map((tag) => (
                  <li
                    key={tag}
                    className="rounded-full border border-[var(--line)] bg-teal-light/[0.03] px-2.5 py-0.5 text-[11.5px] text-muted transition-colors duration-300 group-hover:border-[var(--line2)]"
                  >
                    {tag}
                  </li>
                ))}
              </ul>
            </div>
          </StaggerItem>
        ))}

        {/* breadth signal — the catalog is not limited to the tiles above */}
        <StaggerItem className="col-span-2 md:col-span-4">
          <Link
            href="/me"
            className="press group flex items-center justify-center gap-3 rounded-[18px] border border-dashed border-teal/40 bg-teal/[0.05] px-6 py-6 text-center transition-colors duration-300 hover:border-teal hover:bg-teal/[0.09]"
          >
            <span className="font-head text-[17px] font-semibold tracking-[-0.02em] text-teal-light md:text-[19px]">
              {t('more')}
            </span>
            <span
              aria-hidden
              className="text-teal-light transition-transform duration-300 ease-expo group-hover:translate-x-1.5 rtl:group-hover:-translate-x-1.5"
            >
              &rarr;
            </span>
          </Link>
        </StaggerItem>
      </Stagger>
    </section>
  );
}
