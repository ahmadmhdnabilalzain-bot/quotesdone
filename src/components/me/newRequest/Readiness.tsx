// @ts-nocheck
'use client';
import * as M from 'motion/react-m';
import { cn } from '@/lib/utils';
import { t, tf } from '../portalText';

export function ReadinessBar({ pct, lang, reduce }) {
  return (
    <div className="border-b border-border px-5 py-2">
      <div className="flex items-center justify-between"><span className="font-mono text-label uppercase tracking-caps text-muted-foreground">{t(lang, 'nr_readiness')}</span><span className="tabular font-mono text-label text-foreground">{pct}%</span></div>
      <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-secondary/70" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-label={t(lang, 'nr_readiness')}>
        <M.div className="h-full rounded-full bg-linear-to-r from-primary/60 to-primary" initial={reduce ? false : { width: 0 }} animate={{ width: pct + '%' }} transition={{ duration: reduce ? 0 : 0.7, ease: [0.2, 0.8, 0.2, 1] }} />
      </div>
    </div>
  );
}

export function QuestionChips({ questions, next, left, lang, onPick, reduce }) {
  return (
    <div className="mt-2 ps-1">
      <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{left > 0 ? tf(lang, 'nr_left', { n: left }) : t(lang, 'nr_chips_hint')}</div>
      <div className="flex flex-wrap gap-1.5">
        {questions.slice(0, 8).map((q, i) => (
          <M.button key={q + i} type="button" onClick={() => onPick(q)}
            initial={reduce ? false : { opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduce ? 0 : 0.2, delay: reduce ? 0 : 0.05 * i }}
            className={cn('rounded-full border px-3 py-1.5 text-start text-[12.5px] transition-colors focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
              q === next ? 'border-primary/55 bg-primary/15 font-semibold text-primary' : 'border-border bg-card/60 text-foreground hover:border-primary/40')}>
            {q}
          </M.button>
        ))}
      </div>
    </div>
  );
}
