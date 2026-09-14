import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { Reveal } from '@/components/motion/primitives';
import { SectionHeader } from '@/components/SectionHeader';

// Paired "For customers / For suppliers" blocks (website audit ADOPT 3). The supplier half of the
// marketplace had one secondary button on the homepage and no argument behind it.
type Side = { kicker: string; title: string; bullets: string[]; cta: string };

function Block({ s, href, tone }: { s: Side; href: string; tone: 'teal' | 'gold' }) {
  const accent = tone === 'teal' ? 'text-teal-light' : 'text-gold';
  const dot = tone === 'teal' ? 'bg-teal' : 'bg-gold';
  return (
    <div className="glass depth neon-edge relative flex h-full flex-col overflow-hidden rounded-[22px] p-7 md:p-9">
      <span className="grid-tech grid-tech-sm opacity-40" aria-hidden />
      <span className={`relative font-mono text-[11px] font-medium uppercase tracking-[0.2em] ${accent} rtl:tracking-normal`}>{s.kicker}</span>
      <h3 className="crisp relative mt-4 text-balance font-head text-[clamp(22px,2.4vw,30px)] font-semibold leading-[1.1] tracking-[-0.03em] text-white rtl:tracking-normal">
        {s.title}
      </h3>
      <ul className="relative mt-6 flex-1 space-y-3.5">
        {s.bullets.map((b) => (
          <li key={b} className="flex gap-3 text-[14.5px] leading-relaxed text-paper/90">
            <span className={`mt-[9px] h-1.5 w-1.5 shrink-0 rounded-full ${dot}`} aria-hidden />
            {b}
          </li>
        ))}
      </ul>
      <Link
        href={href}
        className={`press relative mt-8 inline-flex w-fit rounded-full px-6 py-3 text-[14.5px] font-bold transition-colors ${
          tone === 'teal' ? 'btn-key bg-teal text-[#04231F] hover:bg-[#1ED0BC]' : 'border border-gold/50 text-gold hover:bg-gold/[0.08]'}`}
      >
        {s.cta}
      </Link>
    </div>
  );
}

export function TwoSided() {
  const t = useTranslations('sides');
  return (
    <section id="sides" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="02" title={t('title')} />
      <Reveal className="mt-14 grid gap-5 md:grid-cols-2">
        <Block s={t.raw('customers') as Side} href="/me" tone="teal" />
        <Block s={t.raw('suppliers') as Side} href="/supplier" tone="gold" />
      </Reveal>
    </section>
  );
}
