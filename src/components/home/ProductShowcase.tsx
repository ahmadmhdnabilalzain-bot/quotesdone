import { useTranslations } from 'next-intl';
import { Link } from '@/i18n/routing';
import { SectionHeader } from '@/components/SectionHeader';
import { ProductFrame, Seal } from '@/components/ui/sealed';

// THE PRODUCT, SHOWN ON ONE SAMPLE JOB.
//
// A faux-live frame of the three things the platform does to every request: it reads the drawing
// (and blacks out the title block's contact fields), it levels the quotes into one comparison with
// the incomplete ones returned, and it opens only the quote the customer chooses. Every figure is
// fixed sample data and the frame says so twice ("Sample" in the bar, the note under it). It
// replaces the LiveMatch replay: no client JS, the final frame is the server HTML, and the two loops
// (qd-scan, the qd-seal loop) are foundation CSS that hold still until the first interaction.
type Row = { item: string; qty: string; conf: number };
type Quote = { id: string; total: string; items: string; days: string };

export function ProductShowcase() {
  const t = useTranslations('show');
  const rows = t.raw('rows') as Row[];
  const quotes = t.raw('quotes') as Quote[];
  const steps = t.raw('steps') as string[];

  return (
    <section id="how" className="container-x scroll-mt-20 py-beat-s md:py-beat-l">
      <SectionHeader
        eyebrow={t('eyebrow')}
        index="01"
        title={t('title')}
        sub={t('sub')}
        aside={
          <Link href="/how-it-works" className="text-[14.5px] font-semibold text-teal-light underline-offset-4 hover:underline">
            {t('more')} <span aria-hidden className="inline-block rtl:rotate-180">&rarr;</span>
          </Link>
        }
      />

      <ProductFrame className="reveal mt-14 md:mt-16" title={<span dir="ltr">quotesdone.com/me/requests/QD-24-0917</span>} sampleLabel={t('sample')}>
        {/* the brief */}
        <div className="flex flex-col gap-1 border-b border-line px-5 py-5 md:flex-row md:items-center md:justify-between md:px-7">
          <p className="font-head text-[17px] font-semibold tracking-snug text-white">{t('job')}</p>
          <p className="text-small text-faint">{t('jobMeta')}</p>
        </div>

        <ol className="grid lg:grid-cols-[1fr_1.05fr_1.2fr]">
          {/* 01 — the drawing is read and its contact block sealed */}
          <li className="border-b border-line p-5 md:p-7 lg:border-b-0 lg:border-e">
            <StepLabel n="01" label={steps[0]} />
            <div className="relative mt-5 h-[210px] overflow-hidden rounded-panel bg-navy-deep shadow-[inset_0_0_0_1px_rgba(110,231,212,.1)]">
              <svg viewBox="0 0 320 210" className="absolute inset-0 h-full w-full" fill="none" aria-hidden>
                <g stroke="rgba(110,231,212,.55)" strokeWidth="1.2">
                  <rect x="18" y="16" width="200" height="150" />
                  <path d="M18 86h86M104 16v70M104 118v48M150 86h68M150 86v30M18 128h40" />
                </g>
                <g stroke="rgba(110,231,212,.22)" strokeWidth="1">
                  <path d="M28 26h66v50H28zM114 26h94v50h-94zM160 96h48v60h-48zM28 96h66v24H28z" strokeDasharray="3 3" />
                  <path d="M18 176h200M18 172v8M218 172v8" />
                </g>
                <text x="118" y="190" fill="rgba(129,153,163,.9)" fontSize="9" fontFamily="monospace" textAnchor="middle">18.40 m</text>
                {/* title block: the contact fields are sealed */}
                <rect x="232" y="16" width="72" height="150" stroke="rgba(110,231,212,.3)" />
                <path d="M232 60h72M232 104h72M232 136h72" stroke="rgba(110,231,212,.2)" />
                <rect x="240" y="26" width="52" height="7" rx="1" fill="#1B3445" />
                <rect x="240" y="38" width="36" height="7" rx="1" fill="#1B3445" />
                <rect x="240" y="70" width="48" height="7" rx="1" fill="#1B3445" />
                <rect x="240" y="82" width="30" height="7" rx="1" fill="#1B3445" />
                <text x="240" y="122" fill="rgba(110,231,212,.7)" fontSize="8" fontFamily="monospace">GF · 1:100</text>
                <text x="240" y="152" fill="rgba(129,153,163,.9)" fontSize="8" fontFamily="monospace">A-101</text>
              </svg>
              <span className="qd-scan border-b border-teal-light/60" aria-hidden />
            </div>
            <p className="mt-4 flex items-center gap-2 text-small text-muted">
              <span className="redact redact-line w-8!" aria-hidden />
              {t('sealedNote')}
            </p>
          </li>

          {/* 02 — the BOQ, read with a confidence for every line */}
          <li className="border-b border-line p-5 md:p-7 lg:border-b-0 lg:border-e">
            <StepLabel n="02" label={steps[1]} />
            <table className="mt-5 w-full text-start text-small">
              <thead>
                <tr className="text-faint">
                  <th className="pb-2 text-start font-normal">{t('colItem')}</th>
                  <th className="pb-2 text-end font-normal">{t('colQty')}</th>
                  <th className="w-[34%] pb-2 text-end font-normal">{t('colConf')}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.item} className="border-t border-line">
                    <td className="py-2.5 pe-2 text-paper">{r.item}</td>
                    <td className="py-2.5 text-end font-mono text-[12.5px] text-muted" dir="ltr">{r.qty}</td>
                    <td className="py-2.5 ps-3">
                      <div className="flex items-center justify-end gap-2">
                        <span className="qd-meter block w-full max-w-[64px]">
                          <span className={r.conf < 90 ? 'bg-gold!' : undefined} style={{ width: `${r.conf}%` }} />
                        </span>
                        <span className="w-9 text-end font-mono text-label tabular text-muted" dir="ltr">{r.conf}%</span>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="mt-4 text-small text-muted">{t('lowConf')}</p>
          </li>

          {/* 03 — three anonymous quotes; the chosen one opens */}
          <li className="p-5 md:p-7">
            <StepLabel n="03" label={steps[2]} />
            <ul className="mt-5 space-y-2.5">
              {quotes.map((q, i) => {
                const chosen = i === 0;
                return (
                  <li
                    key={q.id}
                    className={`rounded-[14px] px-4 py-3.5 ${
                      chosen ? 'bg-gold/5 shadow-[inset_0_0_0_1px_rgba(227,192,101,.45)]' : 'bg-navy-deep/50 shadow-[inset_0_0_0_1px_rgba(110,231,212,.1)]'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full font-mono text-label ${chosen ? 'bg-gold text-[#2a2107]' : 'text-faint shadow-[inset_0_0_0_1px_rgba(110,231,212,.2)]'}`}>
                        {i + 1}
                      </span>
                      <div className="min-w-0 flex-1">
                        {chosen ? (
                          <Seal loop className="qd-revealed text-[13.5px] font-semibold">{t('revealed')}</Seal>
                        ) : (
                          <span className="redact redact-line w-[150px]! text-[18px]" aria-hidden />
                        )}
                        <span className="mt-1 block font-mono text-[11.5px] text-faint" dir="ltr">{q.id} · {q.items} · {q.days}</span>
                      </div>
                      <span className={`shrink-0 font-mono text-[15px] font-medium tabular ${chosen ? 'text-white' : 'text-muted'}`} dir="ltr">AED {q.total}</span>
                    </div>
                  </li>
                );
              })}
            </ul>
            {/* the top 3 are the comparison report; every other quote is listed too (founder rule) */}
            <p className="mt-2.5 text-[12.5px] text-teal-light">{t('moreListed')}</p>
            <p className="mt-3 flex items-start gap-2 text-[12.5px] leading-relaxed text-muted">
              <span className="mt-[3px] shrink-0 rounded-[4px] bg-gold/10 px-1.5 font-mono text-[11px] text-gold" dir="ltr">2</span>
              {t('rejected')}
            </p>
            <span className="mt-5 flex w-full items-center justify-center rounded-full bg-gold px-5 py-3 text-[14px] font-bold text-[#2a2107]">
              {t('revealCta')}
            </span>
          </li>
        </ol>
        <p className="border-t border-line px-5 py-3.5 text-[12.5px] text-faint md:px-7">{t('note')}</p>
      </ProductFrame>
    </section>
  );
}

function StepLabel({ n, label }: { n: string; label: string }) {
  return (
    <div className="flex items-center gap-3">
      <span className="font-mono text-label tabular text-teal-light">{n}</span>
      <span className="text-[14px] font-semibold text-white">{label}</span>
      <span className="h-px flex-1 bg-linear-to-r from-teal/40 to-transparent rtl:bg-linear-to-l" aria-hidden />
    </div>
  );
}
