import { setRequestLocale, getTranslations } from 'next-intl/server';
import { buildMeta } from '@/lib/seo';
import { Link } from '@/i18n/routing';
import { SiteHeader } from '@/components/SiteHeader';
import { SiteFooter } from '@/components/SiteFooter';
import { Reveal, Stagger, StaggerItem } from '@/components/motion/primitives';
import { WorkedCase } from '@/components/WorkedCase';
import { AnonymityFlow } from '@/components/visual/slots';

// /how-it-works — the process distilled from the 150-answer FAQ, with the two-way anonymity table
// (website audit "Months" row). The worked-case slot renders only from a real closed deal.
type Step = { title: string; body: string };
type Row = { who: string; before: string; after: string };

export async function generateMetadata(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  const t = await getTranslations({ locale, namespace: 'howPage' });
  return buildMeta({ locale, path: '/how-it-works', title: t('metaTitle'), description: t('metaDesc') });
}

export default async function Page(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  setRequestLocale(locale);
  const t = await getTranslations({ locale, namespace: 'howPage' });
  const steps = t.raw('steps') as Step[];
  const rows = t.raw('rows') as Row[];
  const time = t.raw('time') as string[];
  return (
    <>
      <SiteHeader />
      <main id="main">
        <section className="bloom relative overflow-hidden">
          <span className="grid-tech" aria-hidden />
          <div className="container-x relative z-10 pb-12 pt-16 md:pt-24">
            <span className="font-mono text-[11px] uppercase tracking-[0.2em] text-teal-light rtl:tracking-normal">{t('kicker')}</span>
            <h1 className="crisp mt-4 max-w-[22ch] font-head text-[clamp(34px,5vw,60px)] font-semibold leading-[1.02] tracking-[-0.045em] text-white rtl:leading-[1.25] rtl:tracking-normal">
              {t('title')}
            </h1>
            <p className="mt-6 max-w-[62ch] text-[17px] leading-relaxed text-muted">{t('sub')}</p>
          </div>
        </section>

        <section className="container-x py-beat-s">
          <Stagger className="relative grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {steps.map((s, i) => (
              <StaggerItem key={s.title}>
                <article className="tile neon-edge relative h-full overflow-hidden rounded-[22px] border border-[var(--line2)] bg-navy-deep/50 p-7">
                  <span className="grid-tech grid-tech-sm opacity-50" aria-hidden />
                  <span className="relative flex h-12 w-12 items-center justify-center rounded-xl border border-[var(--line2)] font-head text-[18px] font-semibold text-teal-light">
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <h2 className="relative mt-5 font-head text-[19px] font-semibold text-white">{s.title}</h2>
                  <p className="relative mt-2.5 text-[14.5px] leading-relaxed text-muted">{s.body}</p>
                </article>
              </StaggerItem>
            ))}
          </Stagger>
        </section>

        <section className="container-x py-beat-s">
          <Reveal>
            <h2 className="font-head text-[clamp(26px,3vw,36px)] font-semibold tracking-[-0.03em] text-white">{t('maskTitle')}</h2>
            <p className="mt-3 max-w-[60ch] text-[15px] text-muted">{t('maskSub')}</p>
            <div className="mt-8 empty:hidden">
              <AnonymityFlow locale={locale} />
            </div>
            <div className="mt-8 overflow-x-auto rounded-[18px] border border-[var(--line2)]">
              <table className="w-full min-w-[640px] border-collapse text-start text-[14px]">
                <thead>
                  <tr className="bg-teal/[0.06]">
                    <th scope="col" className="w-[22%] px-5 py-3.5 text-start font-semibold text-faint" />
                    <th scope="col" className="px-5 py-3.5 text-start font-semibold text-teal-light">{t('before')}</th>
                    <th scope="col" className="px-5 py-3.5 text-start font-semibold text-gold">{t('after')}</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.who} className="border-t border-[var(--line)] bg-navy-deep/40">
                      <th scope="row" className="px-5 py-4 text-start font-head font-semibold text-white">{r.who}</th>
                      <td className="px-5 py-4 text-muted">
                        <span className="me-2 inline-block align-middle redact redact-bar !h-2 !w-8" aria-hidden />{r.before}
                      </td>
                      <td className="px-5 py-4 text-paper/90">{r.after}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Reveal>
        </section>

        <section className="container-x py-beat-s">
          <Reveal className="rounded-[22px] border border-[var(--line2)] bg-navy-deep/50 p-7 md:p-9">
            <h2 className="font-head text-[24px] font-semibold text-white">{t('timeTitle')}</h2>
            <ol className="mt-5 space-y-3">
              {time.map((x, i) => (
                <li key={x} className="flex gap-3 text-[15px] leading-relaxed text-paper/90">
                  <span className="font-mono text-[12px] text-teal-light">{String(i + 1).padStart(2, '0')}</span>{x}
                </li>
              ))}
            </ol>
          </Reveal>
        </section>

        <WorkedCase />

        <section className="container-x py-beat-s text-center">
          <h2 className="font-head text-[clamp(26px,3vw,38px)] font-semibold text-white">{t('finalTitle')}</h2>
          <Link href="/#brief" className="btn-key press mt-7 inline-flex rounded-full bg-teal px-8 py-4 text-[15.5px] font-bold text-[#04231F] hover:bg-[#1ED0BC]">
            {t('finalCta')}
          </Link>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
