import { useTranslations } from 'next-intl';
import { Reveal, TiltCard } from '@/components/motion/primitives';

type Item = { title: string; body: string };

export function WhyAnonymous() {
  const t = useTranslations('why');
  const items = t.raw('items') as Item[];
  return (
    <section id="why" className="py-beat-s md:py-beat">
      <div className="container-x">
        <Reveal className="border-t border-[var(--line)] pt-10">
          <div className="flex items-center gap-4 font-mono text-[10.5px] uppercase tracking-[0.2em] text-teal-light">
            <span className="node-dot" aria-hidden />
            <span>{t('eyebrow')}</span>
            <span className="tabular ml-auto text-faint/60">03</span>
          </div>
          <div className="mt-6 grid gap-6 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] md:gap-14">
            <h2 className="crisp max-w-[15ch] text-balance font-head text-[clamp(28px,3.6vw,46px)] font-semibold leading-[1.05] tracking-[-0.04em] text-white">
              {t('title')}
            </h2>
            <p className="max-w-[56ch] self-end text-pretty text-[16.5px] leading-relaxed text-muted">{t('sub')}</p>
          </div>
        </Reveal>

        {/* Asymmetric: the lead claim gets the instrument treatment, the rest a measured column. */}
        <div className="mt-12 grid gap-10 md:grid-cols-[minmax(0,1.05fr)_minmax(0,.95fr)] md:gap-16">
          {items.slice(0, 1).map((it) => (
            <Reveal key={it.title} y={30}>
              <div className="relative">
                <span className="corners absolute -inset-3 hidden md:block" aria-hidden />
                <TiltCard className="neon-edge mesh-glow relative rounded-[22px]" max={6}>
                  <article className="glass depth relative overflow-hidden rounded-[22px] p-8 md:p-10">
                    <span className="grid-tech grid-tech-sm" aria-hidden />
                    <div className="relative mb-7 flex items-center gap-2" aria-hidden>
                      <span className="redact redact-sq" />
                      <span className="redact redact-bar w-28" />
                      <span className="redact redact-sq !w-3" />
                    </div>
                    <h3 className="relative max-w-[18ch] text-balance font-head text-[clamp(21px,2.2vw,28px)] font-semibold leading-[1.14] tracking-[-0.03em] text-white">
                      {it.title}
                    </h3>
                    <p className="relative mt-4 max-w-[46ch] text-pretty text-[15.5px] leading-relaxed text-muted">
                      {it.body}
                    </p>
                  </article>
                </TiltCard>
              </div>
            </Reveal>
          ))}
          <div className="flex flex-col justify-center">
            {items.slice(1).map((it, i) => (
              <Reveal key={it.title} delay={i * 0.08}>
                <article className="group relative border-b border-[var(--line)] py-7 pl-5 first:border-t">
                  {/* a hover accent bar reads as selection on an instrument list */}
                  <span className="absolute inset-y-7 left-0 w-px bg-teal/30 transition-all duration-300 group-hover:bg-teal group-hover:shadow-[0_0_10px_rgba(110,231,212,.7)]" />
                  <h3 className="font-head text-[18px] font-semibold leading-snug tracking-[-0.015em] text-white transition-colors duration-300 group-hover:text-teal-light">
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
