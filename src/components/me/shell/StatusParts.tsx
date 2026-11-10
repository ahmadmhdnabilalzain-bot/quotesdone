// @ts-nocheck
'use client';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { isClosedRequest } from '../requestStatus';

// ── STAT TILE ──────────────────────────────────────────────────────────────────────────────────
// The old Kpi was a bare number over a caption in a flat box, six across. This gives each number a
// tinted glyph and an optional one-line meaning, and — the part that matters — an emphatic variant
// so "awaiting your decision" does not look the same as "requests". A zero that is GOOD and a zero
// that means nothing has happened yet are different facts and must not render identically.
export function StatTile({ icon: Icon, label, value, hint, tone = 'default' }) {
  return (
    <Card className={cn(
      'group relative overflow-hidden p-4 shadow-e1 transition-[transform,border-color,box-shadow] duration-300 hover:shadow-e2 motion-safe:hover:-translate-y-0.5 sm:p-5',
      tone === 'accent' && 'border-primary/40',
    )}>
      {/* The kit's lit top edge, on the tile that is asking for a decision. */}
      {tone === 'accent' ? <span aria-hidden className="absolute inset-x-6 top-0 h-px bg-linear-to-r from-transparent via-primary/80 to-transparent" /> : null}
      <div className="flex items-start justify-between gap-2">
        {/* Wraps, never truncates: "AWAITING YOUR DECISI…" cut the tile's one word that mattered. */}
        <div className="min-w-0 wrap-break-word font-mono text-label uppercase tracking-caps text-muted-foreground">{label}</div>
        <span className={cn('grid h-8 w-8 shrink-0 place-items-center rounded-panel border',
          tone === 'accent' ? 'border-primary/35 bg-primary/12 text-primary' : 'border-border bg-secondary/40 text-muted-foreground')}>
          <Icon className="h-4 w-4" aria-hidden />
        </span>
      </div>
      <div className={cn('tabular mt-3 font-head text-[30px] font-semibold leading-none tracking-snug',
        tone === 'accent' ? 'text-primary' : 'text-foreground')}>{value}</div>
      {hint ? <div className="mt-2 text-[11.5px] leading-snug text-muted-foreground/85">{hint}</div> : null}
    </Card>
  );
}

// ── STATUS PILL ────────────────────────────────────────────────────────────────────────────────
// The five stages of OUR lifecycle. A marketplace has no "Shipped" and no "Processing"; it has a
// request that is being matched, then quoted, then decided, then revealed, then closed. Colour
// carries meaning and is never the ONLY carrier — the word is always present.
export const RFQ_STATE = {
  matching:  { key: 'st_matching',  cls: 'bg-info/12 text-info-fg border-info/25',           variant: 'info' },
  quoting:   { key: 'st_quoting',   cls: 'bg-warn/12 text-warn-fg border-warn/25',           variant: 'warn' },
  quotes_in: { key: 'st_quotes_in', cls: 'bg-primary/12 text-primary border-primary/30',     variant: 'default' },
  revealed:  { key: 'st_revealed',  cls: 'bg-ok/12 text-ok-fg border-ok/25',                 variant: 'ok' },
  closed:    { key: 'st_closed',    cls: 'bg-secondary/60 text-muted-foreground border-border', variant: 'outline' },
};
// Derived from facts the row already carries, never from the clock.
export function rfqState(inq, quotes) {
  const n = (quotes || []).length;
  // expired and lost are closed too (../requestStatus.ts): an expired request read "Matching".
  if (isClosedRequest(inq && inq.status)) return 'closed';
  if ((quotes || []).some((q) => q.revealed) || (inq && inq.hired_supplier_id)) return 'revealed';
  if (n >= 2) return 'quotes_in';
  if (n >= 1) return 'quoting';
  return 'matching';
}
export function StatusPill({ state, t }) {
  const s = RFQ_STATE[state] || RFQ_STATE.matching;
  return (
    // The kit Badge with its status light; `closed` keeps the muted token so it reads in both themes.
    <Badge variant={s.variant} dot className={cn('shrink-0 font-semibold', state === 'closed' && 'text-muted-foreground')}>
      {t(s.key)}
    </Badge>
  );
}
