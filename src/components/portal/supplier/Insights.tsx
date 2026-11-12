'use client';
// INSIGHTS — one section instead of twelve tabs (14 Sep 2026).
//
// The row-#5 intelligence panels were each a top-level tab, most over populations their own routines
// report as empty (0 quotes and 0 inquiries estate-wide), which made the tab strip 366px tall on a
// 375px phone and buried the journey. supplier_portal's `insights` action asks every panel routine
// once and answers available true/false per panel (rule stated there). Only available panels are
// listed; the rest are counted, never shown with invented numbers. Each panel is loaded on demand so
// the charts do not reach a supplier who never opens them.
//
// 21 Sep 2026 (founder instructions 525/526): the 3D company environment (SupplierEnvironment), the
// 3D supplier network map (SupplierNetworkMap) and the negotiation panel (SupplierNegotiation) were
// removed — "its useless remove it". The twin panel keeps the health board; the network panel keeps
// the knowledge graph.
import { useEffect, useRef, useState } from 'react';
import dynamic from 'next/dynamic';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { call } from './api';
// `call` resolves on every failure (./api.ts), so a read that FAILED arrives as an object with
// ok:false — indistinguishable from an empty answer unless `j.ok` is tested. Until 22 Sep 2026 this
// tab read `(j && j.ok && j.panels) || []` and then rendered "nothing to show" under a promise that
// says we never show a number we have not measured, and it had no expired-session path at all.
import { PanelError, panelErrorCode } from './PanelState';

type Lang = 'en' | 'ar' | string;
const lazy = (f: () => Promise<any>) => dynamic(f, { ssr: false, loading: () => <div className="qd-panel h-40 animate-pulse motion-reduce:animate-none" aria-busy="true" /> });
const C: Record<string, any> = {
  SupplierTwin: lazy(() => import('./SupplierTwin')),
  SupplierInsightBoard: lazy(() => import('./SupplierInsightBoard')),
  MarketIntelligence: lazy(() => import('./MarketIntelligence')),
  SupplierKnowledgeGraph: lazy(() => import('./SupplierKnowledgeGraph')),
  CollaborationWorkspace: lazy(() => import('./CollaborationWorkspace')),
  SupplierOpportunities: lazy(() => import('./SupplierOpportunities')),
  SupplierQuoteBuilder: lazy(() => import('./SupplierQuoteBuilder')),
  SupplierTier: lazy(() => import('./SupplierTier')),
  SupplierCertifications: lazy(() => import('./SupplierCertifications')),
  ProductIntelligence: lazy(() => import('./ProductIntelligence')),
  SupplierInventory: lazy(() => import('./SupplierInventory')),
  SupplierAdvisor: lazy(() => import('./SupplierAdvisor')),
};
// Each holds its loaded size while its chunk arrives (walk of 12 Nov 2026, S11; see `summary` below).
const Summary: any = dynamic(() => import('./SupplierInsightsSummary'), { ssr: false, loading: () => <section className="qd-panel min-h-svh animate-pulse motion-reduce:animate-none" aria-busy="true" /> });
// 29 Sep 2026 (founder_instruction 1013 item 2): last month's scorecard against the trade opens the tab, in English.
const Scorecard: any = dynamic(() => import('./SupplierScorecard'), { ssr: false, loading: () => <section className="qd-panel min-h-56 sm:min-h-[134px]" aria-busy="true" /> });
const PANELS: Record<string, { en: string; ar: string; parts: string[] }> = {
  recommended:    { en: 'Recommended for you', ar: 'مقترح لكم',         parts: ['SupplierOpportunities', 'SupplierQuoteBuilder'] },
  twin:           { en: 'Company health',      ar: 'صحة الشركة',        parts: ['SupplierTwin', 'SupplierInsightBoard'] },
  market:         { en: 'Market',              ar: 'السوق',             parts: ['MarketIntelligence'] },
  network:        { en: 'Network',             ar: 'الشبكة',            parts: ['SupplierKnowledgeGraph'] },
  ranking:        { en: 'Supplier score',      ar: 'تصنيف المورّد',      parts: ['SupplierTier'] },
  certifications: { en: 'Certifications',      ar: 'الشهادات',          parts: ['SupplierCertifications'] },
  products:       { en: 'Products',            ar: 'المنتجات',          parts: ['ProductIntelligence', 'SupplierInventory'] },
  workspaces:     { en: 'Workspaces',          ar: 'مساحات العمل',      parts: ['CollaborationWorkspace'] },
  assistant:      { en: 'Sales engineer',      ar: 'مهندس المبيعات',         parts: ['SupplierAdvisor'] },
};
export const INSIGHT_PANELS = Object.keys(PANELS);

