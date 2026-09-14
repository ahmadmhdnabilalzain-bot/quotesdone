import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SectionHeader } from '@/components/SectionHeader';
import { Arrow } from '@/components/HeroCtas';
import s from '@/components/home/sealed.module.css';

// Paired "For customers / For suppliers" (website audit ADOPT 3). Teal is the customer's side; the
// supplier side is set in paper — gold is reserved for the reveal and is not used here.
type Side = { kicker: string; title: string; bullets: string[]; cta: string };

function Block({ s: side, href, primary }: { s: Side; href: string; primary: boolean }) {
  return (
    <div className={`${s.shell} ${s.rise} h-full`}>
      <div className={`${s.core} flex h-full flex-col p-7 md:p-10`}>
        <span className={`${s.eyebrow} ${primary ? 'text-teal-light' : 'text-paper/80'}`}>{side.kicker}</span>
        <h3 className="mt-5 text-balance font-head text-[clamp(24px,2.6vw,34px)] font-semibold leading-[1.08] tracking-[-0.035em] text-white rtl:leading-[1.35] rtl:tracking-normal">
          {side.title}
        </h3>
        <ol className="mt-8 flex-1 divide-y divide-[var(--line)] border-y border-[var(--line)]">
          {side.bullets.map((b, i) => (
            <li key={b} className="flex gap-4 py-3.5 text-[14.5px] leading-relaxed text-paper/90">
              <span className="mt-[3px] w-5 shrink-0 font-mono text-[12px] tabular text-faint">{String(i + 1).padStart(2, '0')}</span>
              {b}
            </li>
          ))}
        </ol>
        <Link
          href={href}
          className={`group press mt-9 inline-flex w-fit items-center gap-3 rounded-full py-2 pe-2 ps-6 text-[14.5px] font-bold transition-colors duration-300 ${
            primary ? 'bg-teal text-[#04231F] hover:bg-[#1ED0BC]' : 'text-paper shadow-[inset_0_0_0_1px_rgba(238,246,244,.3)] hover:text-white hover:shadow-[inset_0_0_0_1px_rgba(238,246,244,.6)]'
          }`}
        >
          {side.cta}
          <span className={s.arrowDot}><Arrow /></span>
        </Link>
      </div>
    </div>
  );
}

export function TwoSided() {
  const t = useTranslations('sides');
  return (
    <section id="sides" className="container-x py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="03" title={t('title')} />
      <div className="mt-14 grid gap-5 md:mt-16 md:grid-cols-2">
        <Block s={t.raw('customers') as Side} href="/me" primary />
        <Block s={t.raw('suppliers') as Side} href="/supplier" primary={false} />
      </div>
    </section>
  );
}
