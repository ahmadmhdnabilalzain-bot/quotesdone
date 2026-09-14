'use client';

// THE ENGINE CARD, AS A DEMONSTRATION OF THE REAL ENGINE.
//
// Until 14 Sep 2026 this was four hard-coded quotes sorted by price under a pulsing "LIVE" badge,
// with "Ranking by price, rating & track record" printed over a sort that only read price (website
// audit §1 finding 25). It now runs the actual model-free comparison — deterministicCompare, the
// same file quote_compare serves customers from — over one fixed sample brief, and says so: the
// badge reads "Demonstration", and the footnote says it is a replay over a fixed sample, not live
// data. The scores, the order and the top-3 cut on screen are the engine's own output.
//
// SSR renders the FINAL frame (ranked, shortlisted), so the card is readable before hydration and
// with reduced motion; the replay loop starts only after mount.
import { useEffect, useMemo, useState } from 'react';
import { motion, AnimatePresence, useReducedMotion } from 'motion/react';
import { BrandMark } from '@/components/BrandMark';
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

function Stars({ n, label }: { n: number; label: string }) {
  return (
    <span className="flex items-center gap-1" aria-label={`${label} ${n}/5`}>
      <span className="w-[4.2em] shrink-0 font-mono text-[9px] uppercase tracking-[0.12em] text-faint">{label}</span>
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
  const reduce = useReducedMotion();
  const [step, setStep] = useState(FINAL);

  useEffect(() => {
    if (reduce) return;
    setStep(0);
    const id = setInterval(() => setStep((s) => (s + 1) % STEPS), TICK);
    return () => clearInterval(id);
  }, [reduce]);

  const money = useMemo(
    () => new Intl.NumberFormat(lang === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 0 }),
    [lang],
  );
  const field = useMemo(() => {
    const labelled: Labelled[] = SAMPLE.map((q, i) => ({ ...q, label: labels.supplier.replace('{x}', LETTER[lang][i]) }));
    const result = deterministicCompare(labelled, lang);
    const rank = new Map(result.quotes.map((q, i) => [q.label, i]));
    return labelled.map((q, i) => {
      const scored = result.quotes.find((x) => x.label === q.label);
      return { ...q, region: REGION[lang][i], rank: rank.has(q.label) ? rank.get(q.label)! : 99, scored };
    });
  }, [labels.supplier, lang]);

  const arrived = Math.min(4, step);
  const scoring = step >= 5;
  const shortlisted = step >= 6;
  const shown = field.slice(0, step >= 5 ? 4 : arrived);
  const ordered = scoring ? [...shown].sort((a, b) => a.rank - b.rank) : shown;
  const status = !scoring ? labels.competing : !shortlisted ? labels.scoring : labels.shortlisted;
  const fmt = (n: number | null) => (n === null ? '—' : lang === 'ar' ? `${money.format(n)} درهم` : `AED ${money.format(n)}`);

  return (
    <div className="glass depth relative overflow-hidden rounded-[22px]">
      <div className="flex items-center gap-2.5 border-b border-[var(--line)] bg-teal-light/[0.03] px-5 py-3.5">
        <BrandMark className="h-4 w-4 shrink-0" />
        <span className="font-mono text-[10.5px] font-medium uppercase tracking-[0.2em] text-faint rtl:tracking-normal">
          {labels.engine}
        </span>
        <span className="ms-auto rounded-full border border-gold/40 bg-gold/[0.08] px-2 py-0.5 font-mono text-[9.5px] uppercase tracking-[0.16em] text-gold rtl:tracking-normal">
          {labels.demo}
        </span>
      </div>

      <div className="flex items-start gap-3 px-5 py-4">
        <span className="mt-0.5 shrink-0 rounded border border-[var(--line2)] px-1.5 py-0.5 font-mono text-[9.5px] uppercase tracking-[0.14em] text-teal-light rtl:tracking-normal">
          {labels.posted}
        </span>
        <p className="text-[13px] leading-relaxed text-paper/90">{labels.brief}</p>
      </div>

      <div className="relative min-h-[300px] border-t border-[var(--line)] px-4 py-4 sm:px-5">
        <ul className="flex flex-col gap-2.5">
          <AnimatePresence initial={false}>
            {ordered.map((q) => {
              const out = shortlisted && q.rank > 2;
              const best = shortlisted && q.rank === 0;
              return (
                <motion.li
                  key={q.label}
                  layout
                  initial={{ opacity: 0, y: 14 }}
                  animate={{ opacity: out ? 0.38 : 1, y: 0 }}
                  exit={{ opacity: 0 }}
                  transition={{ type: 'spring', stiffness: 420, damping: 34, mass: 0.7 }}
                  className={`relative rounded-xl border px-3.5 py-3 ${
                    best ? 'border-gold/50 bg-gold/[0.07] shadow-[0_16px_40px_-20px_rgba(227,192,101,.75)]'
                    : 'border-[var(--line)] bg-teal-light/[0.02]'}`}
                >
                  <div className="flex items-center gap-3">
                    <span className="redact redact-sq !h-6 !w-6 shrink-0" aria-hidden />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-[12px] font-semibold text-paper">{q.label}</span>
                        <span className="rounded border border-[var(--line2)] px-1 py-px font-mono text-[9.5px] text-muted">{q.region}</span>
                        {best && <span className="rounded-full bg-gold/90 px-1.5 py-px font-mono text-[9px] font-semibold uppercase tracking-[0.12em] text-[#2A2000] rtl:tracking-normal">{labels.best}</span>}
                        {out && <span className="font-mono text-[9.5px] text-faint">{labels.cut}</span>}
                      </div>
                      <span className="mt-0.5 block font-mono text-[9.5px] text-faint">{labels.hidden}</span>
                    </div>
                    <span dir="ltr" className={`shrink-0 font-mono text-[14px] font-semibold tabular ${best ? 'text-gold' : 'text-white'}`}>
                      {fmt(q.price)}
                    </span>
                  </div>
                  {scoring && q.scored && !out && (
                    <div className="mt-2.5 grid gap-1 ps-9 sm:grid-cols-3">
                      <Stars n={q.scored.price_score} label={labels.price} />
                      <Stars n={q.scored.delivery_score} label={labels.delivery} />
                      <Stars n={q.scored.quality_score} label={labels.quality} />
                    </div>
                  )}
                </motion.li>
              );
            })}
          </AnimatePresence>
        </ul>
      </div>

      <div className="flex items-center gap-3 border-t border-[var(--line)] px-5 py-3.5">
        <span className="node-dot shrink-0" aria-hidden />
        <span aria-live="polite" className="min-w-0 flex-1 truncate text-[12.5px] text-muted">{status}</span>
        <span className="shrink-0 rounded-full border border-[var(--line2)] px-2.5 py-1 font-mono text-[9.5px] uppercase tracking-[0.14em] text-faint rtl:tracking-normal">
          {labels.reveal}
        </span>
      </div>
      <p className="border-t border-[var(--line)] px-5 py-2.5 text-[11.5px] leading-relaxed text-faint">{labels.note}</p>
    </div>
  );
}
