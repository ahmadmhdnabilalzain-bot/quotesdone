import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { WorkedCase } from '@/components/WorkedCase';
import { AnonymityFlow } from '@/components/visual/slots';
import { PageHero, CtaPanel } from '@/components/DocFrame';
import { ComparisonReport, SealedQuote } from '@/components/visual/product';
import { Kicker, SectionHead } from '@/components/ui/sealed';
import { Button } from '@/components/ui/button';

// /how-it-works — the process distilled from the 150-answer FAQ, with the two-way anonymity table
// (website audit "Months" row). The worked-case slot renders only from a real closed deal.
// Founder, 14 Sep 2026: the top three are a technical comparison REPORT; every other quote is still
// listed and can be chosen. The hero shows that report (ComparisonReport, labelled sample), and the
// anonymity intro shows one quote sealed on arrival and the same quote opened once chosen.
type Step = { title: string; body: string };
type Row = { who: string; before: string; after: string };

const L = {
  en: { stepsKicker: 'The process', maskKicker: 'Anonymity', timeKicker: 'Timing', finalKicker: 'Start' },
  ar: { stepsKicker: 'المراحل', maskKicker: 'السرّية', timeKicker: 'المدد الزمنية', finalKicker: 'ابدأ' },
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
          aside={<ComparisonReport locale={lang} />}
        />

        <section className="container-x py-beat-s md:py-beat">
          <SectionHead kicker={x.stepsKicker} title={t('title')} className="sr-only" />
          <ol className="qd-stagger reveal-stagger grid gap-px overflow-hidden rounded-card border border-line bg-[var(--line)] md:grid-cols-2 lg:grid-cols-3">
            {steps.map((s, i) => (
              <li key={s.title} className="qd-lit group relative flex flex-col bg-navy p-7 md:p-8">
                <div className="flex items-center justify-between">
                  <span className="tabular font-mono text-[40px] font-medium leading-none text-teal-light/80">{String(i + 1).padStart(2, '0')}</span>
                  <span aria-hidden className="h-px flex-1 translate-y-1 bg-[linear-gradient(90deg,var(--line2),transparent)] ms-5 rtl:bg-[linear-gradient(270deg,var(--line2),transparent)]" />
                </div>
                <h2 className="mt-8 font-head text-h3 text-white">{s.title}</h2>
                <p className="mt-3 text-copy text-muted">{s.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="border-y border-line bg-navy-deep/40">
          <div className="container-x py-beat-s md:py-beat">
            <div className="grid items-center gap-10 lg:grid-cols-[1fr_auto]">
              <SectionHead kicker={x.maskKicker} title={t('maskTitle')} lead={t('maskSub')} />
              <div className="grid gap-4 sm:grid-cols-2 lg:w-[620px]">
                <SealedQuote locale={lang} />
                <SealedQuote locale={lang} open />
              </div>
            </div>
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
            <ol className="grid gap-4 md:grid-cols-3">
              {time.map((line, i) => (
                <li key={line} className="qd-panel qd-ticks relative p-6 pt-9">
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
