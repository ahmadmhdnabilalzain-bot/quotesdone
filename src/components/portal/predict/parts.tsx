'use client';
// The two pieces the forecast and the negotiation panel share, so they cannot drift apart visually
// or start describing the same absence two different ways.
import * as React from 'react';
import { cn } from '@/lib/utils';

/** An honest absence: a heading and a sentence saying WHICH absence is true. Never a cheerful nudge. */
export function Empty({ title, body, className }: { title: string; body: string; className?: string }) {
  return (
    <div className={cn('rounded-lg border border-dashed border-border bg-white/2 px-5 py-8 text-center', className)}>
      <h3 className="text-[15px] font-bold text-foreground">{title}</h3>
      <p className="mx-auto mt-2 max-w-[62ch] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

/**
 * One measured figure.
 *
 * `value` is what the endpoint actually said. `empty` is what to show when there is nothing to
 * measure — pass it, and pass something that says WHY. A tile rendering a confident 0 over "this
 * was withheld" is the defect this whole folder exists to avoid.
 */
export function Field({
  label, value, empty, hint, className,
}: {
  label: string;
  value?: React.ReactNode;
  empty?: string;
  hint?: string;
  className?: string;
}) {
  const missing = value === undefined || value === null || value === '';
  return (
    <div className={cn('rounded-lg border border-border bg-white/3 px-3.5 py-3', className)}>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={cn('mt-1 text-[19px] font-bold leading-tight', missing ? 'text-muted-foreground' : 'text-foreground')}>
        {missing ? '—' : value}
      </div>
      {(missing ? empty : hint) ? (
        <div className="mt-1 text-[11px] leading-snug text-muted-foreground">{missing ? empty : hint}</div>
      ) : null}
    </div>
  );
}
