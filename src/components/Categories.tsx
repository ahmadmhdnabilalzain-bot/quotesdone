import { useTranslations } from 'next-intl';
import { Reveal, Stagger, StaggerItem } from '@/components/motion/primitives';

type Item = { title: string; tags: string | string[] };

/** `tags` ships as a '·'-delimited string in messages/*.json — normalise both shapes. */
const toTags = (t: Item['tags']): string[] =>
  (Array.isArray(t) ? t : String(t ?? '').split('·')).map((x) => x.trim()).filter(Boolean);

export function Categories() {
  const t = useTranslations('cats');
  const items = t.raw('items') as Item[];
  return (
    <section id="cats" className="container-x py-beat-s md:py-beat">
      <Reveal className="border-t border-[var(--line)] pt-10">
        <h2 className="crisp max-w-[18ch] text-balance font-head text-[clamp(28px,3.4vw,44px)] font-semibold leading-[1.08] tracking-[-0.035em] text-white">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-[62ch] text-pretty text-[16.5px] leading-relaxed text-muted">
          <span className="text-teal-light">{t('eyebrow')}.</span> {t('sub')}
        </p>
      </Reveal>

      {/* An index, not a card wall. */}
      <Stagger className="mt-11 divide-y divide-[var(--line)] border-y border-[var(--line)]">
        {items.map((it, i) => (
          <StaggerItem key={it.title}>
            <div className="group grid items-baseline gap-x-8 gap-y-3 py-6 transition-colors duration-300 hover:bg-teal-light/[0.02] md:grid-cols-[minmax(0,.34fr)_minmax(0,.66fr)] md:px-4">
              <div className="flex items-baseline gap-4">
                <span className="font-mono text-[10.5px] tabular text-faint transition-colors duration-300 group-hover:text-teal-light">
                  {String(i + 1).padStart(2, '0')}
                </span>
                <h3 className="font-head text-[18.5px] font-semibold tracking-[-0.02em] text-white transition-colors duration-300 group-hover:text-teal-light">
                  {it.title}
                </h3>
              </div>
              <ul className="flex flex-wrap gap-2">
                {toTags(it.tags).map((tag) => (
                  <li
                    key={tag}
                    className="rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-3 py-1 text-[12.5px] text-muted transition-all duration-300 hover:-translate-y-0.5 hover:border-teal hover:bg-teal/[0.08] hover:text-teal-light hover:shadow-[0_8px_20px_-12px_rgba(20,184,166,.7)]"
                  >
                    {tag}
                  </li>
                ))}
              </ul>
            </div>
          </StaggerItem>
        ))}
      </Stagger>
    </section>
  );
}
