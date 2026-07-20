import { useTranslations } from 'next-intl';

type Step = { n: string; title: string; body: string };

export function HowItWorks() {
  const t = useTranslations('how');
  const steps = t.raw('steps') as Step[];
  return (
    <section id="how" className="container-x py-beat-s md:py-beat">
      <div className="reveal grid gap-6 border-t border-[var(--line)] pt-10 md:grid-cols-[minmax(0,.92fr)_minmax(0,1.08fr)] md:gap-14">
        <div>
          <p className="font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light">
            {t('eyebrow')}
          </p>
          <h2 className="mt-4 max-w-[14ch] text-balance font-head text-[clamp(28px,3.4vw,44px)] font-semibold leading-[1.08] tracking-[-0.035em] text-white">
            {t('title')}
          </h2>
        </div>
        <p className="max-w-[58ch] self-end text-pretty text-[16.5px] leading-relaxed text-muted">
          {t('sub')}
        </p>
      </div>

      {/* A real ordered sequence: the numbers carry information. */}
      <ol className="mt-12 grid gap-px overflow-hidden rounded-[22px] border border-[var(--line)] bg-[var(--line)] md:grid-cols-3">
        {steps.map((s, i) => (
          <li
            key={s.n}
            className="reveal group relative bg-navy-deep/60 p-7 transition-colors duration-300 hover:bg-teal-light/[0.035] md:p-8"
            style={{ transitionDelay: `${i * 70}ms` }}
          >
            <span className="font-mono text-[11px] font-semibold tabular tracking-[0.18em] text-teal-light/70">
              {s.n}
            </span>
            <h3 className="mt-4 font-head text-[19px] font-semibold leading-snug tracking-[-0.015em] text-white">
              {s.title}
            </h3>
            <p className="mt-3 max-w-[42ch] text-pretty text-[14.5px] leading-relaxed text-muted">{s.body}</p>
            <span className="mt-6 block h-px w-10 bg-teal/40 transition-all duration-500 ease-expo group-hover:w-20 group-hover:bg-teal" />
          </li>
        ))}
      </ol>
    </section>
  );
}
