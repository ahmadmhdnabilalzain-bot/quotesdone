'use client';
/**
 * PREDICTIVE INTELLIGENCE — customer portal spec §20.
 *
 * The spec's own example is the shape this renders:
 *   "Based on your projects: you will likely need Electrical cables within 45 days.
 *    Recommended: contact suppliers now."
 *
 * WHERE EVERY VALUE COMES FROM. supabase/functions/customer_intelligence action:'forecast',
 * customer-authed, which calls fn_customer_forecast(customer, horizon_days). That routine derives
 * each prediction from the customer's OWN history and nothing else: for every open project with a
 * target open date, the trades they have procured on their OTHER projects and have not yet raised
 * here, with within_days = (days to that project's deadline − the median lead time this customer
 * has actually observed in that trade). The `reason` and `recommended_action` sentences on each
 * card are the routine's, not this file's — a prediction and the advice attached to it must not be
 * able to disagree because a component reworded one of them.
 *
 * fn_finance_forecast() takes no arguments and projects the COMPANY's cash. It is not, and cannot
 * be scoped to be, a prediction about a customer. Nothing here reads it.
 *
 * WHAT A CUSTOMER SEES TODAY. Production holds zero customers and zero inquiries, so the routine
 * answers basis='no_history' with an empty_reason sentence, series [] and every projected figure
 * null. This renders that sentence. It draws no chart from an empty series and prints no zero where
 * a projection was withheld — a flat line at zero reads as a business that bought nothing, which is
 * a claim about the customer rather than an absence of data about them.
 */
import * as React from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { call } from './api';
import { aed, fmtDate, numOrNull, projection, urgency, type Forecast, type Lang, type Prediction } from './model';
import { Empty, Field } from './parts';
import { confidenceLabel, errText, tr, urgencyLabel } from './strings';

/* ── pieces ───────────────────────────────────────────────────────────────────────────────── */

const URGENCY_TONE = { now: 'destructive', soon: 'warn', planned: 'secondary' } as const;

/**
 * One predicted requirement. Every sentence on it is the routine's own — the card supplies the
 * layout and the badge, and nothing else.
 */
function PredictionCard({ prediction, lang }: { prediction: Prediction; lang: Lang }) {
  const level = urgency(prediction.within_days);
  return (
    <Card className="p-4 transition-colors hover:border-primary/40">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <h4 className="text-[15px] font-bold text-foreground">{categoryLabel(prediction.category, lang)}</h4>
          <p className="mt-0.5 text-[12px] text-muted-foreground">
            {tr(lang, 'p_for')} {prediction.project_name}
          </p>
        </div>
        <Badge variant={URGENCY_TONE[level]}>{urgencyLabel(lang, level)}</Badge>
      </div>

      <p className="mt-2.5 text-[16px] font-bold text-foreground">{tr(lang, 'p_within')(Number(prediction.within_days) || 0)}</p>
      <p className="mt-0.5 text-[12px] text-muted-foreground">
        {tr(lang, 'p_by')} {fmtDate(prediction.expected_by, lang)} · {tr(lang, 'p_confidence')}:{' '}
        {confidenceLabel(lang, prediction.confidence)}
      </p>

      <p className="mt-2.5 text-[12.5px] leading-relaxed text-muted-foreground">
        <span className="font-semibold text-foreground">{tr(lang, 'p_why')}: </span>
        {prediction.reason}
      </p>
      <p className="mt-2 rounded-lg border border-primary/35 bg-primary/10 px-3 py-2 text-[13px] leading-relaxed text-primary">
        <span className="font-bold">{tr(lang, 'p_action')}: </span>
        {prediction.recommended_action}
      </p>
    </Card>
  );
}

/**
 * The next-year run-rate projection, shown beside the actuals it was derived from.
 *
 * The projection is rendered ONLY when fn_customer_forecast says the account clears its own floor
 * (3 requests across 2 active months). Below it the routine returns nulls and a sentence saying so,
 * and that sentence is what appears — never a doubled single data point wearing a forecast label.
 */
