import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { WorkedCase } from '@/components/WorkedCase';
import { AnonymityFlow } from '@/components/visual/slots';
import { PageHero, CtaPanel } from '@/components/DocFrame';
import { ComparisonShowcase, Kicker, LedgerList, ProductFrame, SectionHead } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';

// /how-it-works — the process distilled from the 150-answer FAQ, with the two-way anonymity table
// (website audit "Months" row). The worked-case slot renders only from a real closed deal.
// The comparison in the hero is illustrative and labelled sample. Founder, 14 Sep 2026: the top
// three are a technical comparison REPORT; every other quote is still listed and can be chosen, so
// the frame says so under the report.
type Step = { title: string; body: string };
type Row = { who: string; before: string; after: string };

const L = {
  en: {
    frame: 'report / technical comparison', status: 'Levelled', sample: 'Sample data',
    suppliers: ['A', 'B', 'C'], labels: { item: 'Item', total: 'Total AED', missing: 'Missing', best: 'Best' },
    rows: ['Gypsum partitions', 'Ceiling works', 'Paint & finishes', 'MEP first fix'],
    more: '+ 5 more quotes in the full list. Pick any of them.',
    stepsKicker: 'The process', maskKicker: 'Anonymity', timeKicker: 'Timing', finalKicker: 'Start',
  },
  ar: {
    frame: 'تقرير / مقارنة فنية', status: 'موحّد', sample: 'بيانات نموذجية',
    suppliers: ['أ', 'ب', 'ج'], labels: { item: 'البند', total: 'الإجمالي (درهم)', missing: 'غير مسعّر', best: 'الأفضل' },
    rows: ['قواطع جبسية', 'أعمال الأسقف', 'الدهانات والتشطيبات', 'التمديدات الكهروميكانيكية الأولية'],
    more: '+ 5 عروض أخرى في القائمة الكاملة، ويمكنك اختيار أيٍّ منها.',
    stepsKicker: 'المراحل', maskKicker: 'السرّية', timeKicker: 'المدد الزمنية', finalKicker: 'ابدأ',
  },
};

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'howPage' });
  return buildMeta({ locale, path: '/how-it-works', title: t('metaTitle'), description: t('metaDesc') });
}

export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const lang = locale === 'ar' ? 'ar' : 'en';
  const x = L[lang];
  const t = await getTranslations({ locale, namespace: 'howPage' });
  const steps = t.raw('steps') as Step[];
  const rows = t.raw('rows') as Row[];
  const time = t.raw('time') as string[];
  return (
    <>
      <SiteHeader />
      <main id="main">
        <PageHero
          kicker={t('kicker')}
          title={t('title')}
          lead={t('sub')}
          actions={<Button asChild size="xl" className="qd-magnet"><Link href="/#brief">{t('finalCta')}</Link></Button>}
          aside={
            <ProductFrame title={x.frame} sampleLabel={x.sample} status={x.status} className="shadow-e3">
              <ComparisonShowcase suppliers={x.suppliers} best={1} totals={['38,750', '36,900', '34,200']} labels={x.labels}
                rows={[
                  { item: x.rows[0], values: ['9,400', '9,100', '8,800'] },
                  { item: x.rows[1], values: ['7,250', '6,900', '7,000'] },
                  { item: x.rows[2], values: ['5,600', '5,400', '5,900'] },
                  { item: x.rows[3], values: ['16,500', '15,500', null] },
                ]} />
              <p className="border-t border-line px-4 py-3 font-mono text-label text-faint">{x.more}</p>
            </ProductFrame>
          }
        />

        <section className="container-x py-beat-s md:py-beat">
          <SectionHead kicker={x.stepsKicker} title={t('title')} className="sr-only" />
          {/* The steps are a real sequence, so a ledger with display serials, not a grid of boxes. */}
          <LedgerList lg titleAs="h2" className="qd-stagger reveal-stagger" items={steps.map((s) => ({ title: s.title, body: s.body }))} />
        </section>

        <section className="border-y border-line bg-navy-deep/40">
          <div className="container-x py-beat-s md:py-beat">
            <SectionHead kicker={x.maskKicker} title={t('maskTitle')} lead={t('maskSub')} />
            <div className="mt-10 empty:hidden">
              <AnonymityFlow locale={lang} />
            </div>
            <div className="qd-frame mt-10 overflow-x-auto">
              <table className="w-full min-w-[640px] border-collapse text-start text-body">
                <thead>
                  <tr className="border-b border-line2 bg-navy-deep/50">
                    <th scope="col" className="w-[22%] px-5 py-4" />
                    <th scope="col" className="px-5 py-4 text-start font-mono text-label uppercase tracking-caps text-teal-light">{t('before')}</th>
                    <th scope="col" className="px-5 py-4 text-start font-mono text-label uppercase tracking-caps text-gold-light">{t('after')}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.who} className="border-t border-line">
                      <th scope="row" className="px-5 py-5 text-start font-head text-[15px] font-semibold text-white">{r.who}</th>
                      <td className="px-5 py-5 text-muted">
                        <span className="me-2 inline-block align-middle redact redact-bar !h-2 !w-8" aria-hidden />{r.before}
                      </td>
                      <td className="px-5 py-5 text-paper/90">{r.after}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        <section className="container-x py-beat-s md:py-beat">
          <div className="grid gap-10 lg:grid-cols-[320px_1fr]">
            <div><Kicker>{x.timeKicker}</Kicker><h2 className="mt-5 font-head text-h2 text-white">{t('timeTitle')}</h2></div>
            {/* a measured ruler, not three boxes: the ticks run along the rule the days sit under */}
            <ol className="qd-ticks grid border-t border-line2 md:grid-cols-3">
              {time.map((line, i) => (
                <li key={line} className="relative border-b border-line pb-7 pt-9 md:border-b-0 md:pe-8 md:[&:not(:first-child)]:border-s md:[&:not(:first-child)]:ps-8">
                  <span className="tabular font-mono text-label text-teal-light">{String(i + 1).padStart(2, '0')}</span>
                  <p className="mt-3 text-copy text-paper/90">{line}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <WorkedCase />

        <CtaPanel kicker={x.finalKicker} title={t('finalTitle')}>
          <Button asChild size="xl" className="qd-magnet"><Link href="/#brief">{t('finalCta')}</Link></Button>
        </CtaPanel>
      </main>
      <SiteFooter />
    </>
  );
}
