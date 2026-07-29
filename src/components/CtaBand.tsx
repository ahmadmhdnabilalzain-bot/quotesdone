import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal, SpringHover } from '@/components/motion/primitives';

export function CtaBand() {
  const t = useTranslations();
  return (
    <section className="container-x py-beat-s md:py-beat">
      <Reveal y={34}>
        <div className="relative">
          <span className="corners absolute -inset-3 hidden md:block" aria-hidden />
          <div className="glass depth relative isolate overflow-hidden rounded-[28px] px-7 py-16 text-center md:px-16 md:py-24">
            <span className="grid-tech" aria-hidden />
            <span
              className="halo left-1/2 top-1/2 h-[520px] w-[520px] -translate-x-1/2 -translate-y-1/2 opacity-80"
              aria-hidden
            />
            <div
              aria-hidden
              className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-teal/60 to-transparent"
            />
            <span className="relative mx-auto mb-7 flex w-fit items-center gap-2.5 rounded-full border border-[var(--line2)] bg-teal-light/[0.04] px-4 py-1.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-teal-light backdrop-blur-sm">
              <span className="node-dot" aria-hidden />
              {t('cta.eyebrow')}
            </span>
            <h2 className="crisp relative mx-auto max-w-[18ch] text-balance font-head text-[clamp(32px,5vw,58px)] font-semibold leading-[1.0] tracking-[-0.045em] text-white">
              {t('cta.title')}
            </h2>
            <p className="relative mx-auto mt-6 max-w-[54ch] text-pretty text-[clamp(15.5px,1.7vw,18px)] leading-relaxed text-muted">
              {t('cta.sub')}
            </p>
            <div className="relative mt-11 flex flex-wrap items-center justify-center gap-3">
              <SpringHover className="rounded-full">
                <Link
                  href="/me"
                  className="btn-key press rounded-full bg-teal px-9 py-4 text-[16px] font-bold text-[#04231F] shadow-[0_16px_44px_-16px_rgba(20,184,166,.85)] transition-colors duration-200 hover:bg-[#1ED0BC]"
                >
                  {t('hero.ctaPrimary')}
                </Link>
              </SpringHover>
              <SpringHover className="rounded-full">
                <Link
                  href="/portal"
                  className="press rounded-full border border-[var(--line2)] bg-teal-light/[0.03] px-9 py-4 text-[16px] font-semibold text-paper transition-colors duration-200 hover:border-teal hover:bg-teal/[0.07] hover:text-white"
                >
                  {t('cta.supplier')}
                </Link>
              </SpringHover>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
