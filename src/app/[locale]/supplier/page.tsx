import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { EmiratesMap } from '@/components/visual/slots';
import { PageHero, CtaPanel } from '@/components/DocFrame';
import { Kicker, LedgerList, SealedCard, SectionHead, Stamp, Stepper } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';

// /supplier WAS THE PORTAL ITSELF — a second copy of /portal behind a login box, and every supplier
// link on the site landed on that form (website audit §1 finding 6). It is now the supplier pitch;
// the app stays at /portal. Every figure below is the FAQ's (src/content/marketing.json, checked
// 14 Sep 2026): no commission; registration free permanently for the first 1,000 suppliers, AED
// 1,000/year from the 1,001st; the non-response charge. Verification is automatic (16 Nov 2026, ruling 1681: the licence
// reader decides the moment a document is saved; the name and trade are read from the licence, ruling 1672).
// THE PRODUCT VISUAL IS GONE (founder instruction 70, 14 Sep 2026: "i dont like the product visuals at
// all. cancel that idea"). The hero carried a drawing-to-BOQ mock-up (DrawingToBoq) whose title block
// printed CLIENT / PROJECT / TEL / EMAIL in English on /ar/supplier too; it was removed 22 Sep 2026
// with src/components/visual/product.tsx.
type KV = { k: string; v: string };
type Step = { title: string; body: string };

const L = {
  en: {
    econKicker: 'Economics', stepsKicker: 'Onboarding', coverage: 'Coverage', coverageNote: 'Briefs reach you from anywhere in the UAE, for the trades and services you confirm on your verified profile.',
    ruleKicker: 'Obligation', finalKicker: 'Supplier portal',
  },
  ar: {
    econKicker: 'الجدوى', stepsKicker: 'التسجيل', coverage: 'التغطية', coverageNote: 'تصلكم الطلبات من أي مكان في الإمارات، وفق الأنشطة والخدمات التي تؤكّدونها في ملفكم الموثّق.',
    ruleKicker: 'التزام', finalKicker: 'بوابة الموردين',
  },
};

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  return buildMeta({ locale, path: '/supplier', title: t('metaTitle'), description: t('metaDesc') });
}

export default async function SupplierLanding(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const lang = locale === 'ar' ? 'ar' : 'en';
  const x = L[lang];
  const t = await getTranslations({ locale, namespace: 'supplierLanding' });
  const econ = t.raw('econ') as KV[];
  const steps = t.raw('steps') as Step[];
  return (
    <>
      <SiteHeader />
      <main id="main">
        <PageHero
          kicker={t('kicker')}
          title={t('title')}
          lead={t('sub')}
          actions={<>
            <Button asChild size="xl" className="qd-magnet"><Link href="/portal?join=1">{t('cta')}</Link></Button>
            <Button asChild size="xl" variant="secondary"><Link href="/how-it-works">{t('cta2')}</Link></Button>
          </>}
        />

        <section className="container-x py-beat-s md:py-beat">
          <SectionHead kicker={x.econKicker} title={t('econTitle')} />
          {/* a lead document and the ledger beside it, not a bento of equal tiles */}
          <div className="mt-12 grid gap-10 lg:grid-cols-[5fr_7fr] lg:gap-14">
            {econ[0] ? (
              <SealedCard size="lg" className="flex flex-col gap-3 self-start p-7 pt-14 md:p-9 md:pt-16">
                <Stamp n={1} />
                <h3 className="mt-3 text-balance font-head text-h3 text-white">{econ[0].k}</h3>
                <p className="text-copy text-muted">{econ[0].v}</p>
              </SealedCard>
            ) : null}
            <LedgerList start={2} items={econ.slice(1).map((e) => ({ title: e.k, body: e.v }))} />
          </div>
        </section>

        <section className="border-y border-line bg-navy-deep/40">
          <div className="container-x grid gap-14 py-beat-s md:py-beat lg:grid-cols-[1fr_1fr] lg:items-center">
            <div>
              <SectionHead kicker={x.stepsKicker} title={t('stepsTitle')} />
              <Stepper className="mt-12" steps={steps.map((s, i) => ({ title: s.title, body: s.body, meta: String(i + 1).padStart(2, '0'), state: i === 0 ? 'current' : 'next' }))} />
            </div>
            <figure className="qd-frame qd-grain relative overflow-hidden">
              <div className="qd-frame-bar"><i /><i /><i /><span className="ms-2 font-mono text-label text-muted">{x.coverage}</span></div>
              <div className="relative aspect-16/11 w-full empty:hidden"><EmiratesMap locale={lang} /></div>
              <figcaption className="border-t border-line px-5 py-3.5 text-small text-muted">{x.coverageNote}</figcaption>
            </figure>
          </div>
        </section>

        <section className="container-x py-beat-s md:py-beat">
          <div className="qd-env qd-env-lg grid gap-8 p-7 pt-12 md:grid-cols-[220px_1fr] md:p-10 md:pt-14">
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
          <Button asChild size="xl" className="qd-magnet"><Link href="/portal?join=1">{t('cta')}</Link></Button>
        </CtaPanel>
      </main>
      <SiteFooter />
    </>
  );
}
