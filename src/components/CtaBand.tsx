import { useTranslations } from 'next-intl';
import { Reveal } from '@/components/motion/reveal';
import { HeroCtas } from '@/components/HeroCtas';
import { MeasuredMedian } from '@/components/Counters';

// ONE TIMELINE. The band said "Your next quote is minutes away" while the FAQ said 3–5 working days
// (website audit §1 finding 27). It now states the FAQ's operational figure, and adds the measured
// median only when the counters endpoint has one (five quoted jobs in 30 days).
export function CtaBand() {
  const t = useTranslations();
  return (
    <section className="container-x py-beat-s md:py-beat">
      <Reveal y={34}>
        <div className="relative">
          <span className="corners absolute -inset-3 hidden md:block" aria-hidden />
          <div className="glass depth relative isolate overflow-hidden rounded-[28px] px-7 py-16 text-center md:px-16 md:py-24">
            <span className="grid-tech" aria-hidden />
            <span className="halo left-1/2 top-1/2 h-[520px] w-[520px] -translate-x-1/2 -translate-y-1/2 opacity-80" aria-hidden />
            <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-teal/60 to-transparent" />
            <span className="relative mx-auto mb-7 flex w-fit items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-4 py-1.5 font-mono text-[12px] font-medium uppercase tracking-[0.2em] text-teal-light backdrop-blur-sm rtl:tracking-normal">
              <span className="node-dot" aria-hidden />
              {t('cta.eyebrow')}
            </span>
            <h2 className="crisp relative mx-auto max-w-[20ch] text-balance font-head text-[clamp(30px,4.6vw,54px)] font-semibold leading-[1.02] tracking-[-0.045em] text-white rtl:leading-[1.25] rtl:tracking-normal">
              {t('cta.title')}
            </h2>
            <p className="relative mx-auto mt-6 max-w-[56ch] text-pretty text-[clamp(15.5px,1.7vw,18px)] leading-relaxed text-muted">{t('cta.sub')}</p>
            <MeasuredMedian template={t('cta.median')} />
            <div className="relative mt-10">
              <HeroCtas
                align="center"
                labels={{ getQuotes: t('hero.ctaPrimary'), joinSupplier: t('cta.supplier'), myPortal: t('hero.myPortal'), supplierPortal: t('hero.supplierPortal') }}
              />
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
