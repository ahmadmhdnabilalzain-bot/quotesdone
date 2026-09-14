'use client';

// THE ENGINE CARD, AS A DEMONSTRATION OF THE REAL ENGINE.
//
// Until 14 Sep 2026 this was four hard-coded quotes sorted by price under a pulsing "LIVE" badge,
// with "Ranking by price, rating & track record" printed over a sort that only read price (website
// audit §1 finding 25). It now runs the actual model-free comparison — deterministicCompare, the
// same file quote_compare serves customers from — over one fixed sample brief, and says so: the
// badge reads "Demonstration" and the footnote says it is a replay over a fixed sample, not live
// data. The scores, the order and the top-3 cut on screen are the engine's own output.
//
// NO ANIMATION LIBRARY. The homepage shipped ~848 KB of JS and `motion` was the bulk of it; this
// card is the only moving part above the fold, so it moves with CSS transitions alone: each row is
// absolutely positioned and slides to its rank with a transform. The server renders the FINAL frame
// (all four rows, ranked, shortlisted, fully opaque), so the SSR HTML carries no opacity:0 and the
// card reads the same with JavaScript off or prefers-reduced-motion on. The replay starts after mount.
import { useEffect, useMemo, useState } from 'react';
import { BrandMark } from '@/components/BrandMark';
import { onFirstInteraction } from '@/lib/firstInteraction';
import { deterministicCompare, type Labelled } from '../../supabase/functions/quote_compare/deterministic';

export type LiveMatchLabels = {
  engine: string; demo: string; posted: string; brief: string;
  competing: string; scoring: string; shortlisted: string; cut: string; best: string;
  hidden: string; reveal: string; price: string; delivery: string; quality: string; note: string;
  supplier: string; // "Supplier {x}"
};

// A fixed sample field for "SPC flooring, 250 sqm villa in Dubai". Figures are illustrative.
const REGION = { en: ['DXB', 'AUH', 'SHJ', 'RAK'], ar: ['دبي', 'أبوظبي', 'الشارقة', 'رأس الخيمة'] };
const LETTER = { en: ['A', 'B', 'C', 'D'], ar: ['أ', 'ب', 'ج', 'د'] };
const SAMPLE: Omit<Labelled, 'label'>[] = [
  { price: 29200, lead_time: '10 days', warranty: '5 years', payment_terms: '30/70', validity: '30 days', itemised: true },
  { price: 24500, lead_time: '14 days', warranty: '3 years', payment_terms: '50/50', validity: '15 days', itemised: true },
  { price: 26800, lead_time: '7 days', warranty: null, payment_terms: '40/60', validity: '30 days', itemised: false },
  { price: 31400, lead_time: '21 days', warranty: '2 years', payment_terms: null, validity: null, itemised: false },
];

const TICK = 820;
const STEPS = 10; // 0 posted · 1-4 arrive · 5 scoring · 6 shortlist · 7-9 hold
const FINAL = STEPS - 1;
const ROW = 96; // px per row slot; each row is ROW-10 tall

function Stars({ n, label }: { n: number; label: string }) {
  return (
    <span className="flex items-center gap-1" aria-label={`${label} ${n}/5`}>
      <span className="w-[4.4em] shrink-0 font-mono text-[12px] uppercase tracking-[0.1em] text-faint rtl:tracking-normal">{label}</span>
      <span className="flex gap-[3px]" aria-hidden>
        {[1, 2, 3, 4, 5].map((i) => (
          <span key={i} className={`h-1.5 w-2.5 rounded-[1px] ${i <= n ? 'bg-teal' : 'bg-[var(--line2)]'}`} />
        ))}
      </span>
    </span>
  );
}

