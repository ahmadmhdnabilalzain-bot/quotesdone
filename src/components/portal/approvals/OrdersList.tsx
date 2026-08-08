'use client';
/**
 * ORDERS — customer portal spec §22, the "Orders" module, and the 📦 Orders entry in the spec's own
 * navigation.
 *
 * WHERE EVERY VALUE COMES FROM. supabase/functions/procurement_api action:'orders', customer-authed,
 * which calls fn_customer_orders(customer) — public.po_orders filtered on customer_id, with
 * public.po_lines nested. Until 6 Aug 2026 po_orders had no customer column at all and no customer
 * could be shown an order even in principle; the column, the FK and the derivation trigger were
 * added by the approvals-and-orders backend phase and this is the first surface to read them.
 *
 * vendor_id is deliberately NOT served and therefore not rendered: it points at the company's AP
 * vendor master, and supplier identity in this product is reveal-gated.
 *
 * WHAT A CUSTOMER SEES TODAY. Both projects hold ZERO po_orders rows and nothing writes a customer
 * order yet, so this renders the empty state on every load. It says exactly that — no order has been
 * placed, delivered or invoiced — and never implies that something is in progress.
 *
 * THE TWO NUMBERS THIS FILE REFUSES TO GUESS, both in ./model and both executed by model.test.mjs:
 *   orderValue  — po_orders.subtotal is the authority. Lines are summed only when subtotal is
 *                 absent AND every line is priced, because a sum over the priced half of an order
 *                 is a smaller number than the order.
 *   receivedPct — null, not 0%, when no line has a recorded receipt. "Nothing was recorded" and
 *                 "nothing arrived" are different facts about someone's money.
 */
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { call } from './api';
import { fmtDate, money, numOrNull, orderValue, receivedPct, type CustomerOrder, type Lang } from './model';
import { errText, tr } from './strings';

/* ── pieces ───────────────────────────────────────────────────────────────────────────────── */

/** One measured figure. `empty` says WHY there is nothing, never a cheerful zero. */
function Field({ label, value, empty }: { label: string; value?: React.ReactNode; empty?: string }) {
  const missing = value === undefined || value === null || value === '';
  return (
    <div>
      <dt className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className={cn('mt-0.5 text-[13.5px] font-bold', missing ? 'text-muted-foreground' : 'text-foreground')}>
        {missing ? empty || '—' : value}
      </dd>
    </div>
  );
}

const ORDER_TONE: Record<string, 'ok' | 'warn' | 'destructive' | 'secondary'> = {
  received: 'ok',
  closed: 'ok',
  approved: 'ok',
  open: 'warn',
  sent: 'warn',
  draft: 'secondary',
  cancelled: 'destructive',
};

