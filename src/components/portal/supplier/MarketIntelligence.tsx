'use client';
// ROW #5 §14 §22 — MARKET INTELLIGENCE, with an honest ceiling.
//
// ── HALF OF §14 IS ABOUT SUPPLY AND HALF IS ABOUT DEMAND ────────────────────────────────────────
// The estate has one of those halves. 20,464 leads carry a sector and an emirate, so a supplier can
// truthfully be told how many companies compete with them and where. There are 0 inquiries and 0
// quotes, so demand trend, most-requested and average market price cannot be computed at all.
//
// The blocked figures render as an explicit "not available yet" WITH the empty population named.
// They are not hidden, because a supplier should know the platform cannot answer that yet, and they
// are not filled in, because "HVAC demand ↑ 18%" against zero inquiries is indistinguishable from
// real market intelligence on screen — and a supplier could staff up on the strength of it.
//
// The competitor half is not a consolation prize. "4,276 companies compete with you in Abu Dhabi,
// and 0 of them can currently receive an RFQ" is genuinely useful and completely true.
//
// ── AND IT STOPPED BEING TRUE THE MOMENT A SUPPLIER FINISHED (13 Aug 2026) ──────────────────────
// "0 of them" is a count of PEERS: fn_supplier_market's peers CTE opens with `l.id <> me.id`. The
// note beneath it said "...so none can currently be matched to work — including you", a constant,
// and that last clause is a claim about the reader which the number cannot support. Rendered on
// production to MERIDIAN MEP: verified, approved, scope confirmed, and the one company in the whole
// estate that fn_match_capability actually returns. The panel told it that it could not be matched.
// `matchable` now counts on both legs of the real gate and `me_matchable` is computed about the
// reader, so a supplier who has done the work is told they are ahead instead of being told a lie.
import React, { useEffect, useState } from 'react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Blocked = { available?: boolean; value?: unknown; basis?: string; population?: number; note?: string };
type Trend = Blocked & {
  category?: string | null; value?: number | null; prior?: number | null;
  direction?: 'up' | 'down' | 'flat' | null; pct?: number | null; from_zero?: boolean;
  share_pct?: number | null; series?: { week: string; count: number }[];
};
type TopCat = Blocked & { value?: string | null; count?: number | null };
type Price = Blocked & {
  value?: number | null; median?: number | null; p25?: number | null; p75?: number | null;
  low?: number | null; high?: number | null; currency?: string;
};
type Market = {
  sector?: string | null;
  population?: 'demo' | 'live';
  competitors?: { available?: boolean; basis?: string; total?: number; in_my_area?: number;
                  matchable?: number; me_matchable?: boolean;
                  by_emirate?: { emirate: string; count: number }[] };
  market_composition?: { available?: boolean; basis?: string; segments?: { name: string; count: number }[] };
  demand_trend?: Trend; most_requested?: TopCat; avg_market_price?: Price;
};
type Lang = 'en' | 'ar';

