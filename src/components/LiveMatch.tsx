'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { motion, AnimatePresence, useReducedMotion } from 'motion/react';
import { BrandMark } from '@/components/BrandMark';

export type LiveMatchLabels = {
  live: string;
  posted: string;
  competing: string;
  sorting: string;
  best: string;
  hidden: string;
  reveal: string;
  brief: string;
};

type Quote = { id: string; region: string; price: number; rating: number };

/** Fixed sample field — prices are AED figures, not translatable copy. */
const QUOTES: Quote[] = [
  { id: 'q1', region: 'DXB', price: 29200, rating: 0.86 },
  { id: 'q2', region: 'AUH', price: 24500, rating: 0.97 },
  { id: 'q3', region: 'SHJ', price: 26800, rating: 0.9 },
  { id: 'q4', region: 'RAK', price: 31400, rating: 0.8 },
];
const BEST_ID = 'q2';
const TICK = 720;
const STEPS = 9; // 0 post · 1-4 arrive · 5 rank · 6 matched · 7-8 hold

const fmt = (n: number) => `AED ${n.toLocaleString('en-US')}`;

export function LiveMatch({ labels }: { labels: LiveMatchLabels }) {
  const reduce = useReducedMotion();
  const [step, setStep] = useState(reduce ? STEPS - 1 : 0);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (reduce) return;
    timer.current = setInterval(() => setStep((s) => (s + 1) % STEPS), TICK);
    return () => {
      if (timer.current) clearInterval(timer.current);
    };
  }, [reduce]);

  const ranking = step >= 5;
  const visible = reduce ? 4 : Math.max(0, Math.min(4, step));

  // Insertion order while arriving; price-sorted once the engine ranks.
  const ordered = useMemo(() => {
    const shown = QUOTES.slice(0, visible);
    return ranking ? [...shown].sort((a, b) => a.price - b.price) : shown;
  }, [visible, ranking]);

  const status = !ranking ? labels.competing : step === 5 ? labels.sorting : labels.best;

  return (
    <div className="glass depth relative overflow-hidden rounded-[22px]">
      {/* header */}
      <div className="flex items-center gap-2.5 border-b border-[var(--line)] bg-teal-light/[0.03] px-5 py-3.5">
        <BrandMark className="h-4 w-4 shrink-0" />
        <span className="font-mono text-[10px] font-medium uppercase tracking-[0.22em] text-faint">
          Smart Engine
        </span>
        <span className="ml-auto inline-flex items-center gap-1.5 rounded-full border border-teal/40 bg-teal/[0.08] px-2 py-0.5">
          <span className="qd-pulse h-1.5 w-1.5 rounded-full bg-teal" />
          <span className="font-mono text-[9px] uppercase tracking-[0.18em] text-teal-light">
            {labels.live}
          </span>
        </span>
      </div>

      {/* brief */}
      <div className="flex items-start gap-3 px-5 py-4">
        <span className="mt-0.5 shrink-0 rounded border border-[var(--line2)] px-1.5 py-0.5 font-mono text-[9px] uppercase tracking-[0.16em] text-teal-light">
          {labels.posted}
        </span>
        <p className="font-mono text-[12.5px] leading-relaxed text-paper/90">{labels.brief}</p>
      </div>

      {/* quote field */}
      <div className="relative min-h-[236px] border-t border-[var(--line)] px-4 py-4 sm:px-5">
        <ul className="flex flex-col gap-2.5">
          <AnimatePresence initial={false}>
            {ordered.map((q) => {
              const isBest = ranking && q.id === BEST_ID;
              return (
                <motion.li
                  key={q.id}
                  layout
                  initial={{ opacity: 0, y: 14, scale: 0.98 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.98 }}
                  transition={{ type: 'spring', stiffness: 420, damping: 34, mass: 0.7 }}
                  className={`relative flex items-center gap-3 rounded-xl border px-3.5 py-3 sm:px-4 ${
                    isBest
                      ? 'border-gold/50 bg-gold/[0.07] shadow-[0_16px_40px_-20px_rgba(227,192,101,.75)]'
                      : 'border-[var(--line)] bg-teal-light/[0.02]'
                  }`}
                >
                  {/* anonymous supplier */}
                  <span className="redact redact-sq !h-6 !w-6 shrink-0" aria-hidden />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-[9.5px] uppercase tracking-[0.16em] text-faint">
                        {labels.hidden}
                      </span>
                      <span className="rounded border border-[var(--line2)] px-1 py-px font-mono text-[9px] tabular text-muted">
                        {q.region}
                      </span>
                      {isBest && (
                        <motion.span
                          initial={{ opacity: 0, scale: 0.8 }}
                          animate={{ opacity: 1, scale: 1 }}
                          className="ml-0.5 rounded-full bg-gold/90 px-1.5 py-px font-mono text-[8.5px] font-semibold uppercase tracking-[0.14em] text-[#2A2000]"
                        >
                          {labels.best}
                        </motion.span>
                      )}
                    </div>
                    {/* rating bar */}
                    <div className="mt-2 h-1 w-full max-w-[150px] overflow-hidden rounded-full bg-[var(--line)]">
                      <motion.span
                        className={`block h-full rounded-full ${isBest ? 'bg-gold' : 'bg-teal'}`}
                        initial={{ width: 0 }}
                        animate={{ width: `${Math.round(q.rating * 100)}%` }}
                        transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
                      />
                    </div>
                  </div>
                  <span
                    className={`shrink-0 font-mono text-[14.5px] font-semibold tabular ${
                      isBest ? 'text-gold' : 'text-white'
                    }`}
                  >
                    {fmt(q.price)}
                  </span>
                </motion.li>
              );
            })}
          </AnimatePresence>
        </ul>
      </div>

      {/* status footer */}
      <div className="flex items-center gap-3 border-t border-[var(--line)] px-5 py-3.5">
        <span className="node-dot shrink-0" aria-hidden />
        <motion.span
          key={status}
          initial={{ opacity: 0, y: 4 }}
          animate={{ opacity: 1, y: 0 }}
          className="min-w-0 flex-1 truncate text-[12.5px] text-muted"
        >
          {status}
        </motion.span>
        <span className="shrink-0 rounded-full border border-[var(--line2)] px-2.5 py-1 font-mono text-[9.5px] uppercase tracking-[0.16em] text-faint/80">
          {labels.reveal}
        </span>
      </div>
    </div>
  );
}
