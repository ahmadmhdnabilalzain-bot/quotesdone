'use client';
// ROW #5 §15 §4 — THE SUPPLIER AI EMPLOYEE.
//
// ── THE ONE THING THIS COMPONENT MUST NOT DO ────────────────────────────────────────────────────
// §15's mock draws a loss breakdown: "60% Price, 25% Delivery, 15% Missing certificates". Production
// holds 0 quotes and 0 inquiries. There is no loss history to break down, for this supplier or any
// other, so this component renders NO percentages and says plainly why.
//
// A fabricated breakdown would be the most persuasive lie the portal could tell: it reads as
// insight, it would turn a MISSING check green, and a supplier could act on it — changing their
// pricing because a chart said price was costing them 60% of their losses, when nothing was
// measured at all. The empty state is the honest output, and it carries its own reason.
//
// What IS real today is the gap list. Every recommendation below is computed from a column the
// supplier can act on — a missing licence, an expired ISO certificate, an empty capability summary
// — and each links to the tab that fixes it. That is the truthful answer to "why am I losing":
// today it is "you are not yet eligible to compete", and that is worth saying.
import React, { useEffect, useState } from 'react';

type Rec = {
  key: string; action: string; why: string;
  severity: 'high' | 'medium' | 'low' | string;
  goes_to?: string; impact_rfqs?: number | null;
};
type Advice = {
  headline?: string; gap_count?: number; recommendations?: Rec[];
  loss_analysis?: {
    quotes_submitted?: number; quotes_won?: number; rejections?: number;
    loss_reasons?: { reason: string; count: number; pct: number }[]; basis?: string;
  };
  impact_basis?: { live_inquiries?: number; note?: string };
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
    title: 'AI Assistant', ask: 'Why am I losing RFQs?',
    lossTitle: 'Lost opportunities', recTitle: 'What to do next',
    noHistory: 'You have not quoted on anything yet, so there is nothing to analyse. '
      + 'No breakdown is shown rather than an invented one.',
    submitted: 'Quoted', won: 'Won', rejected: 'Rejected',
    fix: 'Fix this', loading: 'Analysing your account…',
    allGood: 'Nothing to fix.', opportunities: 'live opportunities',
    high: 'blocking', medium: 'limiting', low: 'minor',
  },
  ar: {
    title: 'المساعد الذكي', ask: 'لماذا أخسر الطلبات؟',
    lossTitle: 'الفرص الخاسرة', recTitle: 'الخطوة التالية',
    noHistory: 'لم تقدّم أي عرض سعر بعد، لذا لا يوجد ما يمكن تحليله. '
      + 'لا نعرض تحليلًا مُختلقًا.',
    submitted: 'عروض مقدمة', won: 'فائزة', rejected: 'مرفوضة',
    fix: 'إصلاح', loading: 'جارٍ تحليل حسابك…',
    allGood: 'لا يوجد ما يحتاج إصلاحًا.', opportunities: 'فرص متاحة',
    high: 'يمنع', medium: 'يحدّ', low: 'بسيط',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

const SEV: Record<string, string> = {
  high: 'border-rose-400/40 bg-rose-400/10 text-rose-200',
  medium: 'border-amber-400/40 bg-amber-400/10 text-amber-200',
  low: 'border-white/15 bg-white/5 opacity-80',
};

export default function SupplierAdvisor({
  token, lang = 'en', goTo,
}: { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const [a, setA] = useState<Advice | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'advisor' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setA(j);
      else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!a) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const loss = a.loss_analysis || {};
  const reasons = loss.loss_reasons || [];
  const recs = a.recommendations || [];

  return (
    <div className="space-y-4">
      {/* §4's actionable assistant line: a concrete gap AND a quantified upside, or nothing to fix. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-2">{t(lang, 'title')}</h3>
        <p className="text-sm leading-relaxed">{a.headline}</p>
      </section>

      {/* §15 — the loss question, asked in the supplier's own words. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="text-[13px] font-medium mb-3">{t(lang, 'ask')}</div>

        <div className="grid grid-cols-3 gap-4 mb-3">
          <div><div className="text-xl font-semibold tabular-nums">{loss.quotes_submitted ?? 0}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'submitted')}</div></div>
          <div><div className="text-xl font-semibold tabular-nums">{loss.quotes_won ?? 0}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'won')}</div></div>
          <div><div className="text-xl font-semibold tabular-nums">{loss.rejections ?? 0}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'rejected')}</div></div>
        </div>

        {/* NO INVENTED BREAKDOWN. The empty state states its own reason. */}
        {reasons.length === 0 ? (
          <p className="text-[11px] opacity-60 leading-relaxed border-t border-white/10 pt-3">
            {t(lang, 'noHistory')}
            {loss.basis && <span className="opacity-40"> ({loss.basis})</span>}
          </p>
        ) : (
          <div className="border-t border-white/10 pt-3 space-y-2">
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'lossTitle')}</div>
            {reasons.map((r) => (
              <div key={r.reason}>
                <div className="flex justify-between text-[11px] mb-1">
                  <span className="opacity-70">{r.reason}</span>
                  <span className="tabular-nums">{r.pct}% ({r.count})</span>
                </div>
                <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
                  <div className="h-full rounded-full bg-rose-400/70 transition-all duration-700"
                       style={{ width: Math.max(2, Math.min(100, r.pct)) + '%' }} />
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* §15's recommendations. Each links to the tab that fixes it — advice you cannot act on is
          a sentence, not an assistant. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-3">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'recTitle')}</h3>
          {a.impact_basis?.live_inquiries != null && (
            <span className="text-[10px] opacity-50">
              {a.impact_basis.live_inquiries} {t(lang, 'opportunities')}
            </span>
          )}
        </div>
        {recs.length === 0 ? (
          <p className="text-[11px] opacity-60">{t(lang, 'allGood')}</p>
        ) : (
          <ul className="space-y-2">
            {recs.map((r) => (
              <li key={r.key} className={`rounded-xl border px-3 py-2.5 ${SEV[r.severity] || SEV.low}`}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-[12.5px] font-medium">{r.action}</div>
                    <div className="text-[11px] opacity-75 leading-relaxed mt-0.5">{r.why}</div>
                    <div className="text-[10px] uppercase tracking-wide opacity-50 mt-1">
                      {t(lang, (r.severity as 'high' | 'medium' | 'low')) || r.severity}
                    </div>
                  </div>
                  {r.goes_to && goTo && (
                    <button
                      type="button"
                      onClick={() => goTo(r.goes_to as string)}
                      className="shrink-0 rounded-lg border border-white/20 px-2.5 py-1 text-[11px] hover:bg-white/10"
                    >
                      {t(lang, 'fix')}
                    </button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
