import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { EmiratesMap } from '@/components/visual/slots';
import { PageHero, CtaPanel } from '@/components/DocFrame';
import { DrawingToBoq } from '@/components/visual/product';
import { Bento, BentoTile, Kicker, SectionHead, Stepper } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';

// /supplier WAS THE PORTAL ITSELF — a second copy of /portal behind a login box, and every supplier
// link on the site landed on that form (website audit §1 finding 6). It is now the supplier pitch;
// the app stays at /portal. Every figure below is the FAQ's (src/content/marketing.json, checked
// 14 Sep 2026): no commission; registration free permanently for the first 1,000 suppliers, AED
// 1,000/year from the 1,001st; the non-response charge; verification within 3 working days.
// The drawing in the hero frame (DrawingToBoq) is illustrative and carries the visible sample label.
type KV = { k: string; v: string };
type Step = { title: string; body: string };

const L = {
  en: {
    econKicker: 'Economics', stepsKicker: 'Onboarding', coverage: 'Coverage', coverageNote: 'Briefs reach you from anywhere in the UAE, for the trades your licence covers.',
    ruleKicker: 'Obligation', finalKicker: 'Supplier portal',
  },
  ar: {
    econKicker: 'الجدوى', stepsKicker: 'التسجيل', coverage: 'التغطية', coverageNote: 'تصلك الطلبات من أي مكان في الإمارات، للأنشطة التي تغطيها رخصتك.',
    ruleKicker: 'التزام', finalKicker: 'بوابة الموردين',
  },
};

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  return buildMeta({ locale, path: '/supplier', title: t('metaTitle'), description: t('metaDesc') });
}

/** Bento spans for n tiles on the 6-column grid: a wide lead tile, then rows that fill. */
function spans(n: number): (2 | 3 | 4 | 6)[] {
  if (n <= 1) return [6];
  const out: (2 | 3 | 4 | 6)[] = [4, 2];
  let left = n - 2;
  while (left > 0) { const row = left >= 3 ? 3 : left; out.push(...Array(row).fill(row === 3 ? 2 : row === 2 ? 3 : 6)); left -= row; }
  return out;
}

export default async function SupplierLanding(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const lang = locale === 'ar' ? 'ar' : 'en';
  const x = L[lang];
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  const econ = t.raw('econ') as KV[];
  const steps = t.raw('steps') as Step[];
  const span = spans(econ.length);
  return (
    <>
      <SiteHeader />
      <main id="main">
        <PageHero
          kicker={t('kicker')}
          title={t('title')}
          lead={t('sub')}
          actions={<>
            <Button asChild size="xl" className="qd-magnet"><Link href="/portal">{t('cta')}</Link></Button>
            <Button asChild size="xl" variant="secondary"><Link href="/how-it-works">{t('cta2')}</Link></Button>
          </>}
          // What the supplier sees before a reveal: the drawing with the customer blacked out, and
          // the quantities read from it. The job, never the buyer.
          aside={<DrawingToBoq locale={lang} />}
        />

        <section className="container-x py-beat-s md:py-beat">
          <SectionHead kicker={x.econKicker} title={t('econTitle')} />
          <Bento className="mt-12 auto-rows-[minmax(180px,auto)]">
            {econ.map((e, i) => (
              <BentoTile key={e.k} span={span[i]} kicker={String(i + 1).padStart(2, '0')} title={e.k}
                className={i === 0 ? 'qd-keylight justify-end' : 'justify-end'}>
                {e.v}
              </BentoTile>
            ))}
          </Bento>
        </section>

        <section className="border-y border-line bg-navy-deep/40">
          <div className="container-x grid gap-14 py-beat-s md:py-beat lg:grid-cols-[1fr_1fr] lg:items-center">
            <div>
              <SectionHead kicker={x.stepsKicker} title={t('stepsTitle')} />
              <Stepper className="mt-12" steps={steps.map((s, i) => ({ title: s.title, body: s.body, meta: String(i + 1).padStart(2, '0'), state: i === 0 ? 'current' : 'next' }))} />
            </div>
            <figure className="qd-frame qd-grain relative overflow-hidden">
              <div className="qd-frame-bar"><i /><i /><i /><span className="ms-2 font-mono text-label text-muted">{x.coverage}</span></div>
              <div className="relative aspect-[16/11] w-full empty:hidden"><EmiratesMap locale={lang} /></div>
              <figcaption className="border-t border-line px-5 py-3.5 text-small text-muted">{x.coverageNote}</figcaption>
            </figure>
          </div>
        </section>

        <section className="container-x py-beat-s md:py-beat">
          <div className="qd-panel grid gap-8 p-7 md:grid-cols-[220px_1fr] md:p-10">
            <div>
              <Kicker>{x.ruleKicker}</Kicker>
              <h2 className="mt-4 font-head text-h3 text-white">{t('ruleTitle')}</h2>
            </div>
            <div>
              <p className="max-w-[70ch] text-copy text-paper/90">{t('ruleBody')}</p>
              <p className="mt-6 border-t border-line pt-5 text-small text-faint">{t('honest')}</p>
            </div>
          </div>
        </section>

        <CtaPanel kicker={x.finalKicker} title={t('finalTitle')} body={t('finalSub')}>
          <Button asChild size="xl" className="qd-magnet"><Link href="/portal">{t('cta')}</Link></Button>
        </CtaPanel>
      </main>
      <SiteFooter />
    </>
  );
}
