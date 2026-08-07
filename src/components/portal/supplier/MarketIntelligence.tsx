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
import React, { useEffect, useState } from 'react';

type Blocked = { available?: false; value?: null; basis?: string; population?: number; note?: string };
type Market = {
  sector?: string | null;
  competitors?: { available?: boolean; basis?: string; total?: number; in_my_area?: number;
                  matchable?: number; by_emirate?: { emirate: string; count: number }[] };
  market_composition?: { available?: boolean; basis?: string; segments?: { name: string; count: number }[] };
  demand_trend?: Blocked; most_requested?: Blocked; avg_market_price?: Blocked;
};
type Lang = 'en' | 'ar';

const FN = (process.env.NEXT_PUBLIC_SUPABASE_URL || '') + '/functions/v1';
const ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

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
    matchableNote: 'None of them is verified, so none can currently be matched to work — including you.',
  },
  ar: {
    title: 'ذكاء السوق', competitors: 'المنافسون', inArea: 'في نطاق خدمتك',
    matchable: 'قادر على تلقي طلب', composition: 'أين يقع منافسوك',
    demandTrend: 'اتجاه الطلب', mostRequested: 'الأكثر طلبًا', avgPrice: 'متوسط سعر السوق',
    notAvailable: 'غير متاح بعد', loading: 'جارٍ قراءة السوق…',
    sector: 'القطاع', companies: 'شركة', none: 'لا يوجد',
    matchableNote: 'لا أحد منهم موثّق، لذا لا يمكن مطابقة أي منهم بالعمل — بما فيهم أنت.',
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

  return (
    <div className="space-y-4">
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
          <p className="text-[10px] opacity-45 mt-2 leading-snug">{t(lang, 'matchableNote')}</p>
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

      {/* The half the platform cannot answer yet. Shown with its reason, never filled in. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4 space-y-2">
        <Unavailable label={t(lang, 'demandTrend')} b={m.demand_trend} lang={lang} />
        <Unavailable label={t(lang, 'mostRequested')} b={m.most_requested} lang={lang} />
        <Unavailable label={t(lang, 'avgPrice')} b={m.avg_market_price} lang={lang} />
      </section>
    </div>
  );
}
