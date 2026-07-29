import { useTranslations } from 'next-intl';
import { Reveal } from '@/components/motion/primitives';

type Step = { n: string; title: string; body: string };

export function HowItWorks() {
  const t = useTranslations('how');
  const steps = t.raw('steps') as Step[];
  return (
    <section id="how" className="container-x py-beat-s md:py-beat">
      {/* indexed technical header */}
      <Reveal className="border-t border-[var(--line)] pt-10">
        <div className="flex items-center gap-4 font-mono text-[10.5px] uppercase tracking-[0.2em] text-teal-light">
          <span className="node-dot" aria-hidden />
          <span>{t('eyebrow')}</span>
          <span className="tabular ml-auto text-faint/60">02</span>
        </div>
        <div className="mt-6 grid gap-6 md:grid-cols-[minmax(0,.92fr)_minmax(0,1.08fr)] md:gap-14">
          <h2 className="crisp max-w-[14ch] text-balance font-head text-[clamp(28px,3.6vw,46px)] font-semibold leading-[1.05] tracking-[-0.04em] text-white">
            {t('title')}
          </h2>
          <p className="max-w-[58ch] self-end text-pretty text-[16.5px] leading-relaxed text-muted">
            {t('sub')}
          </p>
        </div>
      </Reveal>

      {/* A connected sequence: a rail threads the steps, numbers carry order. */}
      <Reveal delay={0.1} y={30}>
        <ol className="relative mt-12 grid gap-px overflow-hidden rounded-[22px] border border-[var(--line)] bg-[var(--line)] depth md:grid-cols-3">
          <span className="rail top-0 z-10 hidden md:block" aria-hidden />
          {steps.map((s, i) => (
            <li
              key={s.n}
              className="group relative overflow-hidden bg-navy-deep/60 p-7 transition-all duration-300 hover:bg-teal-light/[0.045] md:p-9"
              style={{ transitionDelay: `${i * 60}ms` }}
            >
              {/* oversized ghost numeral — depth without ornament */}
              <span
                aria-hidden
                className="pointer-events-none absolute -right-3 -top-6 select-none font-head text-[130px] font-bold leading-none tracking-tighter text-teal-light/[0.045] transition-colors duration-500 group-hover:text-teal-light/[0.08]"
              >
                {s.n}
              </span>
              <span className="relative flex items-center gap-2.5">
                <span className="node-dot" aria-hidden />
                <span className="font-mono text-[12px] font-semibold tabular tracking-[0.18em] text-teal-light/80">
                  {s.n}
                </span>
              </span>
              <h3 className="relative mt-6 font-head text-[20px] font-semibold leading-snug tracking-[-0.015em] text-white">
                {s.title}
              </h3>
              <p className="relative mt-3 max-w-[42ch] text-pretty text-[14.5px] leading-relaxed text-muted">{s.body}</p>
              <span className="relative mt-7 block h-px w-10 bg-teal/40 transition-all duration-500 ease-expo group-hover:w-24 group-hover:bg-teal group-hover:shadow-[0_0_12px_rgba(110,231,212,.6)]" />
            </li>
          ))}
        </ol>
      </Reveal>
    </section>
  );
}