export function LiveMatch({ labels, locale }: { labels: LiveMatchLabels; locale: string }) {
  const lang: 'en' | 'ar' = locale === 'ar' ? 'ar' : 'en';
  const [step, setStep] = useState(FINAL);

  // The replay waits for the visitor's first interaction (src/lib/firstInteraction.ts). Starting on
  // mount reset the card to step 0 right after hydration and re-rendered it every 820 ms inside the
  // first-load window; until the first scroll/touch/pointer move the card shows the server's final,
  // ranked frame, which is the complete result anyway.
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let id = 0;
    const stop = onFirstInteraction(() => {
      setStep(0);
      id = window.setInterval(() => setStep((s) => (s + 1) % STEPS), TICK);
    });
    return () => { stop(); clearInterval(id); };
  }, []);

  const money = useMemo(
    () => new Intl.NumberFormat(lang === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 0 }),
    [lang],
  );
  const field = useMemo(() => {
    const labelled: Labelled[] = SAMPLE.map((q, i) => ({ ...q, label: labels.supplier.replace('{x}', LETTER[lang][i]) }));
    const result = deterministicCompare(labelled, lang);
    const rank = new Map(result.quotes.map((q, i) => [q.label, i]));
    // A quote outside the shortlist is ranked after it, in arrival order.
    return labelled.map((q, i) => ({
      ...q, region: REGION[lang][i], arrival: i,
      rank: rank.has(q.label) ? rank.get(q.label)! : 3 + i,
      scored: result.quotes.find((x) => x.label === q.label),
    }));
  }, [labels.supplier, lang]);

  const scoring = step >= 5;
  const shortlisted = step >= 6;
  const order = [...field].sort((a, b) => a.rank - b.rank).map((q) => q.label);
  const status = !scoring ? labels.competing : !shortlisted ? labels.scoring : labels.shortlisted;
  const fmt = (n: number | null) => (n === null ? '—' : lang === 'ar' ? `${money.format(n)} درهم` : `AED ${money.format(n)}`);

  return (
    <div className="glass depth relative overflow-hidden rounded-[22px]">
      <div className="flex items-center gap-2.5 border-b border-[var(--line)] bg-teal-light/[0.03] px-5 py-3.5">
        <BrandMark className="h-4 w-4 shrink-0" />
        <span className="font-mono text-[12px] font-medium uppercase tracking-[0.2em] text-faint rtl:font-sans rtl:tracking-normal">
          {labels.engine}
        </span>
        <span className="ms-auto rounded-full border border-gold/40 bg-gold/[0.08] px-2 py-0.5 font-mono text-[12px] uppercase tracking-[0.16em] text-gold rtl:font-sans rtl:tracking-normal">
          {labels.demo}
        </span>
      </div>

      <div className="flex items-start gap-3 px-5 py-4">
        <span className="mt-0.5 shrink-0 rounded border border-[var(--line2)] px-1.5 py-0.5 font-mono text-[12px] uppercase tracking-[0.14em] text-teal-light rtl:font-sans rtl:tracking-normal">
          {labels.posted}
        </span>
        <p className="text-[13px] leading-relaxed text-paper/90">{labels.brief}</p>
      </div>

      <div className="relative border-t border-[var(--line)] px-4 py-4 sm:px-5">
        <ul className="relative" style={{ height: ROW * 4 - 10 }}>
          {field.map((q) => {
            const arrived = step >= q.arrival + 1;
            const slot = scoring ? order.indexOf(q.label) : q.arrival;
            const out = shortlisted && q.rank > 2;
            const best = shortlisted && q.rank === 0;
            return (
              <li
                key={q.label}
                className={`absolute inset-x-0 top-0 rounded-xl border px-3.5 py-3 transition-[transform,opacity,border-color,background-color] duration-[600ms] ease-expo ${
                  best ? 'border-gold/50 bg-gold/[0.07] shadow-[0_16px_40px_-20px_rgba(227,192,101,.75)]'
                  : 'border-[var(--line)] bg-navy-deep/60'}`}
                style={{
                  height: ROW - 10,
                  transform: `translateY(${slot * ROW + (arrived ? 0 : 14)}px)`,
                  opacity: !arrived ? 0 : out ? 0.4 : 1,
                }}
              >
                <div className="flex items-center gap-3">
                  <span className="redact redact-sq !h-6 !w-6 shrink-0" aria-hidden />
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-[12.5px] font-semibold text-paper">{q.label}</span>
                      <span className="rounded border border-[var(--line2)] px-1 py-px font-mono text-[12px] text-muted rtl:font-sans">{q.region}</span>
                      {best && <span className="rounded-full bg-gold/90 px-1.5 py-px text-[12px] font-semibold text-[#2A2000]">{labels.best}</span>}
                      {out && <span className="text-[12px] text-faint">{labels.cut}</span>}
                    </div>
                    <span className="mt-0.5 block text-[12px] text-faint">{labels.hidden}</span>
                  </div>
                  <span dir="ltr" className={`shrink-0 font-mono text-[14px] font-semibold tabular ${best ? 'text-gold' : 'text-white'}`}>
                    {fmt(q.price)}
                  </span>
                </div>
                {q.scored && (
                  <div className={`mt-2 grid gap-1 ps-9 transition-opacity duration-500 sm:grid-cols-3 ${scoring && !out ? 'opacity-100' : 'opacity-0'}`}>
                    <Stars n={q.scored.price_score} label={labels.price} />
                    <Stars n={q.scored.delivery_score} label={labels.delivery} />
                    <Stars n={q.scored.quality_score} label={labels.quality} />
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      </div>

      <div className="flex items-center gap-3 border-t border-[var(--line)] px-5 py-3.5">
        <span className="node-dot shrink-0" aria-hidden />
        <span aria-live="polite" className="min-w-0 flex-1 truncate text-[12.5px] text-muted">{status}</span>
        <span className="shrink-0 rounded-full border border-[var(--line2)] px-2.5 py-1 font-mono text-[12px] uppercase tracking-[0.14em] text-faint rtl:font-sans rtl:tracking-normal">
          {labels.reveal}
        </span>
      </div>
      <p className="border-t border-[var(--line)] px-5 py-2.5 text-[12px] leading-relaxed text-faint">{labels.note}</p>
    </div>
  );
}
