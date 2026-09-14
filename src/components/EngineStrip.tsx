import { useLocale, useTranslations } from 'next-intl';
import { Stagger, StaggerItem, Reveal } from '@/components/motion/reveal';
import { SectionHeader } from '@/components/SectionHeader';
import { DrawingScan, CompareLevelling } from '@/components/visual/slots';

type Item = { title: string; body: string };

// "WHAT THE ENGINE ACTUALLY DOES". The homepage asserted "smart" with a label and wrote the
// mechanisms only in FAQ answers reachable from the footer (website audit §1 finding 28). These are
// the four behaviours from the FAQ, stated where a contractor decides, plus the top-3 cap as a
// feature rather than a hidden rule.
export function EngineStrip() {
  const t = useTranslations('engine');
  const locale = useLocale();
  const items = t.raw('items') as Item[];
  return (
    <section id="engine" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="01" title={t('title')} sub={t('sub')} />
      <div className="relative mt-14 grid gap-5 lg:grid-cols-[1.35fr_1fr]">
        <Stagger className="relative grid gap-px overflow-hidden rounded-[22px] border border-[var(--line2)] bg-[var(--line)] sm:grid-cols-2">
          {items.map((it, i) => (
            <StaggerItem key={it.title} className="relative bg-navy-deep/90 p-7">
              <span className="grid-tech grid-tech-sm opacity-40" aria-hidden />
              <div className="relative flex items-center gap-2" aria-hidden>
                <span className="font-mono text-[12px] tabular text-teal-light">{String(i + 1).padStart(2, '0')}</span>
                <span className="h-px flex-1 bg-gradient-to-r from-teal/50 to-transparent rtl:bg-gradient-to-l" />
                {i === 1 && <span className="redact redact-bar !h-2.5 !w-14" />}
              </div>
              <h3 className="relative mt-5 font-head text-[19px] font-semibold leading-snug tracking-[-0.02em] text-white">{it.title}</h3>
              <p className="relative mt-2.5 text-pretty text-[14px] leading-relaxed text-muted">{it.body}</p>
            </StaggerItem>
          ))}
        </Stagger>

        <Reveal className="relative">
          <div className="glass depth mesh-glow relative flex h-full flex-col justify-between overflow-hidden rounded-[22px] p-8">
            <span className="grid-tech opacity-50" aria-hidden />
            <div className="relative mb-7 aspect-[16/10] w-full overflow-hidden rounded-[14px] empty:hidden">
              <DrawingScan locale={locale === 'ar' ? 'ar' : 'en'} />
            </div>
            <div className="relative">
              <div className="flex items-end gap-2" aria-hidden>
                {[0, 1, 2].map((i) => (
                  <span key={i} className="rounded-t-[6px] border border-teal/40 bg-teal/[0.12]" style={{ width: 34, height: 64 - i * 12 }} />
                ))}
                {Array.from({ length: 7 }).map((_, i) => (
                  <span key={`x${i}`} className="redact rounded-t-[4px]" style={{ width: 12, height: 18 + ((i * 7) % 16) }} />
                ))}
              </div>
              <h3 className="crisp mt-7 font-head text-[clamp(24px,2.6vw,32px)] font-semibold leading-[1.08] tracking-[-0.03em] text-white rtl:tracking-normal">
                {t('top3Title')}
              </h3>
              <p className="mt-3 max-w-[40ch] text-[14.5px] leading-relaxed text-muted">{t('top3Body')}</p>
            </div>
            <div className="relative mt-6 empty:hidden">
              <CompareLevelling locale={locale === 'ar' ? 'ar' : 'en'} />
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
