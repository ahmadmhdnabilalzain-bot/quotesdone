'use client';
/**
 * SPENDING INTELLIGENCE — customer portal spec §11 (Interactive Data Visualization).
 *
 * The customer product contained zero charts. recharts and src/components/ui/chart.tsx were both
 * installed with no importers, and fn_customer_stats has been computing a 12-point history_12m
 * series on every customer_portal overview call that nothing rendered.
 *
 * EVERY number here comes from a field an endpoint already returns:
 *   - history_12m, inquiries[]   ← fn_customer_stats, served by customer_portal action=overview
 *   - inquiries[].quotes[].price ← customer_api action=my_inquiries
 * Nothing is estimated, forecast, or inferred. The parts of §11 that no customer-facing endpoint
 * can currently supply — annual procurement totals, the forecast, supplier-performance graphs —
 * are absent rather than approximated.
 *
 * EMPTY STATES ARE LOAD-BEARING. Production has zero customers and zero inquiries, so history_12m
 * comes back as twelve zeros. A flat line at zero looks like a real, quiet year. Every surface here
 * therefore checks whether there is anything to draw and SAYS what is true instead of drawing it —
 * and "no requests at all" is worded differently from "requests, but not enough quotes to compare",
 * because those are different facts. The arithmetic behind that distinction is in stats.ts, which
 * spread.test.mjs executes.
 *
 * ACCESSIBILITY. Each chart is role="img" labelled by a VISIBLE caption carrying the same
 * information as the drawing, month by month and category by category — so the data survives with
 * no colour, no pointer and no sight. Categories are printed on the axis, never encoded in colour
 * alone, and every bar carries its own value as text.
 */
import * as React from 'react';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, LabelList, XAxis, YAxis } from 'recharts';
import { Card } from '@/components/ui/card';
import { ChartContainer, ChartTooltip, ChartTooltipContent, type ChartConfig } from '@/components/ui/chart';
import { cn } from '@/lib/utils';
import { categoryLabel } from '@/lib/categoryLabel';
import { arCount, AR_NOUN } from '@/lib/countedNoun';
import {
  countByCategory,
  num,
  spreadByCategory,
  summariseHistory,
  monthLabel,
  type HistoryPoint,
  type PortalInquiry,
  type PortalQuote,
  type StatsInquiry,
} from './stats';

export type { HistoryPoint, PortalInquiry, PortalQuote, StatsInquiry };

/** The fn_customer_stats payload, i.e. `overview.stats`. */
export type CustomerStats = {
  inquiries_total?: number | null;
  open_inquiries?: number | null;
  quotes_received?: number | null;
  avg_quotes_per_inquiry?: number | null;
  deals?: number | null;
  total_spend?: number | null;
  inquiries?: StatsInquiry[] | null;
  history_12m?: HistoryPoint[] | null;
};

export type Lang = 'en' | 'ar';

/* ── copy ─────────────────────────────────────────────────────────────────────────────────── */