/** The line items of one order. Quantities and prices are printed as recorded, never reconciled. */
function OrderLines({ order, lang }: { order: CustomerOrder; lang: Lang }) {
  const lines = Array.isArray(order.lines) ? order.lines : [];
  if (!lines.length) return <p className="mt-2 text-[12px] text-muted-foreground">{tr(lang, 'no_lines')}</p>;
  const currency = order.currency || 'AED';
  return (
    <ul className="mt-2 flex list-none flex-col gap-1.5 p-0">
      {lines.map((l, i) => {
        const qty = numOrNull(l.qty);
        const price = numOrNull(l.unit_price);
        const got = numOrNull(l.qty_received);
        return (
          <li key={`${order.id}:${l.line_no ?? i}`} className="rounded-md border border-border bg-white/[0.02] px-3 py-2">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="text-[13px] text-foreground">{l.description || `#${l.line_no ?? i + 1}`}</span>
              <span className="text-[12.5px] tabular-nums text-muted-foreground">
                {qty === null ? '—' : qty}
                {price === null ? '' : ` × ${money(price, currency, lang)}`}
              </span>
            </div>
            {qty !== null && got !== null ? (
              <p className="mt-0.5 text-[11.5px] text-muted-foreground">{tr(lang, 'qty_of')(String(got), String(qty))}</p>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

/* ── the surface the integrator mounts ────────────────────────────────────────────────────── */

export interface OrdersListProps {
  /** Customer Supabase JWT — the token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Called with inquiries.id when an order's originating RFQ is opened. Omit to hide the control. */
  onOpenRfq?: (inquiryId: string) => void;
  className?: string;
}

export function OrdersList({ token, lang = 'en', onOpenRfq, className }: OrdersListProps) {
  const [orders, setOrders] = React.useState<CustomerOrder[] | null>(null);
  const [error, setError] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    let live = true;
    setOrders(null);
    setError('');
    call('procurement_api', { action: 'orders' }, token).then((res) => {
      if (!live) return;
      if (!res.ok) {
        setError(errText(lang, res.error));
        setOrders([]);
        return;
      }
      // The one cast, at the wire boundary. ./model is the transcription of what fn_customer_orders
      // actually emits; nothing below re-derives a field it does not serve.
      const list = res.data.orders as CustomerOrder[] | undefined;
      setOrders(Array.isArray(list) ? list : []);
    });
    return () => {
      live = false;
    };
  }, [token, lang, reloads]);

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'} aria-labelledby="qd-orders">
      <header>
        <h2 id="qd-orders" className="text-xl font-extrabold text-foreground">
          {tr(lang, 'orders')}
        </h2>
        <p className="mt-1 text-[13px] text-muted-foreground">{tr(lang, 'orders_sub')}</p>
      </header>

      {error ? (
        <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-3.5 py-2.5 text-[13px] text-destructive">
          <span className="font-semibold">
            {tr(lang, 'err_load_orders')} {error}
          </span>
          <Button type="button" size="sm" variant="outline" onClick={() => setReloads((n) => n + 1)}>
            {tr(lang, 'retry')}
          </Button>
        </div>
      ) : null}

      {/* `error ? null` before the empty state: an empty state printed over a failure tells the
          customer nothing has happened when the truth is that we could not ask. */}
      {orders === null ? (
        <>
          <p className="sr-only" role="status">
            {tr(lang, 'loading_orders')}
          </p>
          <Skeleton className="h-[148px] w-full rounded-lg" aria-hidden="true" />
        </>
      ) : error ? null : orders.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border bg-white/[0.02] px-5 py-8 text-center">
          <h3 className="text-[15px] font-bold text-foreground">{tr(lang, 'empty_orders_title')}</h3>
          <p className="mx-auto mt-2 max-w-[62ch] text-[13px] leading-relaxed text-muted-foreground">
            {tr(lang, 'empty_orders_body')}
          </p>
        </div>
      ) : (
        <ul className="flex list-none flex-col gap-3 p-0">
          {orders.map((o) => {
            const value = orderValue(o);
            const got = receivedPct(o.lines);
            return (
              <li key={o.id}>
                <Card className="p-4">
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div>
                      <h3 className="text-[15px] font-bold text-foreground">{o.po_no || o.id}</h3>
                      {o.memo ? <p className="mt-0.5 text-[12px] text-muted-foreground">{o.memo}</p> : null}
                    </div>
                    {o.status ? <Badge variant={ORDER_TONE[o.status] ?? 'secondary'}>{o.status}</Badge> : null}
                  </div>

                  <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
                    <Field label={tr(lang, 'k_ordered')} value={fmtDate(o.order_date, lang)} empty={tr(lang, 'date_unknown')} />
                    <Field label={tr(lang, 'k_expected')} value={fmtDate(o.expected_date, lang)} empty={tr(lang, 'date_unknown')} />
                    <Field
                      label={tr(lang, 'k_value')}
                      value={value === null ? undefined : money(value, o.currency || 'AED', lang)}
                      empty={tr(lang, 'value_unknown')}
                    />
                    <Field
                      label={tr(lang, 'k_received')}
                      value={got === null ? undefined : `${got}%`}
                      empty={tr(lang, 'received_unknown')}
                    />
                  </dl>

                  {value === null ? (
                    <p className="mt-2 text-[11.5px] text-muted-foreground">{tr(lang, 'value_unknown_note')}</p>
                  ) : null}

                  {o.approved_at ? (
                    <p className="mt-2 text-[11.5px] text-muted-foreground">
                      {tr(lang, 'approved_on')} {fmtDate(o.approved_at, lang)}
                    </p>
                  ) : null}

                  <OrderLines order={o} lang={lang} />

                  {onOpenRfq && o.inquiry_id ? (
                    <Button type="button" size="sm" variant="outline" className="mt-3" onClick={() => onOpenRfq(String(o.inquiry_id))}>
                      {tr(lang, 'linked_rfq')}
                    </Button>
                  ) : null}
                </Card>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

export default OrdersList;
