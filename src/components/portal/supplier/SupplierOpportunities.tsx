'use client';
// ROW #5 §10 — RECOMMENDED FOR YOU. A ranked list with its reasoning shown.
//
// The spec rejects the chronological inbox: the supplier should meet the work that FITS THEM first
// and be told why it fits. The RFQ tab is a date-ordered list; this is the other thing.
//
// ── THE "WHY" IS THE FEATURE, NOT A TOOLTIP ─────────────────────────────────────────────────────
// Every opportunity shows all four reasons — trade, nearby location, your capacity fits, previous
// similar project — whether or not each applied. A ranking that only shows its positives is a sales
// pitch; showing the misses is what lets a supplier disagree with the score, and disagreeing with
// it is how they learn what to fix in their profile.
//
// ── AND AN UNANSWERABLE REASON IS NOT A FAILED ONE ──────────────────────────────────────────────
// `available:false` renders differently from `applies:false`. With 0 completed jobs on production,
// "previous similar project" cannot be true for anybody, so it reads "no completed work has been
// recorded on QuotesDone yet, for anyone" — never "you have no relevant experience", which is a
// statement about the supplier that the platform is in no position to make.
import React, { useCallback, useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { callShared } from './api';
import { PanelError, PanelLoading, panelErrorCode } from './PanelState';

type Lang = 'en' | 'ar';
type Reason = { key: string; applies: boolean; available?: boolean; text: string; similar_jobs?: number };
type Opportunity = {
  inquiry_id: string; project_title: string; requirement?: string | null;
  category?: string | null; emirate?: string | null;
  estimated_value?: number | null; fit_score: number | null; match_pct: number | null;
  reasons: Reason[];
};
type Payload = {
  count?: number; ordered_by?: string; note?: string | null;
  population?: { open_inquiries?: number; quotes_in_estate?: number };
  opportunities?: Opportunity[];
};

// THE THIRD COPY OF `call` IS GONE. This file and SupplierQuoteBuilder.tsx each carried a private,
// byte-identical copy of the fetch helper — the exact thing ./api.ts's own header warns about ("a
// second copy is how two error-handling behaviours start"), and both copies were weaker: no `_http`
// on a non-2xx answer, and a bare `r.json()` that REJECTS on a non-JSON body instead of resolving to
// { ok:false }. They also both fetched `opportunities` for themselves while sitting in the SAME
// Insights panel, so every open of that tab made the identical call twice (measured 18 Sep 2026 on
// production: 683 ms and 1375 ms, contending). `callShared` shares the one flight — see ./api.ts.

const T = {
  en: {
    title: 'Recommended for you', loading: 'Ranking your opportunities…',
    why: 'Why this is recommended', fit: 'fit', value: 'Estimated value',
    empty: 'Nothing to recommend yet.',
    emptyWhy: 'An opportunity appears here when a customer posts work you could win.',
    ordered: 'Ranked by fit, not by date.', notAssessable: 'not assessable yet',
    requirement: 'What they need', noBrief: 'The customer has not described the work yet.',
  },
  ar: {
    title: 'فرص موصى بها لكم', loading: 'جارٍ ترتيب الفرص…',
    why: 'سبب التوصية', fit: 'مدى الملاءمة', value: 'القيمة التقديرية',
    empty: 'لا توجد توصيات بعد.',
    emptyWhy: 'تظهر الفرص هنا عندما ينشر أحد العملاء مشروعًا يمكنكم الفوز به.',
    ordered: 'مرتّبة حسب الملاءمة، لا حسب التاريخ.', notAssessable: 'غير قابل للتقييم بعد',
    requirement: 'متطلبات العميل', noBrief: 'لم يقدّم العميل وصفًا للعمل بعد.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// A short, stable label per reason, next to the routine's sentence. The sentence is the evidence
// and varies with the data ("Nearby location — Sharjah", "not assessable — you have not described
// your capability yet"); the label is what the supplier scans down the column. Keying it here
// rather than reading it off the payload also means a wording change server-side cannot silently
// alter what the four rows are, which is the thing the supplier learns to read.
const REASON_LABEL: Record<string, { en: string; ar: string }> = {
  trade: { en: 'Your trade', ar: 'نشاطكم' },
  location: { en: 'Nearby location', ar: 'موقع قريب منكم' },
  capacity: { en: 'Your capacity fits', ar: 'قدرتكم الإنتاجية مناسبة' },
  history: { en: 'Previous similar project', ar: 'مشروع مشابه سابق' },
};

export default function SupplierOpportunities({ token, lang = 'en' }:
  { token?: string | null; lang?: Lang }) {
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  const load = useCallback(async () => {
    setErr('');
    const j = await callShared('supplier_portal', { action: 'opportunities' }, token);
    if (j && j.ok) setD(j); else setErr(panelErrorCode(j));
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  if (err) return <PanelError lang={lang} code={err} onRetry={() => { void load(); }} />;
  if (!d) return <PanelLoading lang={lang} text={t(lang, 'loading')} />;

  const list = d.opportunities || [];

  return (
    <div className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-[15px] font-semibold text-white">{t(lang, 'title')}</h2>
        <p className="text-[11px] text-muted-foreground">{t(lang, 'ordered')}</p>
      </header>

      {list.length === 0 && (
        <section className="qd-panel p-4 text-[11.5px] leading-relaxed text-muted-foreground">
          <p>{t(lang, 'empty')}</p>
          <p className="mt-1 opacity-75">{t(lang, 'emptyWhy')}</p>
          {/* The population behind the empty list — never a silent nothing. */}
          <p className="mt-1.5 opacity-50">
            {lang === 'ar'
              ? `الطلبات المفتوحة: ${d.population?.open_inquiries ?? 0} · عروض الأسعار على المنصة: ${d.population?.quotes_in_estate ?? 0}`
              : `${d.population?.open_inquiries ?? 0} open · ${d.population?.quotes_in_estate ?? 0} quotes in the estate`}
          </p>
        </section>
      )}

      {list.map((o, i) => (
        <motion.section
          key={o.inquiry_id}
          initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.22, delay: Math.min(i * 0.04, 0.2) }}
          className="qd-panel p-4"
        >
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <h3 className="text-[13.5px] font-semibold text-white">{o.project_title}</h3>
              <p className="mt-0.5 text-[11px] text-muted-foreground">
                {[o.category, o.emirate].filter(Boolean).join(' · ')}
                {o.estimated_value != null && <> · {t(lang, 'value')} {o.estimated_value}</>}
              </p>
            </div>
            {/* The match percentage. Null would mean unranked, so it is shown as such rather
                than as a zero. */}
            <div className="shrink-0 text-end">
              <div className="text-2xl font-semibold tabular-nums text-white">
                {o.match_pct == null ? '—' : o.match_pct + '%'}
              </div>
              <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'fit')}</div>
            </div>
          </div>

          {/* The requirement, in the customer's own words. NULL is a state, not a blank line. */}
          <div className="mt-2.5">
            <h4 className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'requirement')}</h4>
            <p className={o.requirement ? 'mt-0.5 text-[12.5px] leading-[1.65] text-white/85' : 'mt-0.5 text-[12.5px] italic text-muted-foreground/60'}>
              {o.requirement || t(lang, 'noBrief')}
            </p>
          </div>

          <div className="mt-3">
            <h4 className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'why')}</h4>
            <ul className="mt-1.5 flex flex-col gap-1">
              {o.reasons.map((r) => {
                const unanswerable = r.available === false;
                return (
                  <li key={r.key} className="flex items-start gap-2 text-[12px] leading-[1.6]">
                    <span aria-hidden className={
                      'mt-[6px] h-1.5 w-1.5 shrink-0 rounded-full '
                      + (unanswerable ? 'bg-white/25' : r.applies ? 'bg-ok' : 'bg-white/20')}
                    />
                    <span className={unanswerable ? 'italic text-muted-foreground/70'
                      : r.applies ? 'text-white/90' : 'text-muted-foreground'}>
                      <b className="font-medium">
                        {(REASON_LABEL[r.key] || { en: r.key, ar: r.key })[lang] || r.key}
                      </b>
                      {unanswerable && <> — <i>{t(lang, 'notAssessable')}</i></>}
                      <span className="opacity-80"> · {r.text}</span>
                    </span>
                  </li>
                );
              })}
            </ul>
          </div>
        </motion.section>
      ))}
    </div>
  );
}