const T = {
  en: {
    section: 'Spending intelligence',
    section_sub: 'Computed from your own requests and the quotes you received. Nothing here is estimated.',
    trend_title: 'Requests over the last 12 months',
    trend_note: 'Counts the requests you posted, by the month you posted them.',
    trend_missing: 'Your 12-month history has not loaded yet.',
    trend_empty:
      'You have not posted a request in the last 12 months, so there is no trend to draw yet. This chart fills in from your first request.',
    trend_alt: (total: number, dir: string, peak: string, peakN: number, months: string) =>
      `${total} request${total === 1 ? '' : 's'} in the last 12 months, ${dir}. Busiest month ${peak} with ${peakN}. Month by month: ${months}.`,
    dir_rising: 'rising over the year',
    dir_falling: 'falling over the year',
    dir_steady: 'steady over the year',
    dir_single: 'all in a single month so far',
    cat_title: 'Requests by category',
    cat_note: 'How your requests split across trades.',
    cat_empty: 'You have no requests yet, so there is nothing to break down by category.',
    cat_missing: 'Your category breakdown has not loaded yet.',
    cat_alt: (pairs: string) => `Requests by category: ${pairs}.`,
    gap_title: 'Quote spread by category',
    gap_note:
      'On each request with two or more quotes, the gap between the highest and the lowest quote, added up per category. This is what comparing quotes was worth to you — not a discount any supplier offered.',
    gap_empty_none: 'You have no requests yet, so there are no quotes to compare.',
    gap_missing: 'Your requests are still loading, so the quote spread is not shown yet.',
    gap_empty_thin:
      'None of your requests has two or more quotes yet. A spread needs at least two quotes on the same request to measure, so there is nothing to show.',
    gap_alt: (pairs: string, total: string, n: number) =>
      `Gap between the highest and lowest quote, by category: ${pairs}. Total ${total} across ${n} request${n === 1 ? '' : 's'} that received two or more quotes.`,
    gap_total: (v: string, n: number) => `Total spread across ${n} request${n === 1 ? '' : 's'}: ${v}`,
    uncategorised: 'Not categorised',
    more: (n: number) => `${n} smaller categor${n === 1 ? 'y is' : 'ies are'} not drawn; all of them are listed in the summary above.`,
    k_requests: 'Requests',
    k_spread: 'Spread',
    recent_note: 'Covers the 25 most recent requests, which is what the portal loads.',
  },
  ar: {
    section: 'تحليلات الإنفاق',
    section_sub: 'أرقام محسوبة من طلباتك والعروض التي استلمتها، ولا شيء منها تقديري.',
    trend_title: 'الطلبات خلال آخر 12 شهرًا',
    trend_note: 'عدد الطلبات التي نشرتها، حسب شهر النشر.',
    trend_missing: 'لم يُحمَّل سجل الاثني عشر شهرًا بعد.',
    trend_empty: 'لم تنشر أي طلب خلال آخر 12 شهرًا، فلا اتجاه يُعرض بعد. يبدأ الرسم البياني بالامتلاء مع أول طلب تنشره.',
    trend_alt: (total: number, dir: string, peak: string, peakN: number, months: string) =>
      `${arCount(total, AR_NOUN.request)} خلال آخر 12 شهرًا، ${dir}. أنشط الأشهر ${peak} بعدد ${peakN}. التوزيع الشهري: ${months}.`,
    dir_rising: 'في ارتفاع خلال العام',
    dir_falling: 'في انخفاض خلال العام',
    dir_steady: 'مستقر خلال العام',
    dir_single: 'كلها في شهر واحد حتى الآن',
    cat_title: 'الطلبات حسب الفئة',
    cat_note: 'كيف تتوزع طلباتك على التخصصات.',
    cat_empty: 'لا توجد لديك طلبات بعد، فلا شيء يُصنَّف حسب الفئة.',
    cat_missing: 'لم يُحمَّل توزيع الفئات بعد.',
    cat_alt: (pairs: string) => `الطلبات حسب الفئة: ${pairs}.`,
    gap_title: 'فارق الأسعار حسب الفئة',
    gap_note:
      'الفارق بين أعلى عرض وأدناه في كل طلب تلقّى عرضين أو أكثر، مجموعًا حسب الفئة. هذه هي القيمة التي تحققها لك مقارنة العروض، وليست خصمًا قدّمه أي مورّد.',
    gap_empty_none: 'لا توجد لديك طلبات بعد، لذلك لا توجد عروض للمقارنة.',
    gap_missing: 'ما زالت طلباتك قيد التحميل، لذلك لا يظهر فارق الأسعار بعد.',
    gap_empty_thin:
      'لم يتلقَّ أي من طلباتك عرضين أو أكثر حتى الآن. ويتطلب قياس الفارق عرضين على الأقل للطلب نفسه، لذا لا شيء للعرض.',
    gap_alt: (pairs: string, total: string, n: number) =>
      `الفارق بين أعلى عرض وأدناه حسب الفئة: ${pairs}. الإجمالي ${total} في ${arCount(n, AR_NOUN.request, { oblique: true })} تلقّى عرضين أو أكثر.`,
    gap_total: (v: string, n: number) => `إجمالي الفارق في ${arCount(n, AR_NOUN.request, { oblique: true })}: ${v}`,
    uncategorised: 'غير مصنّف',
    more: (n: number) => `${arCount(n, AR_NOUN.category)} أصغر لا تظهر في الرسم، وجميعها واردة في الملخص أعلاه.`,
    k_requests: 'الطلبات',
    k_spread: 'الفارق',
    recent_note: 'يشمل أحدث 25 طلبًا، وهي ما تعرضه البوابة.',
  },
} as const;

