'use client';
// Small pieces shared by the project list and the project workspace, so the two surfaces cannot
// drift apart visually or start describing the same number two different ways.
import * as React from 'react';
import { cn } from '@/lib/utils';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * One measured figure.
 *
 * `value` is what the API actually said. `empty` is what to show when there is nothing to measure —
 * pass it, and pass something that says WHY (e.g. "No linked RFQs"), never a cheerful zero. The one
 * defect this portal has already shipped was an empty state that read the same whether or not
 * anything had happened; a tile that renders "0 suppliers" over "nothing was linked" is that defect.
 */
export function Stat({
  label, value, hint, empty, className,
}: {
  label: string;
  value?: React.ReactNode;
  hint?: string;
  empty?: string;
  className?: string;
}) {
  const isEmpty = value === undefined || value === null || value === '';
  return (
    <div className={cn('rounded-lg border border-border bg-white/[0.03] px-3.5 py-3', className)}>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={cn('mt-1 text-[19px] font-bold leading-tight', isEmpty ? 'text-muted-foreground' : 'text-foreground')}>
        {isEmpty ? '—' : value}
      </div>
      {(isEmpty ? empty : hint) ? (
        <div className="mt-1 text-[11px] leading-snug text-muted-foreground">{isEmpty ? empty : hint}</div>
      ) : null}
    </div>
  );
}

/** A message the customer must be able to read and act on. Never used to dress a failure as news. */
export function Notice({
  tone = 'info', children, action, className,
}: {
  tone?: 'info' | 'error';
  children: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      role={tone === 'error' ? 'alert' : 'status'}
      aria-live="polite"
      className={cn(
        'flex flex-wrap items-center gap-3 rounded-lg border px-3.5 py-2.5 text-[13px]',
        tone === 'error' ? 'border-destructive/40 bg-destructive/10 text-destructive' : 'border-primary/35 bg-primary/10 text-primary',
        className,
      )}
    >
      <span className="font-semibold">{children}</span>
      {action}
    </div>
  );
}

/** A plain, non-interactive proportion bar. Kept out of Radix Progress so it can sit inside a
 *  <button> card without nesting a role="progressbar" in a control. The number is always in text
 *  next to it — the bar alone is decoration. */
export function Bar({ pct, className }: { pct: number; className?: string }) {
  return (
    <div aria-hidden="true" className={cn('h-1.5 w-full overflow-hidden rounded-full bg-white/10', className)}>
      <div className="h-full rounded-full bg-primary transition-[width] duration-500" style={{ width: `${Math.max(0, Math.min(100, pct))}%` }} />
    </div>
  );
}

export function ListSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2" aria-hidden="true">
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton key={i} className="h-[168px] w-full rounded-lg" />
      ))}
    </div>
  );
}
