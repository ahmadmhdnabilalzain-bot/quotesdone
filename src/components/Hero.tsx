import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal, Stagger, StaggerItem, SpringHover, Spotlight } from '@/components/motion/primitives';
import { LiveMatch } from '@/components/LiveMatch';

type Proof = { k: string; v: string };

export function Hero() {
  const t = useTranslations('hero');
  const proof = t.raw('proof') as Proof[];
  const ticker = [...proof, ...proof];

  return (
    <Spotlight className="bloom relative overflow-hidden" size={620}>
      <span className="grid-tech" aria-hidden />
      <section className="container-x relative z-10 pb-16 pt-16 md:pb-20 md:pt-24">
        {/* headline block */}
        <Stagger className="mx-auto flex max-w-[760px] flex-col items-center text-center">
          <StaggerItem>
            <span className="inline-flex items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-4 py-1.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light backdrop-blur-sm">
              <span className="qd-pulse h-1.5 w-1.5 rounded-full bg-teal" />
              {t('badge')}
            </span>
          </StaggerItem>
          <StaggerItem>
            <h1 className="crisp mt-8 font-head text-[clamp(40px,7vw,84px)] font-semibold leading-[0.94] tracking-[-0.05em] text-white">
              {t('titleA')}{' '}
              <span className="text-brand-grad">
                {t('titleB')} {t('titleEm')}
              </span>
            </h1>
          </StaggerItem>
          <StaggerItem>
            <p className="mt-7 max-w-[52ch] text-pretty text-[clamp(16px,1.7vw,19px)] leading-relaxed text-muted">
              {t('subtitle')}
            </p>
          </StaggerItem>
          <StaggerItem>
            <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
              <SpringHover className="rounded-full">
                <Link
                  href="/me"
                  className="btn-key press rounded-full bg-teal px-8 py-4 text-[15.5px] font-bold text-[#04231F] shadow-[0_16px_44px_-16px_rgba(20,184,166,.8)] transition-colors duration-200 hover:bg-[#1ED0BC]"
                >
                  {t('ctaPrimary')}
                </Link>
              </SpringHover>
              <SpringHover className="rounded-full">
                <Link
                  href="/portal"
                  className="press rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-8 py-4 text-[15.5px] font-semibold text-paper transition-colors duration-200 hover:border-teal hover:bg-teal/[0.07] hover:text-white"
                >
                  {t('ctaSupplier')}
                </Link>
              </SpringHover>
            </div>
          </StaggerItem>
        </Stagger>

        {/* the engine — the star of the page, on a rotating conic halo */}
        <Reveal delay={0.15} y={40} className="relative mx-auto mt-16 max-w-[560px] md:mt-20">
          <span
            className="halo left-1/2 top-1/2 h-[120%] w-[120%] -translate-x-1/2 -translate-y-1/2"
            aria-hidden
          />
          <div className="qd-float relative">
            <span className="corners absolute -inset-3 hidden sm:block" aria-hidden />
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
      </section>

      {/* honest coverage ticker — real facts, no invented counts, seamless loop */}
      <Reveal className="relative z-10 border-y border-[var(--line)] bg-navy-deep/40 py-5 backdrop-blur-sm">
        <div className="relative overflow-hidden [mask-image:linear-gradient(90deg,transparent,#000_8%,#000_92%,transparent)]">
          <div className="marquee items-center gap-0">
            {ticker.map((p, i) => (
              <span key={i} className="flex items-center gap-3 whitespace-nowrap px-7">
                <span className="node-dot" aria-hidden />
                <span className="font-head text-[15px] font-semibold tracking-[-0.01em] text-white">
                  {p.k}
                </span>
                <span className="text-[14px] text-faint">{p.v}</span>
              </span>
            ))}
          </div>
        </div>
      </Reveal>
    </Spotlight>
  );
}
