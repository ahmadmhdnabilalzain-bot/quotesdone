import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';

function Stat({ n, l }: { n: string; l: string }) {
  return (
    <div>
      <div className="font-mono text-[26px] font-semibold tabular text-white">{n}</div>
      <div className="mt-1 text-xs leading-snug text-faint">{l}</div>
    </div>
  );
}

/** The engine instrument: not a fake browser window, a readout. */
function EnginePanel({ labels }: { labels: { brief: string; steps: string[]; hidden: string } }) {
  return (
    <div className="surface relative overflow-hidden rounded-[22px] shadow-[0_40px_100px_-55px_rgba(0,12,20,.95)]">
      <div className="flex items-center gap-2.5 border-b border-[var(--line)] bg-teal-light/[0.03] px-5 py-3.5">
        <span className="h-1.5 w-1.5 rounded-full bg-teal shadow-[0_0_0_3px_rgba(20,184,166,.18)]" />
        <span className="font-mono text-[10px] font-medium uppercase tracking-[0.22em] text-faint">
          Smart Engine live
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
              r.best ? 'border-gold/40 bg-gold/[0.06]' : 'border-[var(--line)] bg-teal-light/[0.02]'
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
    <section className="container-x pb-[72px] pt-14 md:pb-[104px] md:pt-20">
      <div className="grid items-center gap-14 lg:grid-cols-[1.06fr_.94fr]">
        <div>
          <span className="inline-flex items-center gap-2.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light">
            <span className="h-1.5 w-1.5 rounded-full bg-teal shadow-[0_0_0_0_rgba(20,184,166,.6)]" />
            {t('badge')}
          </span>
          <h1 className="mt-6 max-w-[16ch] font-head text-[clamp(38px,5.2vw,62px)] font-semibold leading-[1.04] tracking-[-0.04em] text-white">
            <span className="text-teal-light">{t('titleA')}</span> {t('titleB')}{' '}
            <em className="not-italic text-white">{t('titleEm')}</em>
          </h1>
          <p className="mt-6 max-w-[52ch] text-[clamp(16px,1.5vw,18px)] leading-relaxed text-muted">
            {t('subtitle')}
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Link
              href="/me"
              className="btn-key rounded-full bg-teal px-7 py-4 text-[15.5px] font-bold text-[#04231F] shadow-[0_14px_38px_-14px_rgba(20,184,166,.7)] transition-colors duration-200 hover:bg-[#1ED0BC]"
            >
              {t('ctaPrimary')}
            </Link>
            <Link
              href="/portal"
              className="rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-7 py-4 text-[15.5px] font-semibold text-paper transition-colors duration-200 hover:border-teal hover:bg-teal/[0.07] hover:text-white"
            >
              {t('ctaSupplier')}
            </Link>
          </div>
          <div className="mt-12 grid max-w-xl grid-cols-2 gap-8 sm:grid-cols-4">
            <Stat n={t('stat1n')} l={t('stat1l')} />
            <Stat n={t('stat2n')} l={t('stat2l')} />
            <Stat n={t('stat3n')} l={t('stat3l')} />
            <Stat n={t('stat4n')} l={t('stat4l')} />
          </div>
        </div>
        <EnginePanel
          labels={{ brief: 'Brief', steps: ['Structuring', 'Matching', 'Anonymising'], hidden: 'hidden' }}
        />
      </div>
    </section>
  );
}
