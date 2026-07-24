import { useTranslations } from 'next-intl';
import { Reveal, TiltCard } from '@/components/motion/primitives';

type Item = { title: string; body: string };

export function WhyAnonymous() {
  const t = useTranslations('why');
  const items = t.raw('items') as Item[];
  return (
    <section id="why" className="py-beat-s md:py-beat">
      <div className="container-x">
        <Reveal className="grid gap-6 border-t border-[var(--line)] pt-10 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] md:gap-14">
          <h2 className="crisp max-w-[15ch] text-balance font-head text-[clamp(28px,3.4vw,44px)] font-semibold leading-[1.08] tracking-[-0.035em] text-white">
            {t('title')}
          </h2>
          <div className="self-end">
            <p className="text-[13px] font-medium text-teal-light">{t('eyebrow')}</p>
            <p className="mt-3 max-w-[56ch] text-pretty text-[16.5px] leading-relaxed text-muted">{t('sub')}</p>
          </div>
        </Reveal>

        {/* Asymmetric: the first claim gets the weight, the rest sit as a measured column. */}
        <div className="mt-12 grid gap-10 md:grid-cols-[minmax(0,1.05fr)_minmax(0,.95fr)] md:gap-16">
          {items.slice(0, 1).map((it) => (
            <Reveal key={it.title} y={30}>
              <TiltCard className="neon-edge mesh-glow relative rounded-[22px]" max={6}>
                <article className="glass depth relative overflow-hidden rounded-[22px] p-8 md:p-10">
                  <div className="mb-7 flex items-center gap-2" aria-hidden>
                    <span className="redact redact-sq" />
                    <span className="redact redact-bar w-28" />
                    <span className="redact redact-sq !w-3" />
                  </div>
                  <h3 className="max-w-[18ch] text-balance font-head text-[clamp(21px,2.2vw,27px)] font-semibold leading-[1.16] tracking-[-0.025em] text-white">
                    {it.title}
                  </h3>
                  <p className="mt-4 max-w-[46ch] text-pretty text-[15.5px] leading-relaxed text-muted">{it.body}</p>
                </article>
              </TiltCard>
            </Reveal>
          ))}
          <div className="flex flex-col justify-center">
            {items.slice(1).map((it, i) => (
              <Reveal key={it.title} delay={i * 0.08}>
                <article className="group border-b border-[var(--line)] py-7 first:border-t">
                  <h3 className="font-head text-[17.5px] font-semibold leading-snug tracking-[-0.015em] text-white transition-colors duration-300 group-hover:text-teal-light">
                    {it.title}
                  </h3>
                  <p className="mt-2.5 max-w-[52ch] text-pretty text-[14.5px] leading-relaxed text-muted">{it.body}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
