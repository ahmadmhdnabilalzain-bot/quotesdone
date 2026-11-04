/**
 * SEALED RECIPES — the composed pieces wave 2 builds pages from. Server components (no hooks), so
 * they add nothing to First Load JS; every string comes in through props, so each page passes its
 * own translated copy. Rendered and verified on /brand.
 *
 *   Seal            the brand motif: content under a redaction bar; `open` slides it off in gold
 *   Kicker          mono caps label with a live node (Arabic: weight + teal lead bar)
 *   SectionHead     kicker + display heading + lead, the one section opener
 *   SealedCard      the shape-system card: a sealed document with a folded corner (globals.css .qd-env)
 *   LedgerList      the shape-system list: ruled rows with mono serials instead of a grid of boxes
 *   Bento/BentoTile asymmetric feature grid of sealed documents
 *   ProductFrame    faux-live application window; ALWAYS carries a visible "sample data" label
 *   ComparisonShowcase · BoqShowcase · MatchShowcase   product screens inside a ProductFrame
 *   StatBlock       one figure + label + source/note (never print a number nobody measured)
 *   Stepper         vertical timeline/stepper with done/current/next states
 *   FactBand        logo-free trust band: facts, not borrowed logos
 *   ProofBand       testimonial-free proof: mechanisms with the evidence each one rests on
 */
import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export function Seal({ children, open, loop, className }: { children: ReactNode; open?: boolean; loop?: boolean; className?: string }) {
  return (
    <span className={cn('qd-seal', open && 'is-open', loop && 'qd-seal-loop', className)}>
      <span>{children}</span>
    </span>
  );
}

