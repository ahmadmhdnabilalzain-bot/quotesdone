import { useLocale, useTranslations } from 'next-intl';
import { BriefBox } from '@/components/BriefBox';
import { HeroCtas } from '@/components/HeroCtas';
import { Counters } from '@/components/Counters';
import { HeroScene } from '@/components/visual/slots';
import { Link } from '@/i18n/routing';
import s from '@/components/home/sealed.module.css';

type Proof = { k: string; v: string };
// hero.proof[3] is "Licence-checked — before any supplier quotes" in both message files; the claim
// links to the page that shows the check.
const VERIFIED = 3;

// THE HERO PAINTS AT TTFB.
//
// The h1 is plain server-rendered markup with no hidden initial state, so it is the LCP element and
// visible in the HTML itself (a hidden-until-hydrated hero measured LCP 7.6 s on Lighthouse mobile,
// website audit §1 findings 7-8). The Sealed 3D scene is decorative and sits on the inline-end side,
// not under the headline: on the live site the scene's gold slab collided with the h1 at 1440 px.
// It is mounted through visual/slots, so its poster paints first and three.js loads only after the
// visitor's first interaction on a capable device.
export function Hero() {
  const t = useTranslations('hero');
  const locale = useLocale();
  const proof = t.raw('proof') as Proof[];

  return (
    <div className={`${s.heroField} relative isolate overflow-hidden`}>
      <span className={s.hairGrid} aria-hidden />
      <section className="container-x relative grid gap-y-10 pb-16 pt-14 md:pt-24 lg:grid-cols-12 lg:gap-x-8 lg:pb-24 lg:pt-28">
        <div className="relative z-10 flex flex-col items-start text-start lg:col-span-7">
          <span className={`${s.eyebrow} inline-flex items-center gap-3 text-teal-light`}>
            <span className="qd-pulse h-1.5 w-1.5 shrink-0 rounded-full bg-teal" aria-hidden />
            {t('kicker')}
          </span>
          <h1 className={`${s.display} mt-7 font-head font-semibold text-white`}>
            <span className="block">
              {t('title1')}
              <span className={`${s.seal} ms-[0.18em] w-[1.3em]`} aria-hidden />
            </span>
            <span className={`${s.opened} block`}>{t('title2')}</span>
          </h1>
          <p className="mt-7 max-w-[54ch] text-pretty text-[clamp(16px,1.55vw,19px)] leading-relaxed text-muted">
            {t('subtitle')}
          </p>
          <div id="brief" className="mt-10 w-full max-w-[680px] scroll-mt-24">
            <BriefBox />
          </div>
          <div className="mt-8">
            <HeroCtas
              note
              labels={{
                getQuotes: t('ctaPrimary'), joinSupplier: t('ctaSupplier'), myPortal: t('myPortal'),
                supplierPortal: t('supplierPortal'), supplierTitle: t('supplierTitle'),
                supplierBody: t('supplierBody'), supplierHow: t('supplierHow'),
              }}
            />
          </div>
        </div>

        {/* The scene: a block under the copy on phones, a bleed on the inline-end side on desktop. */}
        <div className="relative lg:col-span-5" aria-hidden>
          <span className={`${s.keyLight} left-1/2 top-1/2 h-[120%] w-[120%] -translate-x-1/2 -translate-y-1/2`} />
          <div className="relative mx-auto aspect-[5/4] w-full max-w-[520px] lg:absolute lg:-inset-y-10 lg:-end-24 lg:mx-0 lg:aspect-auto lg:w-[130%] lg:max-w-none">
            <HeroScene locale={locale === 'ar' ? 'ar' : 'en'} />
          </div>
        </div>
      </section>

      {/* Measured counts replace these four statements only once each clears its floor. Until then
          the statements render — server-side, with no invented number in them. */}
      <Counters>
        <div className="relative border-t border-[var(--line)] bg-navy-deep/60">
          <dl className="container-x grid grid-cols-2 gap-x-6 gap-y-6 py-7 md:grid-cols-4">
            {proof.map((p, i) => {
              const body = (
                <>
                  <dt className="font-head text-[clamp(17px,1.8vw,21px)] font-semibold tracking-[-0.02em] text-white rtl:tracking-normal">{p.k}</dt>
                  <dd className="mt-1 text-[13.5px] leading-snug text-faint">{p.v}</dd>
                </>
              );
              return i === VERIFIED ? (
                <Link key={p.k} href="/how-we-verify" className="group block border-s border-[var(--line2)] ps-4 underline-offset-4 hover:[&_dt]:underline">
                  {body}
                </Link>
              ) : (
                <div key={p.k} className="border-s border-[var(--line2)] ps-4">{body}</div>
              );
            })}
          </dl>
        </div>
      </Counters>
    </div>
  );
}
