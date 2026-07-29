import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal, Stagger, StaggerItem, TiltCard, SpringHover, Spotlight } from '@/components/motion/primitives';

function Stat({ n, l }: { n: string; l: string }) {
  return (
    <StaggerItem className="group h-full bg-navy-deep/50 px-6 py-6 transition-colors duration-300 hover:bg-teal-light/[0.035] md:px-8 md:py-7">
      <div className="font-mono text-[clamp(24px,2.6vw,32px)] font-semibold tabular text-white">{n}</div>
      <div className="mt-1.5 text-xs leading-snug text-faint">{l}</div>
      <span className="mt-4 block h-px w-8 bg-teal/40 transition-all duration-500 ease-expo group-hover:w-14 group-hover:bg-teal" />
    </StaggerItem>
  );
}

/** The engine instrument: not a fake browser window, a readout. */
function EnginePanel({ labels }: { labels: { brief: string; steps: string[]; hidden: string } }) {
  return (
    <div className="glass depth relative overflow-hidden rounded-[22px]">
      {/* a soft light sweep travels down the instrument — reads as "processing" */}
      <span className="qd-scan" aria-hidden />
      <div className="flex items-center gap-2.5 border-b border-[var(--line)] bg-teal-light/[0.03] px-5 py-3.5">
        <span className="qd-pulse h-1.5 w-1.5 rounded-full bg-teal" />
        <span className="font-mono text-[10px] font-medium uppercase tracking-[0.22em] text-faint">
          Smart Engine live
        </span>
        <span className="ml-auto font-mono text-[9.5px] tabular tracking-[0.16em] text-faint/70">
          ENGINE · v3
        </span>
      </div>
      <div className="flex gap-3 px-5 py-4">
        <span className="mt-0.5 shrink-0 rounded border border-[var(--line2)] px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.16em] text-teal-light">
          {labels.brief}
        </span>
        <p className="font-mono text-[12.5px] leading-relaxed text-paper/90">
          SPC flooring, 250 sqm villa in Dubai, supply &amp; install.
        </p>
      </div>
      <div className="px-5">
        {labels.steps.map((s, i) => (
          <div key={s} className="flex items-center gap-3 border-t border-[var(--line)] py-3.5">
            <span className="font-mono text-[10px] tabular text-faint">0{i + 1}</span>
            <span className="flex-1 text-[13.5px] text-paper/90">{s}</span>
            <span className="font-mono text-[9.5px] uppercase tracking-[0.14em] text-teal-light/70">done</span>
          </div>
        ))}
      </div>
      <div className="flex flex-col gap-2 border-t border-[var(--line)] px-5 py-4">
        {[
          { p: 'AED 26,800', best: false },
          { p: 'AED 24,500', best: true },
          { p: 'AED 29,200', best: false },
        ].map((r) => (
          <div
            key={r.p}
            className={`flex items-center gap-3 rounded-xl border px-4 py-3 ${
              r.best ? 'border-gold/40 bg-gold/[0.06] shadow-[0_10px_30px_-18px_rgba(227,192,101,.6)]' : 'border-[var(--line)] bg-teal-light/[0.02]'
            }`}
          >
            <span className="redact redact-sq !h-2 !w-2" aria-hidden />
            <span className="redact redact-bar !h-3 flex-1" aria-hidden />
            <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-faint">{labels.hidden}</span>
            <span className={`font-mono text-[14.5px] font-semibold tabular ${r.best ? 'text-gold' : 'text-white'}`}>
              {r.p}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function Hero() {
  const t = useTranslations('hero');
  return (
    <Spotlight className="bloom relative overflow-hidden">
      <span className="grid-tech" aria-hidden />
      <section className="container-x relative z-10 pb-[72px] pt-12 md:pb-[104px] md:pt-16">
        {/* technical status row — language-neutral instrument markers */}
        <div className="mb-10 flex items-center gap-4 font-mono text-[10px] uppercase tracking-[0.2em] text-faint/70">
          <span className="node-dot" aria-hidden />
          <span className="tabular">01 / MATCH</span>
          <span className="h-px flex-1 bg-[var(--line)]" />
          <span className="tabular hidden sm:inline">EST · 2024</span>
        </div>

        <div className="grid items-center gap-14 lg:grid-cols-[1.08fr_.92fr]">
          <Stagger>
            <StaggerItem>
              <span className="inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-3.5 py-1.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light">
                <span className="qd-pulse h-1.5 w-1.5 rounded-full bg-teal" />
                {t('badge')}
              </span>
            </StaggerItem>
            <StaggerItem>
              <h1 className="crisp mt-7 max-w-[15ch] font-head text-[clamp(42px,6vw,72px)] font-semibold leading-[0.98] tracking-[-0.045em] text-white">
                <span className="text-teal-light">{t('titleA')}</span> {t('titleB')}{' '}
                <em className="not-italic text-white">{t('titleEm')}</em>
              </h1>
            </StaggerItem>
            <StaggerItem>
              <p className="mt-7 max-w-[50ch] text-[clamp(16px,1.5vw,18.5px)] leading-relaxed text-muted">
                {t('subtitle')}
              </p>
            </StaggerItem>
            <StaggerItem>
              <div className="mt-9 flex flex-wrap items-center gap-3">
                <SpringHover className="rounded-full">
                  <Link
                    href="/me"
                    className="btn-key press rounded-full bg-teal px-7 py-4 text-[15.5px] font-bold text-[#04231F] shadow-[0_14px_38px_-14px_rgba(20,184,166,.7)] transition-colors duration-200 hover:bg-[#1ED0BC]"
                  >
                    {t('ctaPrimary')}
                  </Link>
                </SpringHover>
                <SpringHover className="rounded-full">
                  <Link
                    href="/portal"
                    className="press rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-7 py-4 text-[15.5px] font-semibold text-paper transition-colors duration-200 hover:border-teal hover:bg-teal/[0.07] hover:text-white"
                  >
                    {t('ctaSupplier')}
                  </Link>
                </SpringHover>
              </div>
            </StaggerItem>
          </Stagger>

          <Reveal delay={0.15} y={34}>
            <div className="qd-float relative">
              {/* HUD bracket frame around the live instrument */}
              <span className="corners absolute -inset-3 hidden md:block" aria-hidden />
              <TiltCard className="relative rounded-[22px]" max={9}>
                <EnginePanel
                  labels={{ brief: 'Brief', steps: ['Structuring', 'Matching', 'Anonymising'], hidden: 'hidden' }}
                />
              </TiltCard>
            </div>
          </Reveal>
        </div>

        {/* full-width glass readout strip — the stats promoted to an instrument panel */}
        <Reveal delay={0.1} y={26}>
          <div className="relative mt-14 md:mt-16">
            <span className="corners absolute -inset-2" aria-hidden />
            <Stagger className="depth grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-[var(--line)] bg-[var(--line)] sm:grid-cols-4">
              <Stat n={t('stat1n')} l={t('stat1l')} />
              <Stat n={t('stat2n')} l={t('stat2l')} />
              <Stat n={t('stat3n')} l={t('stat3l')} />
              <Stat n={t('stat4n')} l={t('stat4l')} />
            </Stagger>
          </div>
        </Reveal>
      </section>
    </Spotlight>
  );
}
