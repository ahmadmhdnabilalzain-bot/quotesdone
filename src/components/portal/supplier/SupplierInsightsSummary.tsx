'use client';
// INSIGHTS, DRAWN (15 Sep 2026, sales_engineer).
//
// Founder's spec: the supplier's pricing against the market, hints to improve, and headline totals —
// inquiries received, quotations submitted, jobs won, revenue — as a visual experience, not text. Every
// number, band, conversion and hint arrives decided from supplier_portal `insights_summary`
// (supabase/functions/supplier_portal/insights_summary.ts); this file only draws it:
//   - four headline tiles;
//   - the price position as a gauge over the three bands fn_supplier_stats uses (edges from the payload);
//   - the funnel, each count and its conversion in separate elements — the old overview wrote "0 0%" as one
//     run of text, which Arabic's bidi merged into "00%";
//   - the 12-month trend (recharts, already a dependency), with a screen-reader table of the same numbers;
//   - hint cards, each opening the tab where it is fixed.
// A new supplier sees the same shapes at zero with one honest note — no sample data, ever.
import { useEffect, useRef, useState } from 'react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { AlertTriangle, ArrowUpRight, CheckCircle2, Lightbulb } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { call } from './api';
// One money format for the portal: /ar reads "1,200 د.إ", /en "AED 1,200".
import { aed } from './money';

// avg_lead_time_days is the mean of the lead_time this supplier WROTE on its own quotations
// (fn_supplier_stats: avg of the digits in quotes.lead_time) — not a measured delivery time.
// "Average lead time" alone read as a performance figure (audit 21 Sep 2026, finding 38), so the
// label says what was averaged. Hidden when null, i.e. when no quote carried a lead time.
const LEAD_LABEL = { en: 'Average lead time you quoted', ar: 'متوسط مدة التوريد في عروضكم' } as const;
import { ws } from './workspaceCopy';
import { arDays } from '@/lib/durationLabel';

type Lang = 'en' | 'ar' | string;
type Summary = {
  ok: boolean; has_data: boolean;
  totals: { inquiries_received: number; quotations_submitted: number; jobs_won: number; revenue_aed: number };
  rates: { win_pct: number | null; reveal_pct: number | null; response_pct: number | null; avg_lead_time_days: number | null; lost_to_others: number };
  price_position: { band: 'below' | 'around' | 'above' | 'no_data'; pct_vs_market_avg: number | null; lowest_rate_pct: number | null; competitive_rfqs: number; times_lowest: number; gauge: number | null; band_edges: { below_max: number; above_min: number } };
  funnel: { key: string; count: number; conversion_pct: number | null }[];
  series: { month: string; quotes: number; reveals: number }[];
  hints: { code: string; severity: 'high' | 'medium' | 'low'; params: Record<string, string | number>; action: string | null }[];
};

const nf = (n: number) => Number(n || 0).toLocaleString('en-AE', { maximumFractionDigits: 0 });
const monthLabel = (m: string, lang: Lang) => { const d = new Date(m + '-01T00:00:00Z'); return isNaN(d.getTime()) ? m : d.toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { month: 'short', timeZone: 'UTC' }); };
const signed = (v: number) => (v > 0 ? '+' : v < 0 ? '−' : '') + Math.abs(Math.round(v)) + '%';

function Tile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="qd-panel qd-ticks p-4 pt-5">
      <div className="text-[12px] font-semibold text-muted-foreground">{label}</div>
      <div className="mt-2 font-head text-[26px] font-semibold leading-none text-foreground tabular-nums"><bdi dir="ltr">{value}</bdi></div>
      {sub ? <div className="mt-1.5 text-[11.5px] text-muted-foreground">{sub}</div> : null}
    </div>
  );
}

