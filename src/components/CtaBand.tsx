import { useTranslations } from 'next-intl';
import { HeroCtas } from '@/components/HeroCtas';
import { MeasuredMedian } from '@/components/Counters';
import s from '@/components/home/sealed.module.css';

// ONE TIMELINE. The sub states the FAQ's operational figure (3–5 working days) and the measured
// median appears only when the counters endpoint has one (website audit §1 finding 27).
// The row of seals above the headline is the brand line drawn: seven sealed, one opened.
export function CtaBand() {
  const t = useTranslations();
  return (
    <section className="container-x pb-beat md:pb-beat-l">
      <div className={`${s.shell} ${s.rise}`}>
        <div className={`${s.core} relative isolate overflow-hidden px-6 py-16 text-center md:px-16 md:py-24`}>
          <span className={s.hairGrid} aria-hidden />
          <span className={`${s.keyLight} left-1/2 top-0 h-[560px] w-[760px] max-w-[160%] -translate-x-1/2 -translate-y-1/2`} aria-hidden />
          <div className="relative mx-auto flex w-fit items-center gap-2" aria-hidden>
            {Array.from({ length: 7 }).map((_, i) =>
              i === 3 ? (
                <span key={i} className="h-3 w-12 rounded-[2px] shadow-[inset_0_0_0_1px_#E3C065]" />
              ) : (
                <span key={i} className={`${s.seal} w-9 text-[19px]`} />
              ),
            )}
          </div>
          <h2 className={`${s.h2} relative mx-auto mt-10 max-w-[18ch] text-balance font-head font-semibold text-white`}>
            {t('cta.title')}
          </h2>
          <p className="relative mx-auto mt-6 max-w-[56ch] text-pretty text-[clamp(15.5px,1.6vw,18px)] leading-relaxed text-muted">{t('cta.sub')}</p>
          <MeasuredMedian template={t('cta.median')} />
          <div className="relative mt-10">
            <HeroCtas
              align="center"
              labels={{ getQuotes: t('hero.ctaPrimary'), joinSupplier: t('cta.supplier'), myPortal: t('hero.myPortal'), supplierPortal: t('hero.supplierPortal') }}
            />
          </div>
        </div>
      </div>
    </section>
  );
}