export default function Insights({ token, lang, goTo, initial }: { token: string; lang: Lang; goTo: (t: string) => void; initial?: string | null }) {
  const ar = lang === 'ar';
  const reduce = useReducedMotion();
  const [st, setSt] = useState<{ loading: boolean; avail: string[]; hidden: number; err: string }>({ loading: true, avail: [], hidden: 0, err: '' });
  const [sel, setSel] = useState<string | null>(initial || null);
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);
  const load = () => {
    setSt((s) => ({ ...s, loading: true, err: '' }));
    call('supplier_portal', { action: 'insights' }, token).then((j) => {
      if (!live.current) return;
      if (!j || !j.ok) { setSt({ loading: false, avail: [], hidden: 0, err: panelErrorCode(j) }); return; }
      const rows: { key: string; available: boolean }[] = j.panels || [];
      const avail = INSIGHT_PANELS.filter((k) => rows.some((r) => r.key === k && r.available));
      setSt({ loading: false, avail, hidden: INSIGHT_PANELS.length - avail.length, err: '' });
      setSel((s) => (s && avail.includes(s) ? s : avail[0] || null));
    });
  };
  useEffect(() => { load(); }, [token]);

  // 15 Sep 2026: the tab opens on the supplier's own performance (totals, price position, funnel, trend,
  // hints — ./SupplierInsightsSummary.tsx), which always renders, zeros included. The intelligence panels
  // follow, and only those with real data behind them.
  // NOTHING MOVES WHEN INSIGHTS OPENS (walk of 12 Nov 2026, S11; founder ruling 1645). Measured on origin/main with the stub: CLS 0.62
  // at 390x844, 0.43 at 360x640, 0.39 at 1440x900. The scorecard and the summary are separate chunks that arrived in either order with no
  // space held for them, and the summary's 192 px placeholder became 1,250-1,950 px, pushing "More analysis" down under his eyes. Each now
  // has its own boundary holding its loaded size: the scorecard its card (224 px on a phone, 134 px wide; measured 204-224 / 134), the
  // summary at least a screen, so what follows starts below the fold until the figures are in.
  const summary = <><Scorecard token={token} /><Summary token={token} lang={lang} goTo={goTo} /></>;
  if (st.loading) return <>{summary}<div className="qd-panel h-32 animate-pulse motion-reduce:animate-none" aria-busy="true" /></>;
  // The read failed. This tab is not given an `onExpired` route by its parent (SupplierPortal.tsx
  // renders `<Insights token lang goTo initial />`), so an expired session is said in words here
  // instead of being silently redrawn as "nothing to show".
  if (st.err) return <>{summary}<PanelError lang={ar ? 'ar' : 'en'} code={st.err} onRetry={load} /></>;
  if (!st.avail.length) return (
    <>{summary}
    <section className="qd-panel p-5">
      <h2 className="text-[15.5px] font-bold text-foreground">{ar ? 'تحليلات إضافية' : 'More analysis'}</h2>
      <p className="mt-1 max-w-[62ch] text-[13px] leading-[1.65] text-muted-foreground">{ar
        ? 'تظهر كل لوحة تحليل إضافية فور وجود بيانات حقيقية خلفها — لا نعرض رقمًا لم نقِسه.'
        : 'Each further analysis panel appears as soon as there is real data behind it — we never show a number we have not measured.'}</p>
    </section></>
  );
  const panel = sel ? PANELS[sel] : null;
  return (
    <>{summary}
    <section aria-labelledby="qd-insights-h">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="qd-insights-h" className="font-head text-h3 tracking-snug text-foreground">{ar ? 'تحليلات إضافية' : 'More analysis'}</h2>
        {st.hidden > 0 && <span className="font-mono text-[11.5px] text-muted-foreground">{ar ? `عدد اللوحات المخفية حتى تتوفر البيانات: ${st.hidden}` : `${st.hidden} panel${st.hidden === 1 ? '' : 's'} hidden until there is data`}</span>}
      </div>
      <nav aria-label={ar ? 'لوحات التحليل' : 'Insight panels'} className="mb-4 flex flex-wrap gap-1.5">
        {st.avail.map((k) => (
          <button key={k} type="button" aria-current={sel === k ? 'page' : undefined} onClick={() => setSel(k)}
            className={cn('inline-flex min-h-11 min-w-11 items-center justify-center rounded-chip border px-3 py-1.5 text-[12.5px] font-medium transition-colors',
              sel === k ? 'border-primary/60 bg-primary/15 text-primary' : 'border-(--line) text-muted-foreground hover:border-primary/40')}>
            {ar ? PANELS[k].ar : PANELS[k].en}
          </button>
        ))}
      </nav>
      {panel && (
        <motion.div key={sel} className="space-y-4" initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35 }}>
          {panel.parts.map((p) => { const Comp = C[p]; return <Comp key={p} token={token} lang={lang} goTo={goTo} />; })}
        </motion.div>
      )}
    </section></>
  );
}
