'use client';
// INSIGHTS — one section instead of twelve tabs (14 Sep 2026).
//
// The row-#5 intelligence panels were each a top-level tab, most over populations their own routines
// report as empty (0 quotes and 0 inquiries estate-wide), which made the tab strip 366px tall on a
// 375px phone and buried the journey. supplier_portal's `insights` action asks every panel routine
// once and answers available true/false per panel (rule stated there). Only available panels are
// listed; the rest are counted, never shown with invented numbers. Each panel is loaded on demand so
// neither the 3D scene nor the charts reach a supplier who never opens them.
import { useEffect, useState } from 'react';
import dynamic from 'next/dynamic';
import { motion, useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { call } from './api';

type Lang = 'en' | 'ar' | string;
const lazy = (f: () => Promise<any>) => dynamic(f, { ssr: false, loading: () => <div className="qd-panel h-40 animate-pulse motion-reduce:animate-none" aria-busy="true" /> });
const C: Record<string, any> = {
  SupplierTwin: lazy(() => import('./SupplierTwin')),
  SupplierInsightBoard: lazy(() => import('./SupplierInsightBoard')),
  SupplierEnvironment: lazy(() => import('./SupplierEnvironment')),
  MarketIntelligence: lazy(() => import('./MarketIntelligence')),
  SupplierNetworkMap: lazy(() => import('./SupplierNetworkMap')),
  SupplierKnowledgeGraph: lazy(() => import('./SupplierKnowledgeGraph')),
  CollaborationWorkspace: lazy(() => import('./CollaborationWorkspace')),
  SupplierOpportunities: lazy(() => import('./SupplierOpportunities')),
  SupplierQuoteBuilder: lazy(() => import('./SupplierQuoteBuilder')),
  SupplierTier: lazy(() => import('./SupplierTier')),
  SupplierCertifications: lazy(() => import('./SupplierCertifications')),
  ProductIntelligence: lazy(() => import('./ProductIntelligence')),
  SupplierInventory: lazy(() => import('./SupplierInventory')),
  SupplierAdvisor: lazy(() => import('./SupplierAdvisor')),
  SupplierNegotiation: lazy(() => import('./SupplierNegotiation')),
};
const PANELS: Record<string, { en: string; ar: string; parts: string[] }> = {
  recommended:    { en: 'Recommended for you', ar: 'موصى به لك',        parts: ['SupplierOpportunities', 'SupplierQuoteBuilder'] },
  twin:           { en: 'Company health',      ar: 'صحة الشركة',        parts: ['SupplierTwin', 'SupplierInsightBoard', 'SupplierEnvironment'] },
  market:         { en: 'Market',              ar: 'السوق',             parts: ['MarketIntelligence'] },
  network:        { en: 'Network',             ar: 'الشبكة',            parts: ['SupplierNetworkMap', 'SupplierKnowledgeGraph'] },
  ranking:        { en: 'Supplier score',      ar: 'تصنيف المورّد',      parts: ['SupplierTier'] },
  certifications: { en: 'Certifications',      ar: 'الشهادات',          parts: ['SupplierCertifications'] },
  products:       { en: 'Products',            ar: 'المنتجات',          parts: ['ProductIntelligence', 'SupplierInventory'] },
  workspaces:     { en: 'Workspaces',          ar: 'مساحات العمل',      parts: ['CollaborationWorkspace'] },
  assistant:      { en: 'Advisor',             ar: 'المستشار',          parts: ['SupplierAdvisor'] },
  negotiation:    { en: 'Negotiation',         ar: 'التفاوض',           parts: ['SupplierNegotiation'] },
};
export const INSIGHT_PANELS = Object.keys(PANELS);

export default function Insights({ token, lang, goTo, initial }: { token: string; lang: Lang; goTo: (t: string) => void; initial?: string | null }) {
  const ar = lang === 'ar';
  const reduce = useReducedMotion();
  const [st, setSt] = useState<{ loading: boolean; avail: string[]; hidden: number }>({ loading: true, avail: [], hidden: 0 });
  const [sel, setSel] = useState<string | null>(initial || null);
  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'insights' }, token).then((j) => {
      if (!live) return;
      const rows: { key: string; available: boolean }[] = (j && j.ok && j.panels) || [];
      const avail = INSIGHT_PANELS.filter((k) => rows.some((r) => r.key === k && r.available));
      setSt({ loading: false, avail, hidden: INSIGHT_PANELS.length - avail.length });
      setSel((s) => (s && avail.includes(s) ? s : avail[0] || null));
    }).catch(() => live && setSt({ loading: false, avail: [], hidden: INSIGHT_PANELS.length }));
    return () => { live = false; };
  }, [token]);

  if (st.loading) return <div className="qd-panel h-32 animate-pulse motion-reduce:animate-none" aria-busy="true" />;
  if (!st.avail.length) return (
    <section className="qd-panel p-5">
      <h2 className="text-[15.5px] font-bold text-white">{ar ? 'الرؤى' : 'Insights'}</h2>
      <p className="mt-1 max-w-[62ch] text-[13px] leading-[1.65] text-muted-foreground">{ar
        ? 'لا توجد رؤى بعد. تظهر كل لوحة فور وجود بيانات حقيقية خلفها — لا نعرض رقمًا لم نقِسه.'
        : 'No insights yet. Each panel appears as soon as there is real data behind it — we never show a number we have not measured.'}</p>
    </section>
  );
  const panel = sel ? PANELS[sel] : null;
  return (
    <section aria-labelledby="qd-insights-h">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="qd-insights-h" className="font-[family-name:var(--font-head)] text-[17px] font-bold text-white">{ar ? 'الرؤى' : 'Insights'}</h2>
        {st.hidden > 0 && <span className="text-[11.5px] text-muted-foreground">{ar ? `${st.hidden} لوحات مخفية حتى تتوفر بيانات` : `${st.hidden} panel${st.hidden === 1 ? '' : 's'} hidden until there is data`}</span>}
      </div>
      <nav aria-label={ar ? 'لوحات الرؤى' : 'Insight panels'} className="mb-4 flex flex-wrap gap-1.5">
        {st.avail.map((k) => (
          <button key={k} type="button" aria-current={sel === k ? 'page' : undefined} onClick={() => setSel(k)}
            className={cn('rounded-full border px-3 py-1.5 text-[12.5px] font-semibold transition-colors',
              sel === k ? 'border-primary/60 bg-primary/15 text-primary' : 'border-[var(--line)] text-muted-foreground hover:border-primary/40')}>
            {ar ? PANELS[k].ar : PANELS[k].en}
          </button>
        ))}
      </nav>
      {panel && (
        <motion.div key={sel} className="space-y-4" initial={reduce ? false : { opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35 }}>
          {panel.parts.map((p) => { const Comp = C[p]; return <Comp key={p} token={token} lang={lang} goTo={goTo} />; })}
        </motion.div>
      )}
    </section>
  );
}
