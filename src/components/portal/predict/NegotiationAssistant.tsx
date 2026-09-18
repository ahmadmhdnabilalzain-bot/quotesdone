'use client';
/**
 * NEGOTIATION ASSISTANT — customer portal spec §15.
 *
 * The spec's own example is the shape this renders:
 *   Quote $850,000 → Market analysis: average $790,000 → Recommended action: negotiate 5-7%
 *   reduction → Suggested message: "Can you improve pricing based on project volume?"
 *
 * WHERE EVERY VALUE COMES FROM. supabase/functions/negotiation_assistant action:'guidance',
 * customer-authed, which calls fn_negotiation_guidance(customer, quote). Ownership is re-checked in
 * SQL, so a quote id belonging to someone else is refused by the database and not only by the
 * handler. That routine joins fn_price_confidence / public.category_price_stats (the market median,
 * p25, p75 and sample size, which had no customer-authed reader at all before 6 Aug 2026) to
 * public.supplier_negotiation_policy, and emits the band, the delta against the median, the house
 * policy's recommended action, a policy-bounded target price and a message drafted in English and
 * Arabic. Every one of those is rendered here as it arrived.
 *
 * THE ONE THING THIS FILE DECIDES, and it decides it towards silence: `marketComparison` in ./model
 * refuses to present a market position when the backend's own band is 'insufficient_data'. The
 * routine still returns a median and a delta off a thin sample while withholding the target price;
 * printing "12% above market" from two comparable quotes would be a confident sentence with nothing
 * behind it — the same defect as the empty state that claimed suppliers had been matched whether or
 * not any were. The routine's headline sentence, which says how thin the sample is, appears instead.
 *
 * WHAT A CUSTOMER SEES TODAY. Production holds zero quotes, so category_price_stats is empty and
 * every call answers band='insufficient_data' with no target price and no discount figure. The
 * drafted message in that state asks the supplier to confirm scope, lead time, payment terms and
 * warranty — which is real, sendable and honest — and no market number is shown.
 */
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { call } from './api';
import { aed, marketComparison, numOrNull, type Lang, type Negotiation } from './model';
import { Empty, Field } from './parts';
import { errText, tr } from './strings';

/* ── pieces ───────────────────────────────────────────────────────────────────────────────── */

/** A drafted message, shown in full and copyable. Never truncated — the customer sends this text. */
function DraftMessage({ label, body, lang }: { label: string; body: string; lang: Lang }) {
  const [copied, setCopied] = React.useState(false);
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(body);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      // Clipboard permission refused. The text is on screen and selectable, so say nothing rather
      // than raise an error about a convenience.
    }
  };
  return (
    <div className="rounded-lg border border-border bg-white/[0.02] p-3.5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-[12px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</h4>
        {/* A clipboard write is instant, so under the loading rules no spinner may ever show here —
            what was missing is the CONFIRMATION, and a label that only changes visually confirms
            nothing to a screen reader. aria-live carries the swap. */}
        <Button type="button" size="sm" variant="outline" onClick={() => void copy()}>
          <span aria-live="polite">{copied ? tr(lang, 'n_copied') : tr(lang, 'n_copy')}</span>
        </Button>
      </div>
      <p className="mt-2 whitespace-pre-wrap text-[13px] leading-relaxed text-foreground">{body}</p>
    </div>
  );
}

/* ── the surface the integrator mounts ────────────────────────────────────────────────────── */

export interface NegotiationAssistantProps {
  /** Customer Supabase JWT — the token CustomerPortal already holds. */
  token: string;
  /** public.quotes.id of a quote on one of this customer's own RFQs. Null renders the prompt state. */
  quoteId?: string | null;
  lang?: Lang;
  className?: string;
}

