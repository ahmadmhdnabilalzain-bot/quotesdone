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
        <div className="flex items-center gap-4 font-mono text-[10.5px] uppercase tracking-[0.2em] text-teal-light">
          <span className="node-dot" aria-hidden />
          <span>{t('eyebrow')}</span>
          <span className="tabular ml-auto text-faint/60">04</span>
        </div>
        <h2 className="crisp mt-6 max-w-[18ch] text-balance font-head text-[clamp(28px,3.6vw,46px)] font-semibold leading-[1.05] tracking-[-0.04em] text-white">
          {t('title')}
        </h2>
        <p className="mt-4 max-w-[62ch] text-pretty text-[16.5px] leading-relaxed text-muted">{t('sub')}</p>
      </Reveal>

      {/* A precision directory, not a card wall — corner-framed, each row selectable. */}
      <div className="relative mt-11">
        <span className="corners absolute -inset-2 hidden md:block" aria-hidden />
        <Stagger className="divide-y divide-[var(--line)] overflow-hidden rounded-[18px] border border-[var(--line)] bg-navy-deep/40">
          {items.map((it, i) => (
            <StaggerItem key={it.title}>
              <div className="group relative grid items-baseline gap-x-8 gap-y-3 py-6 pl-5 pr-4 transition-colors duration-300 hover:bg-teal-light/[0.03] md:grid-cols-[minmax(0,.34fr)_minmax(0,.66fr)] md:pl-7">
                <span className="absolute inset-y-4 left-0 w-px bg-transparent transition-all duration-300 group-hover:bg-teal group-hover:shadow-[0_0_10px_rgba(110,231,212,.7)]" />
                <div className="flex items-baseline gap-4">
                  <span className="font-mono text-[11px] tabular text-faint transition-colors duration-300 group-hover:text-teal-light">
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <h3 className="font-head text-[19px] font-semibold tracking-[-0.02em] text-white transition-colors duration-300 group-hover:text-teal-light">
                    {it.title}
                  </h3>
                </div>
                <ul className="flex flex-wrap gap-2">
                  {toTags(it.tags).map((tag) => (
                    <li
                      key={tag}
                      className="rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-3 py-1 text-[12.5px] text-muted backdrop-blur-sm transition-all duration-300 hover:-translate-y-0.5 hover:border-teal hover:bg-teal/[0.08] hover:text-teal-light hover:shadow-[0_8px_20px_-12px_rgba(20,184,166,.7)]"
                    >
                      {tag}
                    </li>
                  ))}
                </ul>
              </div>
            </StaggerItem>
          ))}
        </Stagger>
      </div>
    </section>
  );
}