const tr = (lang: Lang) => T[lang] ?? T.en;

const aed = (n: number, lang: Lang): string =>
  'AED ' + n.toLocaleString(lang === 'ar' ? 'ar-AE' : 'en-AE', { maximumFractionDigits: 0 });

/** Bars past this point are dropped from the drawing but stay in the text alternative. */
const MAX_BARS = 8;

/* ── one chart card: title, what-it-measures note, and either the drawing or the truth ─────── */

function Panel({
  title,
  note,
  empty,
  caption,
  captionId,
  footer,
  children,
  className,
}: {
  title: string;
  note: string;
  /** When set, the chart is NOT drawn and this sentence is shown instead. */
  empty?: string;
  /** Text alternative. Visible, and referenced by the chart's aria-labelledby. */
  caption?: string;
  captionId?: string;
  footer?: string;
  children?: React.ReactNode;
  className?: string;
}) {
  return (
    <Card className={cn('p-4', className)}>
      <h3 className="text-[14px] font-bold text-foreground">{title}</h3>
      <p className="mt-1 text-[12px] leading-relaxed text-muted-foreground">{note}</p>
      {empty ? (
        <p className="mt-3 rounded-lg border border-border bg-secondary/30 px-3 py-3 text-[13px] leading-relaxed text-muted-foreground">
          {empty}
        </p>
      ) : (
        <>
          <div className="mt-3">{children}</div>
          {caption ? (
            <p id={captionId} className="mt-2 text-[12px] leading-relaxed text-muted-foreground">
              {caption}
            </p>
          ) : null}
          {footer ? <p className="mt-1 text-[12px] font-semibold text-foreground">{footer}</p> : null}
        </>
      )}
    </Card>
  );
}

/* ── 1. request trend over history_12m ────────────────────────────────────────────────────── */

export function RequestTrendChart({
  history,
  lang = 'en',
  className,
}: {
  history?: HistoryPoint[] | null;
  lang?: Lang;
  className?: string;
}) {
  const t = tr(lang);
  const capId = `${React.useId()}cap`;

  const hasSeries = Array.isArray(history) && history.length > 0;
  const summary = summariseHistory(history);

  // Two different absences. No series means the overview call has not landed; an all-zero series
  // means the customer genuinely has no history, and a flat line would read as a real quiet year.
  if (!summary) {
    return (
      <Panel
        title={t.trend_title}
        note={t.trend_note}
        empty={hasSeries ? t.trend_empty : t.trend_missing}
        className={className}
      />
    );
  }

  const dir =
    summary.direction === 'rising' ? t.dir_rising : summary.direction === 'falling' ? t.dir_falling : summary.direction === 'single' ? t.dir_single : t.dir_steady;
  const months = summary.points.map((p) => `${monthLabel(p.month, lang)} ${p.inquiries}`).join(', ');
  const config = { inquiries: { label: t.k_requests, color: 'hsl(var(--chart-1))' } } satisfies ChartConfig;

  return (
    <Panel
      title={t.trend_title}
      note={t.trend_note}
      caption={t.trend_alt(summary.total, dir, monthLabel(summary.peak.month, lang), summary.peak.inquiries, months)}
      captionId={capId}
      className={className}
    >
      <ChartContainer config={config} className="aspect-auto h-[210px] w-full" role="img" aria-labelledby={capId}>
        <AreaChart data={summary.points} margin={{ left: 4, right: 8, top: 6, bottom: 0 }}>
          <CartesianGrid vertical={false} />
          <XAxis dataKey="month" tickFormatter={(m) => monthLabel(String(m), lang)} tickLine={false} axisLine={false} tickMargin={8} interval="preserveStartEnd" />
          <YAxis width={26} allowDecimals={false} tickLine={false} axisLine={false} />
          <ChartTooltip content={<ChartTooltipContent />} />
          <Area
            dataKey="inquiries"
            type="monotone"
            stroke="var(--color-inquiries)"
            strokeWidth={2}
            fill="var(--color-inquiries)"
            fillOpacity={0.18}
            dot={{ r: 2 }}
          />
        </AreaChart>
      </ChartContainer>
    </Panel>
  );
}

