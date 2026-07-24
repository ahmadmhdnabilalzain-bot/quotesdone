import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal, TiltCard, SpringHover } from '@/components/motion/primitives';

export function CtaBand() {
  const t = useTranslations();
  return (
    <section className="container-x py-beat-s md:py-beat">
      <Reveal y={30}>
        <TiltCard className="neon-edge mesh-glow relative rounded-[26px]" max={4} glow={false}>
          <div className="glass depth relative overflow-hidden rounded-[26px] px-7 py-12 text-center md:px-16 md:py-16">
            <div
              aria-hidden
              className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-teal/45 to-transparent"
            />
            <p className="font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light">
              {t('cta.eyebrow')}
            </p>
            <h2 className="crisp mx-auto mt-5 max-w-[19ch] text-balance font-head text-[clamp(28px,3.6vw,46px)] font-semibold leading-[1.07] tracking-[-0.035em] text-white">
              {t('cta.title')}
            </h2>
            <p className="mx-auto mt-5 max-w-[56ch] text-pretty text-[16.5px] leading-relaxed text-muted">
              {t('cta.sub')}
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
              <SpringHover className="rounded-full">
                <Link
                  href="/me"
                  className="btn-key rounded-full bg-teal px-7 py-4 text-[15.5px] font-bold text-[#04231F] shadow-[0_14px_38px_-14px_rgba(20,184,166,.7)] transition-colors duration-200 hover:bg-[#1ED0BC]"
                >
                  {t('hero.ctaPrimary')}
                </Link>
              </SpringHover>
              <SpringHover className="rounded-full">
                <Link
                  href="/portal"
                  className="rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-7 py-4 text-[15.5px] font-semibold text-paper transition-colors duration-200 hover:border-teal hover:bg-teal/[0.07] hover:text-white"
                >
                  {t('cta.supplier')}
                </Link>
              </SpringHover>
            </div>
          </div>
        </TiltCard>
      </Reveal>
    </section>
  );
}
