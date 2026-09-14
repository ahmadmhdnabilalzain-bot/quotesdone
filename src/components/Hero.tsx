import { useLocale, useTranslations } from 'next-intl';
import { BriefBox } from '@/components/BriefBox';
import { HeroCtas } from '@/components/HeroCtas';
import { Counters } from '@/components/Counters';
import { HeroScene } from '@/components/visual/slots';
import s from '@/components/home/sealed.module.css';

type Fact = { k: string; v: string };
type Step = { t: string; b: string };

// THE FIRST SCREEN ANSWERS WHAT, HOW AND WHAT IT COSTS.
//
// Founder, 14 Sep 2026: "if a customer enters the website and he never knew about the app, he
// should understand what we do in less than a minute without scrolling up and down many times."
// So the first screen carries, in reading order: a plain headline naming the service, the Sealed
// line as its supporting promise, one sentence of how, the price in plain words, and the job box
// as the single primary action; the three steps sit directly under it. Everything below the hero
// is optional reading.
//
// The h1 and copy are server-rendered with no hidden initial state, so they paint at TTFB and the
// LCP is text. The 3D scene is desktop-only decoration behind the job box: under lg its slot is
// display:none, so its gate never opens and three.js is never requested on a phone.
//
// The top 3 are a comparison REPORT; every other quote is listed as well and any can be chosen
// (founder, 14 Sep 2026: "never claim that we only show 3").
export function Hero() {
  const t = useTranslations('hero');
  const locale = useLocale();
  const price = t.raw('price') as Fact[];
  const steps = t.raw('steps') as Step[];

  return (
    <div className={`${s.heroField} relative isolate overflow-hidden`}>
      <span className="grid-tech" aria-hidden />
      <section className="container-x relative grid gap-10 pb-12 pt-10 md:pt-14 lg:grid-cols-12 lg:items-center lg:gap-x-12 lg:pb-14 lg:pt-16">
        <div className="relative z-10 lg:col-span-7">
          <span className="qd-kicker">{t('kicker')}</span>
          <h1 className="mt-6 font-head text-[clamp(36px,4.9vw,64px)] font-semibold leading-[1.02] tracking-display text-white rtl:text-[clamp(30px,3.9vw,50px)] rtl:leading-[1.32]">
            {t('title')}
          </h1>
          <p className="mt-5 flex items-center gap-3 text-[clamp(16px,1.6vw,20px)] font-medium leading-snug text-gold">
            <span className="redact redact-line !w-9 shrink-0" aria-hidden />
            {t('sealed')}
          </p>
          <p className="mt-5 max-w-[58ch] text-pretty text-[clamp(15.5px,1.4vw,17.5px)] leading-relaxed text-muted">{t('how')}</p>
          <dl className="mt-7 grid max-w-[600px] gap-3 sm:grid-cols-2">
            {price.map((p) => (
              <div key={p.k} className="flex items-baseline gap-3 border-s-2 border-teal/60 ps-3.5">
                <dt className="font-head text-[22px] font-semibold tracking-snug text-white" dir="auto">{p.k}</dt>
                <dd className="text-[14px] leading-snug text-muted">{p.v}</dd>
              </div>
            ))}
          </dl>
        </div>

        <div className="relative lg:col-span-5">
          {/* desktop-only scene: sits behind the job box and bleeds up and outward, never into the copy */}
          <div className="pointer-events-none absolute -end-24 -top-24 bottom-10 start-10 hidden opacity-70 lg:block [mask-image:radial-gradient(closest-side,#000_55%,transparent)]" aria-hidden>
            <HeroScene locale={locale === 'ar' ? 'ar' : 'en'} />
          </div>
          <div id="brief" className="relative z-10 scroll-mt-24">
            <BriefBox />
          </div>
          <div className="relative z-10 mt-5">
            <HeroCtas
              quiet
              note
              labels={{
                getQuotes: t('ctaPrimary'), joinSupplier: t('ctaSupplier'), myPortal: t('myPortal'),
                supplierPortal: t('supplierPortal'), supplierTitle: t('supplierTitle'),
                supplierBody: t('supplierBody'), supplierHow: t('supplierHow'),
              }}
            />
          </div>
        </div>
      </section>

      {/* HOW IT WORKS, in one row, directly under the first screen's content */}
      <div className="relative border-t border-line bg-navy-deep/60">
        <ol aria-label={t('stepsLabel')} className="container-x grid gap-px md:grid-cols-3">
          {steps.map((st, i) => (
            <li key={st.t} className="flex gap-4 py-6 md:py-7 md:pe-8 md:[&:not(:first-child)]:border-s md:[&:not(:first-child)]:border-line md:[&:not(:first-child)]:ps-8">
              <span className={`mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-full font-mono text-label ${i === 2 ? 'bg-gold/15 text-gold shadow-[inset_0_0_0_1px_rgba(227,192,101,.5)]' : 'text-teal-light shadow-[inset_0_0_0_1px_rgba(110,231,212,.35)]'}`}>
                {i + 1}
              </span>
              <div>
                <h2 className="font-head text-[17px] font-semibold tracking-snug text-white">{st.t}</h2>
                <p className="mt-1.5 text-[14px] leading-relaxed text-muted">{st.b}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>

      {/* Measured counts appear only once each clears its floor; until then nothing is printed. */}
      <Counters>{null}</Counters>
    </div>
  );
}
