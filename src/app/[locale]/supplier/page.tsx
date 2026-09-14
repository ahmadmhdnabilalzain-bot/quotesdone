import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Reveal, Stagger, StaggerItem } from '@/components/motion/primitives';
import { EmiratesMap } from '@/components/visual/slots';

// /supplier WAS THE PORTAL ITSELF — a second copy of /portal behind a login box, and every supplier
// link on the site landed on that form (website audit §1 finding 6). It is now the supplier pitch;
// the app stays at /portal. Every figure below is the FAQ's (src/content/marketing.json, checked
// 14 Sep 2026): no commission; registration free permanently for the first 1,000 suppliers, AED
// 1,000/year from the 1,001st; the non-response charge; verification within 3 working days.
type KV = { k: string; v: string };
type Step = { title: string; body: string };

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  return buildMeta({ locale, path: '/supplier', title: t('metaTitle'), description: t('metaDesc') });
}

export default async function SupplierLanding(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  const econ = t.raw('econ') as KV[];
  const steps = t.raw('steps') as Step[];
  const primary = 'btn-key press inline-flex rounded-full bg-teal px-8 py-4 text-[15.5px] font-bold text-[#04231F] shadow-[0_16px_44px_-16px_rgba(20,184,166,.8)] hover:bg-[#1ED0BC]';
  return (
    <>
      <SiteHeader />
      <main id="main">
        <section className="bloom relative overflow-hidden">
          <span className="grid-tech" aria-hidden />
          <div className="container-x relative z-10 grid items-center gap-12 pb-16 pt-16 md:pt-24 lg:grid-cols-[1.1fr_.9fr]">
            <div>
              <span className="font-mono text-[11px] uppercase tracking-[0.18em] text-gold rtl:tracking-normal">{t('kicker')}</span>
              <h1 className="crisp mt-5 font-head text-[clamp(34px,5.2vw,64px)] font-semibold leading-[1.0] tracking-[-0.045em] text-white rtl:leading-[1.25] rtl:tracking-normal">
                {t('title')}
              </h1>
              <p className="mt-6 max-w-[56ch] text-[17px] leading-relaxed text-muted">{t('sub')}</p>
              <div className="mt-9 flex flex-wrap gap-3">
                <Link href="/portal" className={primary}>{t('cta')}</Link>
                <Link href="/how-it-works" className="press inline-flex rounded-full border border-[var(--line2)] px-8 py-4 text-[15.5px] font-semibold text-paper hover:border-teal hover:text-white">
                  {t('cta2')}
                </Link>
              </div>
            </div>
            {/* What the supplier sees before a reveal: the job, never the buyer. */}
            <div className="glass depth relative overflow-hidden rounded-[22px] p-6" aria-hidden>
              <span className="grid-tech grid-tech-sm opacity-50" />
              <div className="relative mb-5 aspect-[16/10] w-full overflow-hidden rounded-[14px] empty:hidden">
                <EmiratesMap locale={locale === 'ar' ? 'ar' : 'en'} />
              </div>
              <div className="relative space-y-3">
                <div className="flex items-center gap-2"><span className="redact redact-sq !h-7 !w-7" /><span className="redact redact-bar !w-32" /></div>
                <div className="rounded-[12px] border border-[var(--line2)] bg-navy-deep/60 p-4">
                  <div className="h-2 w-3/4 rounded bg-teal/30" />
                  <div className="mt-2 h-2 w-1/2 rounded bg-teal/20" />
                  <div className="mt-4 grid grid-cols-3 gap-2">
                    {[0, 1, 2].map((i) => <div key={i} className="h-10 rounded-[8px] border border-[var(--line)] bg-teal-light/[0.03]" />)}
                  </div>
                </div>
                <div className="flex gap-2"><span className="redact redact-bar !w-20" /><span className="redact redact-bar !w-12" /></div>
              </div>
            </div>
          </div>
        </section>

        <section className="container-x py-beat-s">
          <h2 className="font-head text-[clamp(26px,3vw,36px)] font-semibold tracking-[-0.03em] text-white">{t('econTitle')}</h2>
          <Stagger className="mt-10 grid gap-px overflow-hidden rounded-[22px] border border-[var(--line2)] bg-[var(--line)] md:grid-cols-2 lg:grid-cols-3">
            {econ.map((e, i) => (
              <StaggerItem key={e.k} className={`relative bg-navy-deep/90 p-7 ${i === 0 ? 'lg:col-span-2 mesh-glow' : ''}`}>
                <span className="font-mono text-[11px] text-gold">{String(i + 1).padStart(2, '0')}</span>
                <h3 className="mt-4 font-head text-[21px] font-semibold tracking-[-0.02em] text-white">{e.k}</h3>
                <p className="mt-2.5 max-w-[52ch] text-[14.5px] leading-relaxed text-muted">{e.v}</p>
              </StaggerItem>
            ))}
          </Stagger>
        </section>

        <section className="container-x py-beat-s">
          <h2 className="font-head text-[clamp(24px,2.8vw,32px)] font-semibold text-white">{t('stepsTitle')}</h2>
          <ol className="mt-8 grid gap-4 md:grid-cols-4">
            {steps.map((s, i) => (
              <li key={s.title} className="tile relative rounded-[18px] border border-[var(--line2)] bg-navy-deep/50 p-6">
                <span className="flex h-9 w-9 items-center justify-center rounded-full border border-teal/50 font-mono text-[13px] text-teal-light">{i + 1}</span>
                <h3 className="mt-4 font-head text-[17px] font-semibold text-white">{s.title}</h3>
                <p className="mt-2 text-[13.5px] leading-relaxed text-muted">{s.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="container-x py-beat-s">
          <Reveal className="rounded-[22px] border border-gold/30 bg-gold/[0.04] p-7 md:p-9">
            <h2 className="font-head text-[22px] font-semibold text-gold">{t('ruleTitle')}</h2>
            <p className="mt-3 max-w-[76ch] text-[15px] leading-relaxed text-paper/90">{t('ruleBody')}</p>
            <p className="mt-5 text-[13px] leading-relaxed text-faint">{t('honest')}</p>
          </Reveal>
        </section>

        <section className="container-x py-beat-s text-center">
          <h2 className="font-head text-[clamp(26px,3vw,40px)] font-semibold text-white">{t('finalTitle')}</h2>
          <p className="mx-auto mt-4 max-w-[52ch] text-[16px] text-muted">{t('finalSub')}</p>
          <Link href="/portal" className={`${primary} mt-8`}>{t('cta')}</Link>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
