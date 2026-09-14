import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { EmiratesMap } from '@/components/visual/slots';
import { PageHero, CtaPanel } from '@/components/DocFrame';
import { Bento, BentoTile, BoqShowcase, Kicker, ProductFrame, Seal, SectionHead, Stepper } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

// /supplier WAS THE PORTAL ITSELF — a second copy of /portal behind a login box, and every supplier
// link on the site landed on that form (website audit §1 finding 6). It is now the supplier pitch;
// the app stays at /portal. Every figure below is the FAQ's (src/content/marketing.json, checked
// 14 Sep 2026): no commission; registration free permanently for the first 1,000 suppliers, AED
// 1,000/year from the 1,001st; the non-response charge; verification within 3 working days.
// The brief in the hero frame is illustrative and carries the kit's visible sample label.
type KV = { k: string; v: string };
type Step = { title: string; body: string };

const L = {
  en: {
    frame: 'rfq / fit-out · Dubai', status: 'New brief', sample: 'Sample data', customer: 'Customer',
    chips: ['Fit-out', 'Dubai', 'Drawings attached'],
    boq: { code: 'Code', desc: 'Description', unit: 'Unit', qty: 'Qty' },
    lines: ['Gypsum board partition, 12.5 mm', 'Suspended ceiling, mineral tile', 'Porcelain floor tiling 600 × 600', 'Emulsion paint, two coats'],
    econKicker: 'Economics', stepsKicker: 'Onboarding', coverage: 'Coverage', coverageNote: 'Briefs reach you only for the emirates you serve.',
    ruleKicker: 'Obligation', finalKicker: 'Supplier portal',
  },
  ar: {
    frame: 'طلب عرض سعر / تشطيبات · دبي', status: 'طلب جديد', sample: 'بيانات نموذجية', customer: 'العميل',
    chips: ['تشطيبات', 'دبي', 'مخططات مرفقة'],
    boq: { code: 'الرمز', desc: 'الوصف', unit: 'الوحدة', qty: 'الكمية' },
    lines: ['قواطع ألواح جبسية، 12.5 مم', 'سقف معلّق، بلاطات معدنية', 'تبليط أرضيات بورسلان 600 × 600', 'دهان مائي، طبقتان'],
    econKicker: 'الجدوى', stepsKicker: 'التسجيل', coverage: 'التغطية', coverageNote: 'لا تصلك الطلبات إلا من الإمارات التي تخدمها.',
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
          aside={
            // What the supplier sees before a reveal: the job, never the buyer.
            <ProductFrame title={x.frame} sampleLabel={x.sample} status={x.status} className="shadow-e3">
              <div className="flex flex-wrap items-center gap-2 border-b border-line px-5 py-4">
                <span className="text-small text-muted">{x.customer}</span>
                <Seal>Villa 14, Al Barsha</Seal>
                <span className="ms-auto flex flex-wrap gap-1.5">{x.chips.map((c) => <Badge key={c} variant="outline">{c}</Badge>)}</span>
              </div>
              <BoqShowcase labels={x.boq} lines={[
                { code: '02.10', desc: x.lines[0], unit: 'm²', qty: '184.0' },
                { code: '03.04', desc: x.lines[1], unit: 'm²', qty: '96.5' },
                { code: '06.02', desc: x.lines[2], unit: 'm²', qty: '112.0' },
                { code: '07.11', desc: x.lines[3], unit: 'm²', qty: '420.0' },
              ]} />
            </ProductFrame>
          }
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