/* ── 2. request mix by category, from stats.inquiries ─────────────────────────────────────── */

export function CategoryMixChart({
  inquiries,
  lang = 'en',
  className,
}: {
  inquiries?: StatsInquiry[] | null;
  lang?: Lang;
  className?: string;
}) {
  const t = tr(lang);
  const capId = `${React.useId()}cap`;

  // Same two absences as the trend: no array means the overview call has not landed (or failed),
  // which is not the same fact as "you have no requests".
  const all = countByCategory(inquiries, t.uncategorised).map((r) => ({ ...r, category: categoryLabel(r.category, lang) }));
  if (!all.length) {
    const empty = Array.isArray(inquiries) ? t.cat_empty : t.cat_missing;
    return <Panel title={t.cat_title} note={t.cat_note} empty={empty} className={className} />;
  }

  const shown = all.slice(0, MAX_BARS);
  const hidden = all.length - shown.length;
  const config = { requests: { label: t.k_requests, color: 'hsl(var(--chart-1))' } } satisfies ChartConfig;

  return (
    <Panel
      title={t.cat_title}
      note={t.cat_note}
      caption={t.cat_alt(all.map((r) => `${r.category} ${r.requests}`).join(', '))}
      captionId={capId}
      footer={hidden > 0 ? t.more(hidden) : undefined}
      className={className}
    >
      <ChartContainer
        config={config}
        className="aspect-auto w-full"
        style={{ height: Math.max(150, shown.length * 34 + 26) }}
        role="img"
        aria-labelledby={capId}
      >
        {/* RTL: mirrored by the axes, not by CSS direction — inherited `direction: rtl` flips every
            SVG text anchor, which clipped the category ticks ("hv", "el") and pushed value labels
            onto their bars. The SVG stays LTR; the category axis moves right, bars grow leftward. */}
        <BarChart data={shown} layout="vertical" style={{ direction: 'ltr' }} margin={lang === 'ar' ? { left: 40, right: 4, top: 4, bottom: 4 } : { left: 4, right: 40, top: 4, bottom: 4 }}>
          <XAxis type="number" dataKey="requests" hide allowDecimals={false} reversed={lang === 'ar'} />
          <YAxis type="category" dataKey="category" width={140} tickLine={false} axisLine={false} tickMargin={6} orientation={lang === 'ar' ? 'right' : 'left'} />
          <ChartTooltip content={<ChartTooltipContent />} />
          <Bar dataKey="requests" fill="var(--color-requests)" radius={4} barSize={18}>
            <LabelList dataKey="requests" position={lang === 'ar' ? 'left' : 'right'} className="fill-foreground" fontSize={12} />
          </Bar>
        </BarChart>
      </ChartContainer>
    </Panel>
  );
}

/* ── 3. quote spread by category, from my_inquiries quote prices ──────────────────────────── */