function ForecastPanel({ forecast, lang }: { forecast: Forecast; lang: Lang }) {
  const proj = projection(forecast);
  const { projected_rfqs, projected_spend_aed, by_category } = forecast.next_year || { projected_rfqs: null, projected_spend_aed: null, by_category: [] };
  const observed = forecast.observed || { rfqs: 0, months_active: 0, spend_aed: 0, first_rfq: null, last_rfq: null };
  const horizon = numOrNull(forecast.next_year?.horizon_days) ?? numOrNull(forecast.horizon_days) ?? 365;

  return (
    <Card className="p-4">
      <h3 className="text-[14px] font-bold text-foreground">{tr(lang, 'fc_title')}</h3>
      <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">{tr(lang, 'fc_sub')(horizon)}</p>

      <div className="mt-3 grid gap-2.5 sm:grid-cols-2 lg:grid-cols-4">
        <Field label={tr(lang, 'fc_observed')} value={observed.rfqs || undefined} empty={forecast.empty_reason || undefined} />
        <Field label={tr(lang, 'fc_observed_spend')} value={observed.spend_aed ? aed(Number(observed.spend_aed), lang) : undefined} />
        <Field
          label={tr(lang, 'fc_rfqs')}
          value={proj ? projected_rfqs : undefined}
          empty={tr(lang, 'fc_not_projected')}
        />
        <Field
          label={tr(lang, 'fc_spend')}
          value={proj ? aed(Number(projected_spend_aed), lang) : undefined}
          empty={tr(lang, 'fc_not_projected')}
        />
      </div>

      {!proj && forecast.empty_reason ? (
        <p className="mt-2.5 rounded-lg border border-border bg-secondary/30 px-3 py-2.5 text-[12.5px] leading-relaxed text-muted-foreground">
          {forecast.empty_reason}
        </p>
      ) : null}

      {Array.isArray(by_category) && by_category.length ? (
        <div className="mt-3">
          <h4 className="text-[12px] font-semibold uppercase tracking-wide text-muted-foreground">{tr(lang, 'fc_by_category')}</h4>
          <ul className="mt-1.5 flex list-none flex-col gap-1.5 p-0">
            {by_category.map((c) => (
              <li key={c.category} className="flex flex-wrap items-baseline justify-between gap-2 rounded-md border border-border bg-white/[0.02] px-3 py-2">
                <span className="text-[13px] text-foreground">{categoryLabel(c.category, lang)}</span>
                <span className="text-[12px] tabular-nums text-muted-foreground">
                  {c.share_pct === null || c.share_pct === undefined ? '' : `${c.share_pct}% ${tr(lang, 'fc_share')} · `}
                  {c.projected_spend_aed === null || c.projected_spend_aed === undefined
                    ? tr(lang, 'fc_not_projected')
                    : aed(Number(c.projected_spend_aed), lang)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </Card>
  );
}

/* ── the surface the integrator mounts ────────────────────────────────────────────────────── */

export interface PredictiveIntelligenceProps {
  /** Customer Supabase JWT — the token CustomerPortal already holds. */
  token: string;
  lang?: Lang;
  /** Forecast horizon in days. fn_customer_forecast accepts 1..1095 and defaults to 365. */
  horizonDays?: number;
  className?: string;
}

export function PredictiveIntelligence({ token, lang = 'en', horizonDays = 365, className }: PredictiveIntelligenceProps) {
  const [forecast, setForecast] = React.useState<Forecast | null>(null);
  const [error, setError] = React.useState('');
  const [reloads, setReloads] = React.useState(0);

  React.useEffect(() => {
    let live = true;
    setForecast(null);
    setError('');
    call('customer_intelligence', { action: 'forecast', horizon_days: horizonDays }, token).then((res) => {
      if (!live) return;
      if (!res.ok) {
        setError(errText(lang, res.error));
        return;
      }
      // The one cast, at the wire boundary. ./model is the transcription of what
      // fn_customer_forecast actually emits; nothing below re-derives a field it does not serve.
      // An ok answer without a forecast object would otherwise leave forecast === null, which this
      // component reads as "still loading" — the loader would never end. Say it failed instead.
      const f = res.data.forecast as Forecast | undefined;
      if (!f || typeof f !== 'object') {
        setError(errText(lang, 'no_forecast'));
        return;
      }
      setForecast(f);
    });
    return () => {
      live = false;
    };
  }, [token, lang, horizonDays, reloads]);

  const predictions = forecast?.predictions ?? [];

  return (
    <section className={cn('flex flex-col gap-4', className)} dir={lang === 'ar' ? 'rtl' : 'ltr'} aria-labelledby="qd-predict">
      <header>
        {/* ModuleWindow already renders "What you may need next" as the h1. This heading also said
            "What you WILL need next" one line under a nav item that says "may" - a forecast built
            from an account with no history does not get to promise. See the note in OrdersList. */}
        <p id="qd-predict" className="max-w-[76ch] text-[13px] leading-relaxed text-muted-foreground">{tr(lang, 'predict_sub')}</p>
      </header>

      {error ? (
        <div role="alert" className="flex flex-wrap items-center gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-3.5 py-2.5 text-[13px] text-destructive">
          <span className="font-semibold">
            {tr(lang, 'err_load')} {error}
          </span>
          <Button type="button" size="sm" variant="outline" onClick={() => setReloads((n) => n + 1)}>
            {tr(lang, 'retry')}
          </Button>
        </div>
      ) : null}

      {forecast === null && !error ? (
        <>
          <p className="text-[12.5px] text-muted-foreground" role="status">
            {tr(lang, 'loading_predict')}
          </p>
          <Skeleton className="h-[168px] w-full rounded-lg" aria-hidden="true" />
        </>
      ) : forecast ? (
        <>
          {predictions.length === 0 ? (
            <Empty
              title={
                forecast.basis === 'no_history'
                  ? (tr(lang, 'empty_no_history_title') as string)
                  : (tr(lang, 'empty_no_predictions_title') as string)
              }
              // The routine's own sentence when it has one — it knows which absence is true.
              body={forecast.basis === 'no_history' && forecast.empty_reason ? forecast.empty_reason : (tr(lang, 'empty_no_predictions_body') as string)}
            />
          ) : (
            <ul className="grid list-none gap-3 p-0 sm:grid-cols-2">
              {predictions.map((p) => (
                <li key={`${p.project_id}:${p.category}`}>
                  <PredictionCard prediction={p} lang={lang} />
                </li>
              ))}
            </ul>
          )}
          <ForecastPanel forecast={forecast} lang={lang} />
        </>
      ) : null}
    </section>
  );
}

export default PredictiveIntelligence;
