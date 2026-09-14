import { useTranslations } from 'next-intl';
import { Stagger, StaggerItem, TiltCard } from '@/components/motion/primitives';
import { SectionHeader } from '@/components/SectionHeader';

type Item = { title: string; body: string };

// A pinwheel bento: wide · narrow / narrow · wide — dynamic, never a card grid.
const SPAN = ['md:col-span-2', 'md:col-span-1', 'md:col-span-1', 'md:col-span-2'];

export function WhyAnonymous() {
  const t = useTranslations('why');
  const items = t.raw('items') as Item[];
  return (
    <section id="why" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="05" title={t('title')} sub={t('sub')} />

      <Stagger className="mt-14 grid gap-4 md:grid-cols-3 md:gap-5">
        {items.map((it, i) => {
          const wide = i === 0 || i === 3;
          return (
            <StaggerItem key={it.title} className={SPAN[i % SPAN.length]}>
              <TiltCard
                className="neon-edge tile h-full rounded-[22px]"
                max={wide ? 5 : 7}
                glow={wide}
              >
                <article
                  className={`glass relative flex h-full flex-col overflow-hidden rounded-[22px] p-7 md:p-8 ${
                    wide ? 'mesh-glow' : ''
                  }`}
                >
                  {wide && <span className="grid-tech grid-tech-sm opacity-60" aria-hidden />}
                  {/* identity-withheld motif */}
                  <div className="relative mb-6 flex items-center gap-2" aria-hidden>
                    <span className="redact redact-sq !h-7 !w-7" />
                    <span className="redact redact-bar w-20" />
                    <span className="redact redact-sq !h-3 !w-3" />
                    <span className="ml-auto font-mono text-[10px] tabular text-faint/60">
                      {String(i + 1).padStart(2, '0')}
                    </span>
                  </div>
                  <h3
                    className={`crisp relative text-balance font-head font-semibold leading-[1.12] tracking-[-0.03em] text-white ${
                      wide ? 'text-[clamp(21px,2.3vw,28px)]' : 'text-[19px]'
                    }`}
                  >
                    {it.title}
                  </h3>
                  <p className="relative mt-3.5 max-w-[46ch] text-pretty text-[14.5px] leading-relaxed text-muted">
                    {it.body}
                  </p>
                </article>
              </TiltCard>
            </StaggerItem>
          );
        })}
      </Stagger>
    </section>
  );
}
