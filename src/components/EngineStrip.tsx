import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SectionHeader } from '@/components/SectionHeader';
import s from '@/components/home/sealed.module.css';

// THE SIX RULES, AS A BENTO.
//
// The mechanisms used to live in two sections (four "engine" cards and four "why anonymous" cards)
// and in FAQ answers (website audit §1 finding 28). They are now one grid, each cell carrying a small
// drawing of the rule itself rather than an icon: the identity bars, the licence fields read, the
// shortlist of three against the crowd, the returned quote, the 3%, and the five-day refund clock.
// Anchor #why is kept: the header's "Why anonymous" links to /#why.
type Cell = { title: string; body: string };

export function EngineStrip() {
  const t = useTranslations('engine');
  const tv = useTranslations('verify');
  const c = t.raw('cells') as Cell[];
  const checks = t.raw('checks') as string[];
  const licence = t.raw('licence') as string[];

  return (
    <section id="why" className="container-x scroll-mt-20 py-beat-s md:py-beat">
      <SectionHeader eyebrow={t('eyebrow')} index="02" title={t('title')} sub={t('sub')} />

      <div className="mt-14 grid gap-4 md:mt-16 md:grid-cols-6">
        {/* 1 identity stripped — wide */}
        <Cell className="md:col-span-4" title={c[0].title} body={c[0].body}>
          <div className="rounded-[12px] bg-[#07121a] p-4 shadow-[inset_0_0_0_1px_rgba(110,231,212,.1)]">
            <div className="grid gap-2.5 text-[13px] sm:grid-cols-[auto_1fr] sm:gap-x-6">
              {(t.raw('brief') as string[][]).map(([k, v, sealed]) => (
                <div key={k} className="contents">
                  <span className="font-mono text-[11.5px] uppercase tracking-[0.12em] text-faint rtl:font-sans rtl:tracking-normal">{k}</span>
                  {sealed ? <span className={`${s.seal} w-[min(180px,60%)] text-[18px]`} aria-hidden /> : <span className="text-paper">{v}</span>}
                </div>
              ))}
            </div>
          </div>
        </Cell>

        {/* 2 licence verified */}
        <Cell className="md:col-span-2" title={c[1].title} body={c[1].body}
          foot={<Link href="/how-we-verify" className="text-[13.5px] font-semibold text-teal-light underline-offset-4 hover:underline">{tv('link')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span></Link>}>
          <ul className="space-y-2">
            {licence.map((l) => (
              <li key={l} className="flex items-center gap-2.5 text-[13px] text-paper">
                <Tick />{l}
              </li>
            ))}
          </ul>
        </Cell>

        {/* 3 top three, not thirty */}
        <Cell className="md:col-span-2" title={c[2].title} body={c[2].body}>
          <div className="flex h-[76px] items-end gap-1.5" aria-hidden>
            {[64, 54, 46].map((h) => (
              <span key={h} className="w-7 rounded-t-[5px] bg-teal/20 shadow-[inset_0_0_0_1px_rgba(20,184,166,.55)]" style={{ height: h }} />
            ))}
            {Array.from({ length: 9 }).map((_, i) => (
              <span key={i} className="w-2.5 rounded-t-[2px] bg-[#1B3445]" style={{ height: 14 + ((i * 7) % 18) }} />
            ))}
          </div>
        </Cell>

        {/* 4 incomplete quotes returned */}
        <Cell className="md:col-span-2" title={c[3].title} body={c[3].body}>
          <ul className="space-y-1.5 text-[13px]">
            {checks.map((k, i) => {
              const missing = i === checks.length - 1;
              return (
                <li key={k} className="flex items-center justify-between gap-3 border-b border-[var(--line)] pb-1.5 last:border-0">
                  <span className={missing ? 'text-gold' : 'text-paper'}>{k}</span>
                  {missing ? <span className="font-mono text-[11.5px] text-gold">{t('returned')}</span> : <Tick />}
                </li>
              );
            })}
          </ul>
        </Cell>

        {/* 5 three percent to reveal — the one gold number on the page */}
        <Cell className="md:col-span-2" title={c[4].title} body={c[4].body}>
          <div className="flex items-baseline gap-3">
            <span className="font-head text-[76px] font-semibold leading-none tracking-[-0.06em] text-gold tabular" dir="ltr">3%</span>
            <span className="max-w-[16ch] text-[13px] leading-snug text-muted">{t('pctNote')}</span>
          </div>
        </Cell>

        {/* 6 refund if the supplier stays silent — full width */}
        <Cell className="md:col-span-6" title={c[5].title} body={c[5].body} row>
          <div className="w-full">
            <div className="flex items-center gap-1.5" aria-hidden>
              {[1, 2, 3, 4, 5].map((d) => (
                <span key={d} className="h-9 flex-1 rounded-[6px] bg-navy-deep/60 shadow-[inset_0_0_0_1px_rgba(110,231,212,.14)]" />
              ))}
              <span className="flex h-9 flex-[1.6] items-center justify-center rounded-[6px] bg-teal/15 font-mono text-[12px] text-teal-light shadow-[inset_0_0_0_1px_rgba(20,184,166,.5)] rtl:font-sans">
                {t('refund')}
              </span>
            </div>
            <div className="mt-2 flex justify-between font-mono text-[11.5px] text-faint rtl:font-sans">
              <span>{t('day1')}</span><span>{t('day5')}</span>
            </div>
          </div>
        </Cell>
      </div>
    </section>
  );
}

function Cell({ className = '', title, body, children, foot, row = false }: {
  className?: string; title: string; body: string; children: React.ReactNode; foot?: React.ReactNode; row?: boolean;
}) {
  return (
    <article className={`${s.cell} ${s.rise} flex flex-col gap-7 p-6 md:p-8 ${row ? 'lg:flex-row lg:items-center lg:gap-14' : ''} ${className}`}>
      <div className={row ? 'order-2 lg:order-1 lg:w-1/2' : ''}>{children}</div>
      <div className={`mt-auto ${row ? 'order-1 lg:order-2 lg:mt-0 lg:w-1/2' : ''}`}>
        <h3 className="text-balance font-head text-[21px] font-semibold leading-snug tracking-[-0.025em] text-white rtl:tracking-normal">{title}</h3>
        <p className="mt-2.5 max-w-[48ch] text-pretty text-[14.5px] leading-relaxed text-muted">{body}</p>
        {foot ? <div className="mt-4">{foot}</div> : null}
      </div>
    </article>
  );
}

function Tick() {
  return (
    <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="#6EE7D4" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0" aria-hidden>
      <path d="M3.5 8.5l3 3 6-7" />
    </svg>
  );
}