// Semicircle: left = cheaper than the market, right = dearer. Bands are drawn from the payload's edges on
// the same -20%..+20% scale the server's gauge value uses.
function Gauge({ pp, lang }: { pp: Summary['price_position']; lang: Lang }) {
  const R = 80, cx = 100, cy = 96;
  const at = (g: number) => { const a = Math.PI * (1 - (g + 1) / 2); return [cx + R * Math.cos(a), cy - R * Math.sin(a)]; };
  const arc = (g0: number, g1: number) => { const [x0, y0] = at(g0), [x1, y1] = at(g1); return `M ${x0} ${y0} A ${R} ${R} 0 0 1 ${x1} ${y1}`; };
  const e0 = pp.band_edges.below_max / 20, e1 = pp.band_edges.above_min / 20;
  const none = pp.gauge == null;
  const [nx, ny] = at(pp.gauge ?? 0);
  const label = ws(lang, 'band_' + pp.band);
  return (
    <svg viewBox="0 0 200 118" className="mx-auto w-full max-w-[280px]" role="img" aria-label={`${ws(lang, 'in_price_h')}: ${label}${pp.pct_vs_market_avg != null ? ' (' + signed(pp.pct_vs_market_avg) + ')' : ''}`}>
      <g fill="none" strokeWidth="14" strokeLinecap="butt" opacity={none ? 0.35 : 1}>
        <path d={arc(-1, e0 - 0.01)} stroke="currentColor" className="text-ok-fg" />
        <path d={arc(e0 + 0.01, e1 - 0.01)} stroke="currentColor" className="text-muted-foreground/50" />
        <path d={arc(e1 + 0.01, 1)} stroke="currentColor" className="text-warn-fg" />
      </g>
      {!none && <>
        <line x1={cx} y1={cy} x2={nx} y2={ny} strokeWidth="3" strokeLinecap="round" className="stroke-foreground" />
        <circle cx={cx} cy={cy} r="6" className="fill-foreground" />
      </>}
      <text x={cx - R} y={cy + 18} textAnchor="middle" className="fill-muted-foreground text-[9px]">{ws(lang, 'gauge_below')}</text>
      <text x={cx + R} y={cy + 18} textAnchor="middle" className="fill-muted-foreground text-[9px]">{ws(lang, 'gauge_above')}</text>
      <text x={cx} y={cy - R - 4} textAnchor="middle" className="fill-muted-foreground text-[9px]">{ws(lang, 'gauge_market')}</text>
    </svg>
  );
}

function Funnel({ f, lang }: { f: Summary['funnel']; lang: Lang }) {
  const max = Math.max(1, ...f.map((x) => x.count));
  return (
    <ol className="flex flex-col gap-3">
      {f.map((st, i) => (
        <li key={st.key}>
          <div className="flex items-baseline justify-between gap-3">
            <span className="text-[13px] text-foreground">{ws(lang, 'st_' + st.key)}</span>
            <span className="flex items-baseline gap-2">
              <b className="text-[14px] text-foreground tabular-nums"><bdi dir="ltr">{nf(st.count)}</bdi></b>
              {st.conversion_pct != null && <span className="rounded-full border border-border px-2 py-0.5 text-[11px] text-muted-foreground"><bdi dir="ltr" aria-hidden>{st.conversion_pct}%</bdi><span className="sr-only">{ws(lang, 'conv_of_prev', { pct: st.conversion_pct + '%' })}</span></span>}
            </span>
          </div>
          <div className="mt-1.5 h-2.5 overflow-hidden rounded-full bg-secondary/60" aria-hidden>
            <div className="h-full rounded-full bg-primary transition-[width] duration-700 motion-reduce:transition-none" style={{ width: Math.max(st.count ? 3 : 0, Math.round((100 * st.count) / max)) + '%', opacity: 1 - i * 0.17 }} />
          </div>
        </li>
      ))}
    </ol>
  );
}

const TAB_OF: Record<string, string> = { rfqs: 'rfqs', quotes: 'quotes', messages: 'messages', documents: 'documents', services: 'services', profile: 'profile' };

