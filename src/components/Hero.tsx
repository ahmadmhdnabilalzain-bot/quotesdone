import { useLocale, useTranslations } from 'next-intl';
import { LiveMatch } from '@/components/LiveMatch';
import { BriefBox } from '@/components/BriefBox';
import { HeroCtas } from '@/components/HeroCtas';
import { Counters } from '@/components/Counters';
import { HeroScene } from '@/components/visual/slots';
import { Link } from '@/i18n/routing';

type Proof = { k: string; v: string };
// hero.proof[2] is "Verified — licence checked before quoting" (ar: "موثّقون") in both message files.
const VERIFIED = 2;

// THE HERO PAINTS AT TTFB.
//
// It was a motion Stagger whose hidden state is opacity 0 / blur(6px), released by whileInView
// after ~850 KB of JavaScript hydrated: Lighthouse mobile LCP 7.6 s, 99.4% render delay, and four
// audit screenshots of a blank first screen (website audit §1 findings 7 and 8). The badge, h1,
// subtitle, buttons and the brief box are now plain server-rendered markup with no hidden initial
// state, so the h1 is the LCP element and it is visible in the HTML itself. Motion stays below the
// fold and inside the demonstration card, which also renders its final frame on the server.
export function Hero() {
  const t = useTranslations('hero');
  const locale = useLocale();
  const proof = t.raw('proof') as Proof[];
  const ticker = [...proof, ...proof];

  return (
    <div className="bloom relative isolate overflow-hidden">
      <span className="grid-tech" aria-hidden />
      {/* The 3D scene sits behind the text and paints after first paint; the h1 stays the LCP. */}
      <div className="pointer-events-none absolute inset-0 -z-10" aria-hidden>
        <HeroScene locale={locale === 'ar' ? 'ar' : 'en'} />
      </div>
      <section className="container-x relative z-10 grid items-start gap-12 pb-16 pt-12 md:pt-20 lg:grid-cols-[1.08fr_.92fr] lg:gap-14 lg:pb-20">
        <div className="flex flex-col items-start text-start">
          <span className="inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-4 py-1.5 font-mono text-[12px] font-medium uppercase tracking-[0.16em] text-teal-light backdrop-blur-sm rtl:font-sans rtl:normal-case rtl:tracking-normal">
            <span className="qd-pulse h-1.5 w-1.5 shrink-0 rounded-full bg-teal" />
            {t('badge')}
          </span>
          <h1 className="crisp mt-7 font-head text-[clamp(38px,6vw,76px)] font-semibold leading-[0.96] tracking-[-0.05em] text-white rtl:leading-[1.2] rtl:tracking-normal">
            {t('titleA')}{' '}
            <span className="text-brand-grad">{t('titleB')} {t('titleEm')}</span>
          </h1>
          <p className="mt-6 max-w-[56ch] text-pretty text-[clamp(15.5px,1.6vw,18px)] leading-relaxed text-muted">
            {t('subtitle')}
          </p>
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
          <div id="brief" className="mt-9 w-full scroll-mt-24">
            <BriefBox />
          </div>
        </div>

        {/* the demonstration — the real comparison engine replayed over a fixed sample */}
        <div className="relative mx-auto w-full max-w-[540px] lg:mt-6">
          <span className="halo left-1/2 top-1/2 h-[115%] w-[115%] -translate-x-1/2 -translate-y-1/2" aria-hidden />
          <span className="corners absolute -inset-3 hidden sm:block" aria-hidden />
          <LiveMatch
            locale={locale}
            labels={{
              engine: t('engine'), demo: t('demo'), posted: t('posted'), brief: t('briefText'),
              competing: t('competing'), scoring: t('scoring'), shortlisted: t('shortlisted'), cut: t('cut'),
              best: t('best'), hidden: t('hidden'), reveal: t('reveal'), price: t('price'),
              delivery: t('delivery'), quality: t('quality'), note: t('note'), supplier: t('supplier'),
            }}
          />
        </div>
      </section>

      {/* Measured counts replace the descriptors only once each clears its floor. Until then the
          descriptors below are what renders — server-side, with no invented number in them. */}
      <Counters>
        <div className="relative z-10 border-y border-[var(--line)] bg-navy-deep/40 py-5 backdrop-blur-sm">
          <div className="relative overflow-hidden [mask-image:linear-gradient(90deg,transparent,#000_8%,#000_92%,transparent)]">
            <div className="marquee items-center gap-0">
              {ticker.map((p, i) => {
                const body = (
                  <>
                    <span className="node-dot" aria-hidden />
                    <span className="font-head text-[15px] font-semibold tracking-[-0.01em] text-white">{p.k}</span>
                    <span className="text-[14px] text-faint">{p.v}</span>
                  </>
                );
                const cls = 'flex items-center gap-3 whitespace-nowrap px-7';
                const copy = i >= proof.length;
                // The "Verified / licence checked" claim links to the page that shows the check.
                // The duplicated marquee copy is aria-hidden, so its link is taken out of tab order.
                return i % proof.length === VERIFIED ? (
                  <Link key={i} href="/how-we-verify" className={`${cls} underline-offset-4 hover:underline`} aria-hidden={copy || undefined} tabIndex={copy ? -1 : undefined}>{body}</Link>
                ) : (
                  <span key={i} className={cls} aria-hidden={copy}>{body}</span>
                );
              })}
            </div>
          </div>
        </div>
      </Counters>
    </div>
  );
}
