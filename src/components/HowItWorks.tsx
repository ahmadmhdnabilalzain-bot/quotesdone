import { useTranslations } from 'next-intl';
import { Reveal, Stagger, StaggerItem } from '@/components/motion/reveal';
import { SectionHeader } from '@/components/SectionHeader';
import { Link } from '@/i18n/routing';

type Step = { n: string; title: string; body: string };

export function HowItWorks() {
  const t = useTranslations('how');
  const steps = t.raw('steps') as Step[];
  return (
    <section id="how" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="03" title={t('title')} sub={t('sub')} />

      <div className="relative mt-14 md:mt-16">
        {/* the data beam threads the three steps on desktop */}
        <span className="beam left-[14%] right-[14%] top-9 hidden md:block" aria-hidden />
        <Stagger className="grid gap-4 md:grid-cols-3 md:gap-5">
          {steps.map((s) => (
            <StaggerItem key={s.n}>
              <article className="tile neon-edge group relative h-full overflow-hidden rounded-[22px] border border-[var(--line2)] bg-navy-deep/50 p-7 backdrop-blur-sm hover:border-teal/40 md:p-8">
                <span className="grid-tech grid-tech-sm opacity-60" aria-hidden />
                {/* index medallion sits on the beam */}
                <span className="relative z-10 flex h-[72px] w-[72px] items-center justify-center rounded-2xl border border-[var(--line2)] bg-navy-deep/80 font-head text-[26px] font-semibold text-teal-light shadow-[0_10px_30px_-16px_rgba(0,12,20,.9)]">
                  {s.n}
                  <span className="node-dot absolute -right-1 -top-1" aria-hidden />
                </span>
                <h3 className="relative mt-7 font-head text-[21px] font-semibold leading-snug tracking-[-0.02em] text-white">
                  {s.title}
                </h3>
                <p className="relative mt-3 text-pretty text-[14.5px] leading-relaxed text-muted">{s.body}</p>
                <span className="relative mt-7 block h-px w-10 bg-teal/40 transition-all duration-500 ease-expo group-hover:w-24 group-hover:bg-teal group-hover:shadow-[0_0_12px_rgba(110,231,212,.6)]" />
              </article>
            </StaggerItem>
          ))}
        </Stagger>
      </div>

      <Reveal className="mt-10 flex justify-center">
        <Link href="/how-it-works" className="text-[14.5px] font-semibold text-teal-light underline-offset-4 hover:underline">
          {t('more')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
        </Link>
      </Reveal>
      <Reveal className="mt-14 md:mt-16">
        <div className="divider-node" aria-hidden />
      </Reveal>
    </section>
  );
}