export default function SupplierInsightsSummary({ token, lang, goTo }: { token: string; lang: Lang; goTo?: (t: string) => void }) {
  const ar = lang === 'ar';
  const [s, setS] = useState<Summary | null>(null);
  const [err, setErr] = useState(false);
  // A tab switch unmounts this; an answer arriving afterwards must not write state.
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const load = () => { setErr(false); call('supplier_portal', { action: 'insights_summary' }, token).then((j) => { if (live.current) (j && j.ok ? setS(j) : setErr(true)); }).catch(() => { if (live.current) setErr(true); }); };
  useEffect(() => { load(); }, [token]);
  if (err) return <section className="qd-panel p-5" role="alert"><p className="text-[13px] text-muted-foreground">{ws(lang, 'in_err')}</p><Button size="sm" className="mt-3" onClick={load}>{ws(lang, 'mb_retry')}</Button></section>;
  if (!s) return <section className="qd-panel h-48 animate-pulse motion-reduce:animate-none" aria-busy="true" aria-label={ws(lang, 'in_loading')} />;
  const t = s.totals, pp = s.price_position, r = s.rates;
  const series = s.series.map((p) => ({ ...p, label: monthLabel(p.month, lang) }));
  const anySeries = series.some((p) => p.quotes + p.reveals > 0);
  const rates: [string, string | null][] = [
    ['r_win', r.win_pct != null ? r.win_pct + '%' : null], ['r_reveal', r.reveal_pct != null ? r.reveal_pct + '%' : null],
    ['r_response', r.response_pct != null ? r.response_pct + '%' : null], ['r_lead', r.avg_lead_time_days != null ? (lang === 'ar' ? arDays(r.avg_lead_time_days) : ws(lang, 'days', { n: r.avg_lead_time_days })) : null],
    ['r_lost', r.lost_to_others ? String(r.lost_to_others) : null],
  ];
  return (
    <section aria-labelledby="qd-ins-h" className="mb-6 flex flex-col gap-4">
      <div>
        <h2 id="qd-ins-h" className="font-head text-h3 tracking-snug text-foreground">{ws(lang, 'in_title')}</h2>
        <p className="mt-1 max-w-[70ch] text-[13px] leading-[1.65] text-muted-foreground">{ws(lang, 'in_sub')}</p>
      </div>
      <div className="grid grid-cols-2 gap-2.5 md:grid-cols-4">
        <Tile label={ws(lang, 'tot_received')} value={nf(t.inquiries_received)} />
        <Tile label={ws(lang, 'tot_quoted')} value={nf(t.quotations_submitted)} />
        <Tile label={ws(lang, 'tot_won')} value={nf(t.jobs_won)} />
        <Tile label={ws(lang, 'tot_revenue')} value={aed(lang, t.revenue_aed)} />
      </div>
      {!s.has_data && <p className="rounded-md border border-dashed border-border px-3.5 py-2.5 text-[12.5px] text-muted-foreground">{ws(lang, 'in_empty_note')}</p>}

      <div className="grid grid-cols-1 gap-3.5 md:grid-cols-2">
        <div className="qd-panel p-5">
          <h3 className="text-[14.5px] font-bold text-foreground">{ws(lang, 'in_price_h')}</h3>
          <div className="mt-3" dir="ltr"><Gauge pp={pp} lang={lang} /></div>
          <p className={cn('mt-1 text-center text-[14px] font-semibold', pp.band === 'below' ? 'text-ok-fg' : pp.band === 'above' ? 'text-warn-fg' : 'text-foreground')}>{ws(lang, 'band_' + pp.band)}</p>
          <p className="mt-2 text-center text-[12.5px] leading-[1.65] text-muted-foreground">{pp.band === 'no_data' ? ws(lang, 'price_no_data')
            : ws(lang, 'price_detail', { pct: signed(pp.pct_vs_market_avg ?? 0), n: pp.competitive_rfqs, lowest: pp.times_lowest })}</p>
        </div>
        <div className="qd-panel p-5">
          <h3 className="mb-3 text-[14.5px] font-bold text-foreground">{ws(lang, 'in_funnel_h')}</h3>
          <Funnel f={s.funnel} lang={lang} />
          {rates.some(([, v]) => v != null) && (
            <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 border-t border-border pt-3.5">
              {rates.filter(([, v]) => v != null).map(([k, v]) => (
                <div key={k} className="flex items-baseline justify-between gap-2"><dt className="text-[12.5px] text-muted-foreground">{k === 'r_lead' ? LEAD_LABEL[lang === 'ar' ? 'ar' : 'en'] : ws(lang, k)}</dt><dd className="text-[13px] font-bold text-foreground tabular-nums"><bdi dir="ltr">{v}</bdi></dd></div>
              ))}
            </dl>
          )}
        </div>
      </div>

      <div className="qd-panel p-5">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h3 className="text-[14.5px] font-bold text-foreground">{ws(lang, 'in_trend_h')}</h3>
          <div className="flex items-center gap-4 text-[12px] text-muted-foreground" aria-hidden>
            <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm bg-primary" />{ws(lang, 'trend_quotes')}</span>
            <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm bg-primary/40" />{ws(lang, 'trend_reveals')}</span>
          </div>
        </div>
        <div className="mt-3 h-[200px] w-full" dir="ltr" aria-hidden>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={series} barGap={2} margin={{ top: 6, right: 6, bottom: 0, left: -18 }}>
              <CartesianGrid vertical={false} stroke="currentColor" className="text-border" strokeOpacity={0.5} />
              <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: 'currentColor' }} className="text-muted-foreground" reversed={ar} />
              <YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: 'currentColor' }} className="text-muted-foreground" orientation={ar ? 'right' : 'left'} domain={[0, (m: number) => Math.max(1, m)]} />
              <Tooltip cursor={{ fillOpacity: 0.06 }} contentStyle={{ background: 'var(--card, #111)', border: '1px solid var(--line, #333)', borderRadius: 8, fontSize: 12 }}
                formatter={(v: number, name: string) => [v, name === 'quotes' ? ws(lang, 'trend_quotes') : ws(lang, 'trend_reveals')]} />
              <Bar dataKey="quotes" radius={[4, 4, 0, 0]} fill="currentColor" className="text-primary" maxBarSize={14} />
              <Bar dataKey="reveals" radius={[4, 4, 0, 0]} fill="currentColor" className="text-primary/40" maxBarSize={14} />
            </BarChart>
          </ResponsiveContainer>
        </div>
        {!anySeries && <p className="mt-2 text-[12.5px] text-muted-foreground">{ws(lang, 'trend_empty')}</p>}
        <table className="sr-only">
          <caption>{ws(lang, 'in_trend_h')}</caption>
          <thead><tr><th scope="col">{ar ? 'الشهر' : 'Month'}</th><th scope="col">{ws(lang, 'trend_quotes')}</th><th scope="col">{ws(lang, 'trend_reveals')}</th></tr></thead>
          <tbody>{series.map((p) => <tr key={p.month}><th scope="row">{p.label}</th><td>{p.quotes}</td><td>{p.reveals}</td></tr>)}</tbody>
        </table>
      </div>

      <div>
        <h3 className="mb-2.5 text-[14.5px] font-bold text-foreground">{ws(lang, 'in_hints_h')}</h3>
        <ul className="grid grid-cols-1 gap-2.5 md:grid-cols-2">
          {s.hints.map((h) => {
            const Icon = h.code === 'hint_all_good' ? CheckCircle2 : h.severity === 'high' ? AlertTriangle : Lightbulb;
            const tab = h.action ? TAB_OF[h.action] : null;
            return (
              <li key={h.code + JSON.stringify(h.params)} className={cn('qd-panel flex items-start gap-3 border-s-[3px] p-4', h.severity === 'high' ? 'border-s-danger' : h.severity === 'medium' ? 'border-s-warn' : 'border-s-primary')}>
                <Icon aria-hidden className={cn('mt-0.5 h-4 w-4 shrink-0', h.severity === 'high' ? 'text-danger-fg' : h.severity === 'medium' ? 'text-warn-fg' : 'text-primary')} />
                <div className="min-w-0 flex-1">
                  <div className="text-[13.5px] font-semibold text-foreground">{ws(lang, h.code + '_t', h.params)}</div>
                  <p className="mt-0.5 text-[12.5px] leading-[1.6] text-muted-foreground">{ws(lang, h.code + '_b', h.params)}</p>
                  {tab && goTo && <button type="button" onClick={() => goTo(tab)} className="mt-1.5 inline-flex min-h-11 items-center gap-1 rounded-sm text-[12.5px] font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                    {ws(lang, 'hint_go')}: {ws(lang, tab === 'profile' ? 'acct_profile' : 'tab_' + tab)}<ArrowUpRight aria-hidden className={cn('h-3.5 w-3.5', ar && '-scale-x-100')} />
                  </button>}
                </div>
              </li>
            );
          })}
        </ul>
      </div>
    </section>
  );
}