export function NegotiationAssistant({ token, quoteId, lang = 'en', className }: NegotiationAssistantProps) {
  const [negotiation, setNegotiation] = React.useState<Negotiation | null>(null);
  const [error, setError] = React.useState('');
  // The raw code, kept OFF the screen and ON the element. Support can read it from the DOM or a
  // screenshot's tooltip; the customer reads a sentence. See errText in ./strings for what was
  // on this screen before.
  const [errCode, setErrCode] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    if (!quoteId) {
      setNegotiation(null);
      setError('');
      return;
    }
    let live = true;
    setNegotiation(null);
    setError('');
    setErrCode('');
    call('negotiation_assistant', { action: 'guidance', quote_id: quoteId }, token).then((res) => {
      if (!live) return;
      // The code is stored and phrased at render time, so switching language re-words the error
      // instead of re-fetching guidance the server answers identically in both languages.
      if (!res.ok) {
        setError(String(res.error || 'error'));
        setErrCode(String(res.error || ''));
        return;
      }
      // The one cast, at the wire boundary. ./model is the transcription of what
      // fn_negotiation_guidance actually emits; nothing below re-derives a field it does not serve.
      // An ok answer with no object is an error, not "still loading" — that left a skeleton forever.
      const n = res.data.negotiation as Negotiation | undefined;
      if (!n || typeof n !== 'object') { setError('no_response'); setErrCode('no_response'); return; }
      setNegotiation(n);
    });
    return () => {
      live = false;
    };
  }, [token, quoteId, reloads]);

  const market = marketComparison(negotiation);
  const amount = numOrNull(negotiation?.quote_amount);
  const target = numOrNull(negotiation?.target_price);

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'} aria-labelledby="qd-negotiation">
      <header>
        <h2 id="qd-negotiation" className="text-xl font-extrabold text-foreground">
          {tr(lang, 'neg')}
        </h2>
        <p className="mt-1 max-w-[76ch] text-[13px] leading-relaxed text-muted-foreground">{tr(lang, 'neg_sub')}</p>
      </header>

      {error ? (
        <div role="alert" title={errCode || undefined}
          className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-3.5 py-2.5 text-[13px] text-destructive">
          <span className="font-semibold">
            {tr(lang, 'err_load_neg')} {errText(lang, error)}
          </span>
          <Button type="button" size="sm" variant="outline" onClick={() => setReloads((n) => n + 1)}>
            {tr(lang, 'retry')}
          </Button>
        </div>
      ) : null}

      {!quoteId ? (
        <Empty title={tr(lang, 'empty_no_quote_title') as string} body={tr(lang, 'empty_no_quote_body') as string} />
      ) : negotiation === null && !error ? (
        <>
          <p className="sr-only" role="status">
            {tr(lang, 'loading_neg')}
          </p>
          <Skeleton className="h-[188px] w-full rounded-lg" aria-hidden="true" />
        </>
      ) : negotiation ? (
        <Card className="p-4">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div>
              <h3 className="text-[15px] font-bold text-foreground">
                {negotiation.supplier_name || (negotiation.category ?? tr(lang, 'n_quote'))}
              </h3>
              {negotiation.supplier_name ? null : (
                <p className="mt-0.5 text-[11.5px] text-muted-foreground">{tr(lang, 'n_supplier_locked')}</p>
              )}
            </div>
            {negotiation.band ? <Badge variant={market ? 'warn' : 'secondary'}>{String(negotiation.band).replace(/_/g, ' ')}</Badge> : null}
          </div>

          {/* The routine's own sentence. It states the sample size when there is no benchmark, so it
              is the honest headline in exactly the state production is in. */}
          {negotiation.headline ? (
            <p className="mt-2 text-[13.5px] leading-relaxed text-foreground">{negotiation.headline}</p>
          ) : null}

          <div className="mt-3 grid gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
            <Field label={tr(lang, 'n_quote')} value={amount === null ? undefined : aed(amount, lang)} />
            <Field
              label={tr(lang, 'n_market')}
              value={market ? aed(market.median, lang) : undefined}
              hint={market ? (tr(lang, 'n_sample')(market.sampleN) as string) : undefined}
              empty={tr(lang, 'n_no_benchmark_title') as string}
            />
            <Field
              label={tr(lang, 'n_action')}
              value={negotiation.recommended_action ? String(negotiation.recommended_action).replace(/_/g, ' ') : undefined}
              hint={negotiation.policy_scope ? `${tr(lang, 'n_policy_scope')}: ${negotiation.policy_scope}` : undefined}
            />
            <Field
              label={tr(lang, 'n_target')}
              value={target === null ? undefined : aed(target, lang)}
              hint={
                negotiation.ask_discount_pct === null || negotiation.ask_discount_pct === undefined
                  ? undefined
                  : `−${negotiation.ask_discount_pct}%`
              }
              empty={tr(lang, 'n_no_target') as string}
            />
          </div>

          {market ? (
            <p className="mt-2.5 text-[12.5px] text-muted-foreground">
              {`${Math.abs(market.deltaPct)}% `}
              {market.direction === 'above'
                ? tr(lang, 'n_above')
                : market.direction === 'below'
                  ? tr(lang, 'n_below')
                  : tr(lang, 'n_level')}
            </p>
          ) : null}

          {negotiation.empty_reason ? (
            <p className="mt-2.5 rounded-lg border border-border bg-secondary/30 px-3 py-2.5 text-[12.5px] leading-relaxed text-muted-foreground">
              {negotiation.empty_reason}
            </p>
          ) : null}

          <div className="mt-3 grid gap-2.5 lg:grid-cols-2">
            {negotiation.suggested_message ? (
              <DraftMessage label={tr(lang, 'n_message') as string} body={negotiation.suggested_message} lang={lang} />
            ) : null}
            {negotiation.suggested_message_ar ? (
              <DraftMessage label={tr(lang, 'n_message_ar') as string} body={negotiation.suggested_message_ar} lang={lang} />
            ) : null}
          </div>
        </Card>
      ) : null}
    </section>
  );
}

export default NegotiationAssistant;