export function Kicker({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={cn('qd-kicker', className)}>{children}</span>;
}

export function SectionHead({ kicker, title, lead, align = 'start', className }: { kicker?: ReactNode; title: ReactNode; lead?: ReactNode; align?: 'start' | 'center'; className?: string }) {
  return (
    <header className={cn('max-w-[760px]', align === 'center' && 'mx-auto text-center', className)}>
      {kicker ? <Kicker>{kicker}</Kicker> : null}
      <h2 className="mt-5 font-head text-h2 text-white">{title}</h2>
      {lead ? <p className={cn('mt-5 max-w-[60ch] text-lead text-muted', align === 'center' && 'mx-auto')}>{lead}</p> : null}
    </header>
  );
}

/** A sealed document (founder, 14 Sep 2026: the square cards read as generic). `open` is the chosen
 *  one, in gold; `hover` turns the fold gold under the pointer. Pad at least 24px so the fold clears. */
export function SealedCard({ as: Tag = 'article', size, open, hover, className, children }: {
  as?: 'article' | 'div' | 'li' | 'section'; size?: 'lg'; open?: boolean; hover?: boolean; className?: string; children: ReactNode;
}) {
  return <Tag className={cn('qd-env', size === 'lg' && 'qd-env-lg', open && 'qd-env-gold', hover && 'qd-env-hover', className)}>{children}</Tag>;
}

/** The seal mark carrying a document's serial. Decorative: the order is already in the markup. */
export function Stamp({ n, open, className }: { n: number; open?: boolean; className?: string }) {
  return <span aria-hidden className={cn('qd-stamp', open && 'qd-stamp-open', className)}>{String(n).padStart(2, '0')}</span>;
}

export type LedgerItem = { title: ReactNode; body?: ReactNode };
/** An index of ruled rows, mono serial first. `lg` sets the serial at display size (a real sequence). */
export function LedgerList({ items, start = 1, lg, titleAs: H = 'h3', className }: {
  items: LedgerItem[]; start?: number; lg?: boolean; titleAs?: 'h2' | 'h3'; className?: string;
}) {
  return (
    <ol className={cn('qd-ledger qd-ticks', lg && 'qd-ledger-lg', className)}>
      {items.map((it, i) => (
        <li key={i}>
          <div className="qd-ledger-row">
            <span className="qd-ledger-no" aria-hidden>{String(start + i).padStart(2, '0')}</span>
            <div className="min-w-0 md:grid md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] md:gap-8">
              <H className="text-balance font-head text-[clamp(18px,1.7vw,21px)] font-semibold leading-snug tracking-snug text-white">{it.title}</H>
              {it.body ? <div className="mt-2 max-w-[60ch] text-pretty text-copy text-muted md:mt-0">{it.body}</div> : null}
            </div>
          </div>
        </li>
      ))}
    </ol>
  );
}

export function Bento({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn('grid auto-rows-[minmax(220px,auto)] grid-cols-1 gap-4 md:grid-cols-6', className)}>{children}</div>;
}

const SPAN = { 2: 'md:col-span-2', 3: 'md:col-span-3', 4: 'md:col-span-4', 6: 'md:col-span-6' } as const;
export function BentoTile({ span = 2, tall, kicker, title, children, visual, className }: {
  span?: keyof typeof SPAN; tall?: boolean; kicker?: ReactNode; title: ReactNode; children?: ReactNode; visual?: ReactNode; className?: string;
}) {
  return (
    <article className={cn('qd-env qd-env-hover group flex flex-col overflow-hidden', SPAN[span], tall && 'md:row-span-2', className)}>
      {visual ? <div className="relative min-h-[140px] flex-1 overflow-hidden border-b border-line">{visual}</div> : null}
      <div className="flex flex-col gap-2 p-6 pt-8">
        {kicker ? <span className="font-mono text-label uppercase tracking-caps text-faint">{kicker}</span> : null}
        <h3 className="font-head text-h3 text-white">{title}</h3>
        {children ? <div className="text-copy text-muted">{children}</div> : null}
      </div>
    </article>
  );
}

export function ProductFrame({ title, sampleLabel, status, children, className }: { title: ReactNode; sampleLabel: ReactNode; status?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <figure className={cn('qd-frame qd-grain', className)}>
      <div className="qd-frame-bar">
        <i /><i /><i />
        <span className="ms-2 truncate font-mono text-label text-muted">{title}</span>
        <span className="ms-auto flex items-center gap-2">
          {status ? <span className="flex items-center gap-1.5 font-mono text-label text-teal-light"><span className="node-dot h-1.5! w-1.5!" />{status}</span> : null}
          <span className="rounded-chip border border-line2 px-2 py-0.5 font-mono text-label text-faint">{sampleLabel}</span>
        </span>
      </div>
      <div className="relative">{children}</div>
    </figure>
  );
}

export type ComparisonRow = { item: string; values: (string | null)[] };
/** Levelled comparison: suppliers sealed in the header, one column marked best, gaps flagged. */
export function ComparisonShowcase({ suppliers, rows, totals, best, labels }: {
  suppliers: string[]; rows: ComparisonRow[]; totals: string[]; best: number;
  labels: { item: string; total: string; missing: string; best: string };
}) {
  const cols = `minmax(140px,1.4fr) repeat(${suppliers.length},minmax(96px,1fr))`;
  return (
    <div className="overflow-x-auto">
      <div className="min-w-[520px] text-body" role="table">
        <div className="qd-row border-line2 bg-navy-deep/40" style={{ gridTemplateColumns: cols }} role="row">
          <span className="font-mono text-label uppercase tracking-caps text-faint" role="columnheader">{labels.item}</span>
          {suppliers.map((s, i) => (
            <span key={s} role="columnheader" className="flex flex-col gap-1.5">
              <span className="flex items-center gap-1.5 font-medium text-white">{s}{i === best ? <span className="rounded-chip bg-teal/15 px-1.5 py-px font-mono text-label text-teal-light">{labels.best}</span> : null}</span>
              <span className="redact h-2 w-14" aria-hidden />
            </span>
          ))}
        </div>
        <div className="qd-stagger reveal-stagger">
          {rows.map((r) => (
            <div key={r.item} className="qd-row" style={{ gridTemplateColumns: cols }} role="row">
              <span className="text-paper/90" role="cell">{r.item}</span>
              {r.values.map((v, i) => (
                <span key={i} role="cell" className={cn('tabular font-mono', v === null ? 'text-warn-fg' : i === best ? 'text-teal-light' : 'text-muted')}>
                  {v === null ? `⚠ ${labels.missing}` : v}
                </span>
              ))}
            </div>
          ))}
        </div>
        <div className="qd-row border-t border-line2 bg-teal-light/3" style={{ gridTemplateColumns: cols }} role="row">
          <span className="font-medium text-white" role="cell">{labels.total}</span>
          {totals.map((t, i) => (
            <span key={i} role="cell" className={cn('tabular font-mono text-[15px] font-semibold', i === best ? 'text-white' : 'text-muted')}>{t}</span>
          ))}
        </div>
      </div>
    </div>
  );
}

export type BoqLine = { code: string; desc: string; unit: string; qty: string; rate?: string };
/** Bill of quantities read off a drawing: code · description · unit · qty, rows arriving in order. */
export function BoqShowcase({ lines, labels }: { lines: BoqLine[]; labels: { code: string; desc: string; unit: string; qty: string } }) {
  const cols = '64px minmax(0,1fr) 56px 80px';
  return (
    <div className="text-body" role="table">
      <div className="qd-row bg-navy-deep/40 font-mono text-label uppercase tracking-caps text-faint" style={{ gridTemplateColumns: cols }} role="row">
        <span role="columnheader">{labels.code}</span><span role="columnheader">{labels.desc}</span><span role="columnheader">{labels.unit}</span><span role="columnheader" className="text-end">{labels.qty}</span>
      </div>
      <div className="qd-stagger reveal-stagger">
        {lines.map((l) => (
          <div key={l.code} className="qd-row" style={{ gridTemplateColumns: cols }} role="row">
            <span className="font-mono text-label text-teal-light" role="cell">{l.code}</span>
            <span className="truncate text-paper/90" role="cell">{l.desc}</span>
            <span className="font-mono text-label text-muted" role="cell">{l.unit}</span>
            <span className="tabular text-end font-mono text-paper" role="cell">{l.qty}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export type Match = { name: string; score: number; facts: string; revealed?: boolean };
/** Supplier match list: every identity sealed except the one the customer chose (gold). */
export function MatchShowcase({ matches, labels }: { matches: Match[]; labels: { match: string } }) {
  return (
    <ul className="qd-stagger reveal-stagger divide-y divide-(--line)">
      {matches.map((m, i) => (
        <li key={i} className={cn('flex items-center gap-4 px-4 py-3.5', m.revealed && 'bg-gold/5')}>
          <span className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-panel border font-mono text-label', m.revealed ? 'border-gold/50 text-gold-light' : 'border-line2 text-muted')}>{String(i + 1).padStart(2, '0')}</span>
          <span className="min-w-0 flex-1">
            <span className="block text-copy font-medium">
              <Seal open={m.revealed} className={m.revealed ? 'qd-revealed' : undefined}>{m.name}</Seal>
            </span>
            <span className="mt-1 block truncate text-label text-faint">{m.facts}</span>
          </span>
          <span className="w-28 shrink-0">
            <span className="flex justify-between font-mono text-label"><span className="text-faint">{labels.match}</span><span className="tabular text-paper">{m.score}%</span></span>
            <span className="qd-meter mt-1.5 block"><span style={{ width: `${m.score}%` }} /></span>
          </span>
        </li>
      ))}
    </ul>
  );
}

export function StatBlock({ value, label, note, className }: { value: ReactNode; label: ReactNode; note?: ReactNode; className?: string }) {
  return (
    <div className={cn('qd-ticks relative pt-6', className)}>
      <div className="qd-figure font-head text-[clamp(40px,4.6vw,64px)] font-semibold">{value}</div>
      <div className="mt-2 text-copy text-paper">{label}</div>
      {note ? <div className="mt-1 font-mono text-label text-faint">{note}</div> : null}
    </div>
  );
}

export type Step = { title: ReactNode; body?: ReactNode; meta?: ReactNode; state?: 'done' | 'current' | 'next' };
export function Stepper({ steps, className }: { steps: Step[]; className?: string }) {
  return (
    <ol className={cn('relative flex flex-col gap-7', className)}>
      <span className="qd-step-line" aria-hidden />
      {steps.map((s, i) => (
        <li key={i} className="relative flex gap-5">
          <span className={cn(
            'relative z-10 grid h-8 w-8 shrink-0 place-items-center rounded-full border font-mono text-label',
            s.state === 'done' ? 'border-gold/60 bg-gold/15 text-gold-light' : s.state === 'current' ? 'border-teal bg-teal/20 text-teal-light shadow-glow-teal' : 'border-line2 bg-navy-deep text-faint',
          )}>
            {s.state === 'done' ? '✓' : String(i + 1).padStart(2, '0')}
          </span>
          <div className="pt-1">
            {s.meta ? <div className="font-mono text-label uppercase tracking-caps text-faint">{s.meta}</div> : null}
            <div className={cn('font-head text-[17px] font-semibold tracking-snug', s.state === 'next' ? 'text-muted' : 'text-white')}>{s.title}</div>
            {s.body ? <p className="mt-1 max-w-[52ch] text-copy text-muted">{s.body}</p> : null}
          </div>
        </li>
      ))}
    </ol>
  );
}

export function FactBand({ facts, className }: { facts: { k: ReactNode; v: ReactNode }[]; className?: string }) {
  return (
    <div className={cn('qd-panel grid grid-cols-2 divide-line md:grid-cols-4 md:divide-x', className)}>
      {facts.map((f, i) => (
        <div key={i} className="flex flex-col gap-1.5 px-6 py-5">
          <span className="font-mono text-label uppercase tracking-caps text-faint">{f.k}</span>
          <span className="font-head text-[17px] font-semibold tracking-snug text-white">{f.v}</span>
        </div>
      ))}
    </div>
  );
}

export function ProofBand({ items, className }: { items: { claim: ReactNode; evidence: ReactNode }[]; className?: string }) {
  return (
    <div className={cn('grid gap-4 md:grid-cols-3', className)}>
      {items.map((p, i) => (
        <div key={i} className="qd-env p-6 pt-7">
          <Stamp n={i + 1} />
          <div className="mt-4 font-head text-[19px] font-semibold leading-snug tracking-snug text-white">{p.claim}</div>
          <div className="mt-4 border-t border-line pt-4 text-small text-muted">{p.evidence}</div>
        </div>
      ))}
    </div>
  );
}