export function QuoteSpreadChart({
  inquiries,
  lang = 'en',
  className,
}: {
  inquiries?: PortalInquiry[] | null;
  lang?: Lang;
  className?: string;
}) {
  const t = tr(lang);
  const capId = `${React.useId()}cap`;

  const hasRequests = Array.isArray(inquiries) && inquiries.length > 0;
  const { rows, total, counted } = spreadByCategory(inquiries, t.uncategorised);
  const all = rows.map((r) => ({ ...r, category: categoryLabel(r.category, lang) }));

  // "You have requests but none of them has two quotes" is a different fact from "you have no
  // requests", and the customer needs to be told which one is true.
  if (!counted) {
    return (
      <Panel
        title={t.gap_title}
        note={t.gap_note}
        empty={hasRequests ? t.gap_empty_thin : Array.isArray(inquiries) ? t.gap_empty_none : t.gap_missing}
        className={className}
      />
    );
  }

  const shown = all.slice(0, MAX_BARS);
  const hidden = all.length - shown.length;
  const totalLine = t.gap_total(aed(total, lang), counted);
  const config = { spread: { label: t.k_spread, color: 'hsl(var(--chart-2))' } } satisfies ChartConfig;

  return (
    <Panel
      title={t.gap_title}
      note={`${t.gap_note} ${t.recent_note}`}
      caption={t.gap_alt(all.map((r) => `${r.category} ${aed(r.spread, lang)}`).join(', '), aed(total, lang), counted)}
      captionId={capId}
      footer={hidden > 0 ? `${totalLine} — ${t.more(hidden)}` : totalLine}
      className={className}
    >
      <ChartContainer
        config={config}
        className="aspect-auto w-full"
        style={{ height: Math.max(150, shown.length * 34 + 26) }}
        role="img"
        aria-labelledby={capId}
      >
        {/* RTL mirrored by the axes with the SVG kept LTR — see CategoryMixChart. */}
        <BarChart data={shown} layout="vertical" style={{ direction: 'ltr' }} margin={lang === 'ar' ? { left: 96, right: 4, top: 4, bottom: 4 } : { left: 4, right: 96, top: 4, bottom: 4 }}>
          <XAxis type="number" dataKey="spread" hide reversed={lang === 'ar'} />
          <YAxis type="category" dataKey="category" width={140} tickLine={false} axisLine={false} tickMargin={6} orientation={lang === 'ar' ? 'right' : 'left'} />
          <ChartTooltip content={<ChartTooltipContent formatter={(v) => aed(num(v), lang)} />} />
          <Bar dataKey="spread" fill="var(--color-spread)" radius={4} barSize={18}>
            <LabelList
              dataKey="spread"
              position={lang === 'ar' ? 'left' : 'right'}
              className="fill-foreground"
              fontSize={12}
              formatter={(v: number) => aed(num(v), lang)}
            />
          </Bar>
        </BarChart>
      </ChartContainer>
    </Panel>
  );
}

/* ── the section the integrator mounts ────────────────────────────────────────────────────── */

export function SpendingIntelligence({
  stats,
  inquiries,
  lang = 'en',
  className,
}: {
  /** `overview.stats` from customer_portal action=overview (the fn_customer_stats payload). */
  stats?: CustomerStats | null;
  /** `inquiries` from customer_api action=my_inquiries — needed for the quote-spread chart only. */
  inquiries?: PortalInquiry[] | null;
  lang?: Lang;
  className?: string;
}) {
  const t = tr(lang);
  return (
    <section className={cn('mt-[18px]', className)} aria-labelledby="qd-spending-intelligence">
      <h2 id="qd-spending-intelligence" className="text-[15px] font-bold text-foreground">
        {t.section}
      </h2>
      <p className="mb-2 mt-0.5 text-[12px] leading-relaxed text-muted-foreground">{t.section_sub}</p>
      <div className="grid gap-2.5 md:grid-cols-2">
        <RequestTrendChart history={stats?.history_12m} lang={lang} className="md:col-span-2" />
        <CategoryMixChart inquiries={stats?.inquiries} lang={lang} />
        <QuoteSpreadChart inquiries={inquiries} lang={lang} />
      </div>
    </section>
  );
}

export default SpendingIntelligence;