const FN = SUPA_FN;
const ANON = SUPA_ANON;

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'Market Intelligence', competitors: 'Competitors', inArea: 'in your service area',
    matchable: 'able to receive an RFQ', composition: 'Where your competition sits',
    demandTrend: 'Demand trend', mostRequested: 'Most requested', avgPrice: 'Average market price',
    notAvailable: 'not available yet', loading: 'Reading the market…',
    sector: 'sector', companies: 'companies', none: 'none',
    // Two notes, because "including you" is a claim about the reader and `matchable` counts only
    // their competitors — fn_supplier_market's `peers` CTE opens with `l.id <> me.id`. On 13 Aug
    // 2026 the single constant note told MERIDIAN MEP, the one supplier in the estate an RFQ could
    // reach, that it could not be matched to work. me_matchable is now computed about the reader.
    matchableNoteBlocked: 'None of them can currently be matched to work — and nor can you. Confirm what your company can quote for, on the My scope tab, and you are the first.',
    matchableNoteAhead: 'You can. None of them can — a request in your trade reaches you and not them.',
    thisPeriod: 'enquiries in the last 14 days', priorPeriod: 'in the 14 before',
    shareOf: 'of all enquiries', newDemand: 'new', perWeek: 'Enquiries per week',
    median: 'median', quartiles: 'middle half', range: 'range', from: 'from',
    demoBanner: 'Demonstration data. These figures are computed from QuotesDone demo fixtures, not from live trading.',
  },
  ar: {
    title: 'ذكاء السوق', competitors: 'المنافسون', inArea: 'في نطاق خدمتك',
    matchable: 'قادر على تلقي طلب', composition: 'أين يقع منافسوك',
    demandTrend: 'اتجاه الطلب', mostRequested: 'الأكثر طلبًا', avgPrice: 'متوسط سعر السوق',
    notAvailable: 'غير متاح بعد', loading: 'جارٍ قراءة السوق…',
    sector: 'القطاع', companies: 'شركة', none: 'لا يوجد',
    matchableNoteBlocked: 'لا يمكن مطابقة أي منهم بالعمل — ولا أنت. أكّد ما يمكن لشركتك تسعيره من تبويب «نطاق عملي» وتكون الأول.',
    matchableNoteAhead: 'أنت تستطيع. لا أحد منهم يستطيع — الطلب في تخصصك يصلك أنت دونهم.',
    thisPeriod: 'طلب خلال ١٤ يومًا الماضية', priorPeriod: 'في الـ١٤ يومًا قبلها',
    shareOf: 'من إجمالي الطلبات', newDemand: 'جديد', perWeek: 'الطلبات أسبوعيًا',
    median: 'الوسيط', quartiles: 'النصف الأوسط', range: 'المدى', from: 'من',
    demoBanner: 'بيانات تجريبية. هذه الأرقام محسوبة من بيانات عرض توضيحي، وليست من تداول حقيقي.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// §22's animated chart. A horizontal bar per segment, widths driven by real counts.
function Bars({ rows, lang }: { rows: { name: string; count: number }[]; lang: Lang }) {
  if (!rows.length) return <p className="text-[11px] opacity-50">{t(lang, 'none')}</p>;
  const max = Math.max(...rows.map((r) => r.count), 1);
  return (
    <div className="space-y-1.5">
      {rows.map((r) => (
        <div key={r.name}>
          <div className="flex justify-between text-[11px] mb-0.5">
            <span className="opacity-70 truncate pe-2">{r.name}</span>
            <span className="tabular-nums opacity-60">{r.count.toLocaleString()}</span>
          </div>
          <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
            <div
              className="h-full rounded-full bg-gradient-to-r from-indigo-400 to-sky-400 transition-all duration-700"
              style={{ width: Math.max(2, (r.count / max) * 100) + '%' }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}

// Money the supplier is meant to compare against their own. No decimals — a market price quoted to
// the fils is a precision the population cannot support.
const aed = (n?: number | null, cur = 'AED') =>
  n === null || n === undefined ? '—' : cur + ' ' + Math.round(n).toLocaleString('en-US');

// A card that shows a computed figure. The three demand figures share it so that "available" is
// decided in exactly one place on the surface, the same way the routine decides it in one place.
function Figure({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.02] px-3 py-2.5">
      <div className="text-[11px] opacity-60 mb-1">{label}</div>
      {children}
    </div>
  );
}

// A figure the platform cannot compute yet. Shown, not hidden — and never filled in.
function Unavailable({ label, b, lang }: { label: string; b?: Blocked; lang: Lang }) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.02] px-3 py-2.5">
      <div className="flex justify-between items-baseline gap-2">
        <span className="text-[11px] opacity-60">{label}</span>
        <span className="text-[11px] opacity-40">{t(lang, 'notAvailable')}</span>
      </div>
      {b?.note && <p className="text-[10px] opacity-40 mt-1 leading-snug">{b.note}</p>}
    </div>
  );
}

export default function MarketIntelligence({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [m, setM] = useState<Market | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'market' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setM(j);
      else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!m) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const c = m.competitors || {};
  const byEm = (c.by_emirate || []).map((x) => ({ name: x.emirate, count: x.count }));
  const segs = m.market_composition?.segments || [];

  // The direction the routine computed, as the one glyph a supplier reads before any number.
  // 'flat' gets its own mark rather than defaulting to a down arrow — no change is not a decline.
  const trend = m.demand_trend;
  const arrow = trend?.direction === 'up' ? '↑' : trend?.direction === 'down' ? '↓' : '→';
  const dirTone = trend?.direction === 'up' ? 'text-emerald-300'
    : trend?.direction === 'down' ? 'text-rose-300' : 'text-white/60';

  return (
    <div className="space-y-4">
      {/* A demo fixture must never be able to read its own figures as live trading. The routine
          says which population it computed over; the surface says so out loud. */}
      {m.population === 'demo' && (
        <p className="rounded-xl border border-amber-300/25 bg-amber-300/[0.06] px-3 py-2 text-[11px] leading-snug text-amber-200/80">
          {t(lang, 'demoBanner')}
        </p>
      )}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-3">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
          {m.sector && <span className="text-[10px] opacity-40">{t(lang, 'sector')}: {m.sector}</span>}
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div>
            <div className="text-2xl font-semibold tabular-nums">{(c.total ?? 0).toLocaleString()}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'competitors')}</div>
          </div>
          <div>
            <div className="text-2xl font-semibold tabular-nums">{(c.in_my_area ?? 0).toLocaleString()}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'inArea')}</div>
          </div>
          <div>
            <div className="text-2xl font-semibold tabular-nums text-amber-300">{(c.matchable ?? 0).toLocaleString()}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'matchable')}</div>
          </div>
        </div>
        {(c.matchable ?? 0) === 0 && (c.total ?? 0) > 0 && (
          <p className={'text-[10px] mt-2 leading-snug ' + (c.me_matchable ? 'text-emerald-400/80' : 'opacity-45')}>
            {t(lang, c.me_matchable ? 'matchableNoteAhead' : 'matchableNoteBlocked')}</p>
        )}
      </section>

      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'composition')}</h3>
        <Bars rows={byEm} lang={lang} />
        {segs.length > 0 && (
          <div className="mt-4 pt-3 border-t border-white/10">
            <Bars rows={segs} lang={lang} />
          </div>
        )}
      </section>

      {/* ── THE DEMAND HALF ────────────────────────────────────────────────────────────────────
          Each figure renders its real value when the routine computed one, and its reason when the
          routine refused. The decision is the routine's `available` flag in every case: the surface
          never decides for itself that a number is good enough to show. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4 space-y-2">
        {trend?.available ? (
          <Figure label={t(lang, 'demandTrend') + (trend.category ? ' · ' + trend.category : '')}>
            <div className="flex items-baseline gap-2">
              <span className={'text-xl leading-none ' + dirTone}>{arrow}</span>
              <span className="text-2xl font-semibold tabular-nums">{trend.value ?? 0}</span>
              <span className="text-[11px] opacity-50">{t(lang, 'thisPeriod')}</span>
            </div>
            <div className="text-[11px] opacity-55 mt-1">
              {/* A percentage is printed only when the routine produced one. From a base of zero
                  there is no honest percentage, so the word "new" stands in its place. */}
              {trend.pct !== null && trend.pct !== undefined
                ? <span className={dirTone}>{(trend.pct > 0 ? '+' : '') + trend.pct + '%'}</span>
                : <span className="opacity-70">{t(lang, 'newDemand')}</span>}
              <span className="opacity-50">
                {' · ' + (trend.prior ?? 0) + ' ' + t(lang, 'priorPeriod')}
                {trend.share_pct !== null && trend.share_pct !== undefined
                  ? ' · ' + trend.share_pct + '% ' + t(lang, 'shareOf') : ''}
              </span>
            </div>
            {!!(trend.series || []).length && (
              <div className="mt-2.5 pt-2 border-t border-white/10">
                <div className="text-[10px] uppercase tracking-wide opacity-40 mb-1.5">{t(lang, 'perWeek')}</div>
                <Bars rows={(trend.series || []).map((w) => ({ name: w.week, count: w.count }))} lang={lang} />
              </div>
            )}
            {trend.note && <p className="text-[10px] opacity-40 mt-1.5 leading-snug">{trend.note}</p>}
          </Figure>
        ) : <Unavailable label={t(lang, 'demandTrend')} b={m.demand_trend} lang={lang} />}

        {m.most_requested?.available ? (
          <Figure label={t(lang, 'mostRequested')}>
            <div className="flex items-baseline gap-2">
              <span className="text-lg font-semibold capitalize">{m.most_requested.value}</span>
              <span className="text-[11px] opacity-50">{m.most_requested.count} {t(lang, 'companies') === 'companies' ? 'enquiries' : 'طلب'}</span>
            </div>
            <p className="text-[10px] opacity-40 mt-1">{m.most_requested.basis}</p>
          </Figure>
        ) : <Unavailable label={t(lang, 'mostRequested')} b={m.most_requested} lang={lang} />}

        {m.avg_market_price?.available ? (
          <Figure label={t(lang, 'avgPrice')}>
            <div className="text-2xl font-semibold tabular-nums">
              {aed(m.avg_market_price.value, m.avg_market_price.currency)}
            </div>
            {/* The mean alone tells a supplier nothing about where they sit. The median and the
                middle half are what "you are high" is actually measured against, so they are shown
                beside it rather than left in the payload. */}
            <div className="text-[11px] opacity-55 mt-1 leading-relaxed">
              <div>{t(lang, 'median')}: <span className="tabular-nums">{aed(m.avg_market_price.median, m.avg_market_price.currency)}</span></div>
              <div>{t(lang, 'quartiles')}: <span className="tabular-nums">{aed(m.avg_market_price.p25, m.avg_market_price.currency)} – {aed(m.avg_market_price.p75, m.avg_market_price.currency)}</span></div>
              <div className="opacity-70">{t(lang, 'range')}: <span className="tabular-nums">{aed(m.avg_market_price.low, m.avg_market_price.currency)} – {aed(m.avg_market_price.high, m.avg_market_price.currency)}</span></div>
            </div>
            <p className="text-[10px] opacity-40 mt-1.5 leading-snug">{m.avg_market_price.basis} · {m.avg_market_price.population} quotes</p>
          </Figure>
        ) : <Unavailable label={t(lang, 'avgPrice')} b={m.avg_market_price} lang={lang} />}
      </section>
    </div>
  );
}
