import { useLocale, useTranslations } from 'next-intl';
import { BriefBox } from '@/components/BriefBox';
import { SupplierLink } from '@/components/HeroCtas';
import { Counters } from '@/components/Counters';
import { HeroScene } from '@/components/visual/slots';
import { HeroPoster } from '@/components/visual/posters';
import { DesktopOnly } from '@/components/home/DesktopOnly';
import s from '@/components/home/sealed.module.css';

type Fact = { k: string; v: string };
type Step = { t: string; b: string };

// THE FIRST SCREEN ANSWERS WHAT, HOW AND WHAT IT COSTS.
//
// Founder, 14 Sep 2026: "if a customer enters the website and he never knew about the app, he
// should understand what we do in less than a minute without scrolling up and down many times."
// The first screen carries a plain headline naming the service, the Sealed line as its supporting
// promise, the job box as the single primary action, one sentence of how and the price in plain
// words; the three steps sit directly under it. Everything below the hero is optional reading.
//
// Three grid areas so the order is right on both sizes: on a phone the job box follows the headline
// directly (it is on the 812 px first screen); on desktop it sits in the right column in front of the
// Sealed scene — a lit stack of sealed quote slabs, the chosen one edged in gold — which never
// enters the headline column. The scene renders its poster first and loads three.js only after the
// first interaction on a capable desktop; under lg it is display:none, so a phone never requests it.
// The h1 and copy are server-rendered with no hidden initial state, so the LCP is text.
//
// The top 3 are a comparison REPORT; every other quote is listed too and any can be chosen
// (founder, 14 Sep 2026: "never claim that we only show 3").
export function Hero() {
  const t = useTranslations('hero');
  const locale = useLocale();
  const price = t.raw('price') as Fact[];
  const steps = t.raw('steps') as Step[];

  return (
    <div className={`${s.heroField} relative isolate overflow-hidden`}>
      <span className="grid-tech" aria-hidden />
      <section className="container-x relative grid gap-8 pb-12 pt-10 md:pt-14 lg:grid-cols-12 lg:gap-x-12 lg:gap-y-7 lg:pb-12 lg:pt-14">
        {/* A — what */}
        <div className="relative z-10 lg:col-span-7 lg:row-start-1 lg:self-end">
          <span className="qd-kicker">{t('kicker')}</span>
          <h1 className="mt-6 font-head text-[clamp(34px,4.9vw,64px)] font-semibold leading-[1.02] tracking-display text-white rtl:text-[clamp(29px,3.9vw,50px)] rtl:leading-[1.32]">
            {t('title')}
          </h1>
          <p className="mt-5 flex items-center gap-3 text-[clamp(16px,1.6vw,20px)] font-medium leading-snug text-gold">
            <span className="redact redact-line w-9! shrink-0" aria-hidden />
            {t('sealed')}
          </p>
        </div>

        {/* B — the one action, in front of the sealed stack */}
        <div className="relative lg:col-span-5 lg:col-start-8 lg:row-span-2 lg:row-start-1 lg:self-center">
          <div className="relative hidden h-[250px] lg:block" aria-hidden>
            <span className="halo -inset-x-16 -top-10 bottom-0" />
            <div className="absolute -inset-x-10 -top-8 bottom-0">
              {/* the poster is server-rendered; only a desktop viewport mounts the lazy 3D slot */}
              <DesktopOnly fallback={<HeroPoster />}>
                <HeroScene locale={locale === 'ar' ? 'ar' : 'en'} />
              </DesktopOnly>
            </div>
          </div>
          <div id="brief" className="relative z-10 scroll-mt-24 lg:-mt-20">
            <BriefBox />
          </div>
          <div className="relative z-10 mt-4">
            <SupplierLink ask={t('supplierAsk')} how={t('supplierHow')} portal={t('supplierPortal')} />
          </div>
        </div>

        {/* C — how, and what it costs */}
        <div className="relative z-10 lg:col-span-7 lg:row-start-2 lg:self-start">
          <p className="max-w-[58ch] text-pretty text-[clamp(15.5px,1.4vw,17.5px)] leading-relaxed text-muted">{t('how')}</p>
          <dl className="mt-6 grid max-w-[600px] gap-3 sm:grid-cols-2">
            {price.map((p) => (
              <div key={p.k} className="flex items-baseline gap-3 border-s-2 border-teal/60 ps-3.5">
                <dt className="font-head text-[22px] font-semibold tracking-snug text-white" dir="auto">{p.k}</dt>
                <dd className="text-[14px] leading-snug text-muted">{p.v}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* HOW IT WORKS, in one row, directly under the first screen's content */}
      <div className="relative border-t border-line bg-navy-deep/60">
        <ol aria-label={t('stepsLabel')} className="container-x grid gap-px md:grid-cols-3">
          {steps.map((st, i) => (
            <li key={st.t} className="flex gap-4 py-6 md:py-7 md:pe-8 md:not-first:border-s md:not-first:border-line md:not-first:ps-8">
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
