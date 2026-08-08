'use client';
// Spec §19 — the Supply Chain Map. "Supplier Factory -> Warehouse -> Project Site", animated, with
// a live status.
//
// ── WHAT THIS IS ALLOWED TO CLAIM, MEASURED ─────────────────────────────────────────────────────
// Production, 6 Aug 2026: NO relation in public carries a shipping origin and a destination on the
// same row. Not one. po_orders — the only order store — holds po_no, order_date, expected_date, a
// CHECK-constrained status, a vendor, a customer, an inquiry, a quote and a project. There is no
// coordinate, no origin, no destination, and NO WAREHOUSE TABLE AT ALL.
//
// So this is a STAGE map, not a geographic route, and it says so on the surface in both languages.
// The two nodes it draws are the two the data can evidence — the supplier the order was placed
// with, and the customer's own site — and the middle hop is drawn as the transit the order status
// already reports, never as a warehouse whose existence nothing records. Drawing a factory pin and
// a warehouse pin on a map would be the same lie as the empty state this portal was repaired for.
//
// The marker's position along the track comes from chainLegs(): the order's own status, and for a
// partial delivery its real received/ordered quantity ratio. Nothing here interpolates by clock.
//
// It reads the order store through procurement_api action:'orders' (fn_customer_orders), which is
// what puts po_orders on a customer's screen from this surface — see ./api.ts#fetchOrders. The
// Orders module reads the same endpoint for its list; both derive from the same served fields, so
// a status shown there and a marker shown here cannot disagree.
import { useMemo } from 'react';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { chainLegs, fmtDate, money, CHAIN_LABEL, type ChainStage, type CustomerOrder, type Lang } from './model';
import { tx } from './strings';

export interface SupplyChainMapProps {
  orders: CustomerOrder[];
  lang?: Lang;
  /** Called with the order's inquiry_id so the portal can open the request behind a shipment. */
  onOpenRfq?: (rfqId: string) => void;
}

const STAGE_TONE: Record<ChainStage, string> = {
  placed: 'bg-slate-400',
  approved: 'bg-sky-400',
  in_transit: 'bg-amber-400',
  arrived: 'bg-emerald-400',
  cancelled: 'bg-red-400',
};

export function SupplyChainMap({ orders, lang = 'en', onOpenRfq }: SupplyChainMapProps) {
  const legs = useMemo(() => chainLegs(orders || []), [orders]);

  return (
    <Card className="p-4 md:p-5 bg-card/70 backdrop-blur border-border">
      <div className="text-[15px] font-bold text-foreground">{tx(lang, 'chain_title')}</div>
      <div className="text-[13px] text-muted-foreground">{tx(lang, 'chain_sub')}</div>

      {legs.length === 0 ? (
        <div className="mt-3 rounded-lg border border-dashed border-border bg-secondary/20 p-5 text-[13px] leading-relaxed text-muted-foreground">
          {tx(lang, 'chain_empty')}
        </div>
      ) : (
        <div className="mt-3 flex flex-col gap-3">
          {(orders || []).map((o, idx) => {
            const g = legs[idx];
            if (!g) return null;
            const moving = g.stage === 'in_transit';
            return (
              <div key={g.orderId} className="rounded-lg border border-border bg-secondary/20 p-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <span className="text-[13px] font-semibold text-foreground">{o.po_no || `#${o.id}`}</span>
                    <Badge variant="secondary">{CHAIN_LABEL[lang][g.stage]}</Badge>
                    <span className="text-[11.5px] text-muted-foreground capitalize">{o.status}</span>
                  </div>
                  <div className="text-[11.5px] text-muted-foreground">
                    {tx(lang, 'chain_expected')}: {fmtDate(o.expected_date, lang)}
                    {o.subtotal == null ? '' : ' · ' + money(o.subtotal, o.currency || 'AED')}
                  </div>
                </div>

                {/* The track: 3 labelled stops and one marker whose LEFT offset is the derived
                    position — the animation is a CSS transition on that offset, so the marker
                    travels when a real status or a real received quantity changes, and stands
                    still when nothing has. Nothing moves on a timer. */}
                <div className="mt-3">
                  <div className="relative h-2 rounded-full bg-border/70">
                    <div
                      className={cn('absolute inset-y-0 left-0 rounded-full transition-[width] duration-700 ease-out', STAGE_TONE[g.stage])}
                      style={{ width: `${Math.round(g.progress * 100)}%` }}
                    />
                    <span
                      className={cn(
                        'absolute -top-1 h-4 w-4 -translate-x-1/2 rounded-full border-2 border-background shadow transition-[left] duration-700 ease-out',
                        STAGE_TONE[g.stage], moving && 'animate-pulse',
                      )}
                      style={{ left: `${Math.round(g.progress * 100)}%` }}
                    />
                  </div>
                  <div className="mt-1.5 flex justify-between text-[11px] text-muted-foreground">
                    <span>{tx(lang, 'chain_node_supplier')}</span>
                    <span className={cn(moving && 'text-foreground font-semibold')}>{tx(lang, 'chain_node_transit')}</span>
                    <span>{tx(lang, 'chain_node_site')}</span>
                  </div>
                </div>

                <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11.5px] text-muted-foreground">
                  {g.received == null
                    ? <span>{tx(lang, 'chain_no_qty')}</span>
                    : <span className="text-foreground/85">{Math.round(g.received * 100)}% {tx(lang, 'chain_received')}</span>}
                  <span>{g.lineCount} {tx(lang, 'chain_lines')}</span>
                  {o.inquiry_id && onOpenRfq ? (
                    <button className="text-primary font-semibold transition-colors hover:text-primary/80" onClick={() => onOpenRfq(String(o.inquiry_id))}>
                      {tx(lang, 'sel_open_rfq')}
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="mt-3 text-[11.5px] leading-relaxed text-muted-foreground">{tx(lang, 'chain_caveat')}</div>
    </Card>
  );
}
