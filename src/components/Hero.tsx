import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal, Stagger, StaggerItem, SpringHover, Spotlight } from '@/components/motion/primitives';
import { BrandMark } from '@/components/BrandMark';
import { LiveMatch } from '@/components/LiveMatch';

type Proof = { k: string; v: string };

export function Hero() {
  const t = useTranslations('hero');
  const proof = t.raw('proof') as Proof[];

  return (
    <Spotlight className="bloom relative overflow-hidden">
      <span className="grid-tech" aria-hidden />
      <section className="container-x relative z-10 pb-[72px] pt-14 md:pb-[104px] md:pt-20">
        <div className="grid items-center gap-14 lg:grid-cols-[1.02fr_.98fr]">
          <Stagger>
            <StaggerItem>
              <span className="inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-3.5 py-1.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light">
                <span className="qd-pulse h-1.5 w-1.5 rounded-full bg-teal" />
                {t('badge')}
              </span>
            </StaggerItem>
            <StaggerItem>
              <h1 className="crisp mt-7 max-w-[15ch] font-head text-[clamp(44px,6.4vw,76px)] font-semibold leading-[0.96] tracking-[-0.045em] text-white">
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
              <span className="corners absolute -inset-3 hidden md:block" aria-hidden />
              <LiveMatch
                labels={{
                  live: t('live'),
                  posted: t('posted'),
                  competing: t('competing'),
                  sorting: t('sorting'),
                  best: t('best'),
                  hidden: t('hidden'),
                  reveal: t('reveal'),
                  brief: t('briefText'),
                }}
              />
            </div>
          </Reveal>
        </div>

        {/* honest trust bar — real facts, no invented counts */}
        <Reveal delay={0.1} y={26}>
          <Stagger className="mt-14 grid grid-cols-2 gap-px overflow-hidden rounded-[20px] border border-[var(--line)] bg-[var(--line)] md:mt-16 lg:grid-cols-4">
            {proof.map((p) => (
              <StaggerItem
                key={p.k}
                className="group h-full bg-navy-deep/50 px-6 py-6 transition-colors duration-300 hover:bg-teal-light/[0.035] md:px-8 md:py-7"
              >
                <div className="font-head text-[clamp(18px,1.9vw,22px)] font-semibold tracking-[-0.02em] text-white">
                  {p.k}
                </div>
                <div className="mt-1.5 text-[13px] leading-snug text-faint">{p.v}</div>
                <span className="mt-4 block h-px w-8 bg-teal/40 transition-all duration-500 ease-expo group-hover:w-14 group-hover:bg-teal" />
              </StaggerItem>
            ))}
          </Stagger>
        </Reveal>
      </section>
    </Spotlight>
  );
}
