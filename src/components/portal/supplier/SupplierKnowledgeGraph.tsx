'use client';
// ROW #5 §23 — THE KNOWLEDGE GRAPH, AS THE SUPPLIER'S OWN MARKET NEIGHBOURHOOD.
//
// ── WHAT THIS SHOWS AND WHAT IT DELIBERATELY WILL NOT ───────────────────────────────────────────
// graph_nodes holds 324 nodes. 238 of them are QuotesDone's internal org chart — employees,
// departments, goals, responsibilities — and a supplier is not an audience for our reporting
// lines. fn_supplier_knowledge_graph selects category nodes only, so the filter is one predicate
// in one routine rather than a habit this component has to remember.
//
// ── EVERY NUMBER HERE IS A COUNT OF REAL COMPANIES ──────────────────────────────────────────────
// Adjacency is computed from lead_category: two categories are adjacent when at least five of the
// same companies serve both, and the edge carries that count. "Kitchen & Bathroom Suppliers,
// shared with 118 of the companies in your categories" is a fact about 17,107 rows, not a
// similarity score. Pairs below five are not drawn at all — two companies overlapping is a
// coincidence, and a line for it would be decoration.
import React, { useCallback, useEffect, useState } from 'react';
import { call } from './api';
// The one count formatter: a bare toLocaleString() follows the VIEWER's browser, not the page.
import { num } from './money';
import { PanelError, PanelLoading, panelErrorCode } from './PanelState';
import { categoryLabel } from '@/lib/categoryLabel';

type Lang = 'en' | 'ar';
// label_ar and source since 21 Sep 2026: my_categories is the confirmed trades (supplier_capabilities)
// plus the scraped lead_category rows, so a supplier with confirmed trades is never "not listed".
type Cat = {
  slug: string; label: string | null; label_ar?: string | null; companies: number | null;
  primary?: boolean | null; source?: 'lead_category' | 'confirmed_trade' | string;
};
type Adj = { slug: string; label: string | null; shared_companies: number | null; companies: number | null };
type Graph = {
  lead_id?: number; basis?: string;
  my_categories?: Cat[]; adjacent?: Adj[];
  population?: { category_nodes?: number; adjacency_edges?: number; listed_companies?: number };
};

const T = {
  en: {
    title: 'Your market neighbourhood', loading: 'Reading the knowledge graph…',
    mine: 'Your trades and categories', adjacent: 'Your competitors also serve',
    companies: 'companies', shared: 'shared with you', primary: 'primary', confirmed: 'confirmed',
    none: 'You have no confirmed trade and no category yet. Confirm what you quote for on the My scope tab and your neighbourhood appears here.',
    noneAdj: 'No adjacent category reaches the five-company floor yet.',
    basisNote: 'Two categories are adjacent when at least five of the same companies serve both.',
    graphOf: 'graph of',
    cats: 'categories', edges: 'links', listed: 'listed companies',
  },
  ar: {
    title: 'محيطكم في السوق', loading: 'جارٍ قراءة شبكة المعرفة…',
    mine: 'تخصصاتكم وفئاتكم', adjacent: 'يخدم منافسوكم أيضًا',
    companies: 'شركة', shared: 'مشتركة معكم', primary: 'أساسي', confirmed: 'مؤكَّد',
    none: 'لا يوجد لديكم تخصص مؤكَّد ولا فئة بعد. يُرجى تأكيد ما تسعّرونه من تبويب «نطاق عملي» ليظهر محيطكم هنا.',
    noneAdj: 'لا توجد بعد فئة مجاورة تخدمها خمس شركات على الأقل.',
    basisNote: 'تُعدّ الفئتان متجاورتين عندما تخدمهما خمس شركات على الأقل.',
    graphOf: 'شبكة من',
    cats: 'فئة', edges: 'رابط', listed: 'شركة مُدرجة',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// A bar whose width is the share of companies overlapping — the same width-driven chart §13 and
// §14 use, so the portal draws one kind of bar rather than three.
function Share({ n, max }: { n: number; max: number }) {
  return (
    <div className="h-1.5 rounded-full bg-white/10 overflow-hidden mt-1">
      <div
        className="h-full rounded-full bg-linear-to-r from-emerald-400 to-teal-300 transition-all duration-700"
        style={{ width: Math.max(3, (n / Math.max(max, 1)) * 100) + '%' }}
      />
    </div>
  );
}

export default function SupplierKnowledgeGraph({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [g, setG] = useState<Graph | null>(null);
  const [err, setErr] = useState('');

  const load = useCallback(async () => {
    setErr('');
    const j = await call('supplier_portal', { action: 'knowledge_graph' }, token);
    if (j && j.ok) setG(j); else setErr(panelErrorCode(j));
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  if (err) return <PanelError lang={lang} code={err} onRetry={() => { void load(); }} />;
  if (!g) return <PanelLoading lang={lang} text={t(lang, 'loading')} />;

  const mine = g.my_categories || [];
  const adj = g.adjacent || [];
  const maxShared = Math.max(...adj.map((a) => a.shared_companies || 0), 1);
  const p = g.population || {};

  return (
    <div className="space-y-4" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <section className="rounded-2xl border border-white/10 bg-white/3 backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-3">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
          <span className="text-[10px] opacity-40">
            {t(lang, 'graphOf')} {p.category_nodes ?? 0} {t(lang, 'cats')} · {p.adjacency_edges ?? 0} {t(lang, 'edges')} · {num(p.listed_companies ?? 0)} {t(lang, 'listed')}
          </span>
        </div>

        {mine.length === 0 ? (
          <p className="text-[12px] opacity-55 leading-snug">{t(lang, 'none')}</p>
        ) : (
          <>
            <div className="text-[11px] uppercase tracking-wide opacity-50 mb-1.5">{t(lang, 'mine')}</div>
            <div className="flex flex-wrap gap-1.5">
              {mine.map((c) => (
                <span
                  key={c.slug}
                  className={'rounded-full border px-2.5 py-1 text-[11px] '
                    + (c.primary
                      ? 'border-ok/30 bg-ok/8 text-ok-fg'
                      : 'border-white/12 bg-white/3 opacity-80')}
                >
                  {(lang === 'ar' && c.label_ar) || categoryLabel(c.label || c.slug, lang)}
                  {c.companies != null && <span className="opacity-55 ms-1.5 tabular-nums">{num(c.companies)}</span>}
                  {c.primary ? <span className="opacity-50 ms-1">· {t(lang, 'primary')}</span> : null}
                  {c.source === 'confirmed_trade' ? <span className="opacity-50 ms-1">· {t(lang, 'confirmed')}</span> : null}
                </span>
              ))}
            </div>
          </>
        )}
      </section>

      {mine.length > 0 && (
        <section className="rounded-2xl border border-white/10 bg-white/3 backdrop-blur-xl p-4">
          <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'adjacent')}</h3>
          {adj.length === 0 ? (
            <p className="text-[12px] opacity-55 leading-snug">{t(lang, 'noneAdj')}</p>
          ) : (
            <div className="space-y-2.5">
              {adj.map((a) => (
                <div key={a.slug}>
                  <div className="flex justify-between items-baseline gap-3 text-[12px]">
                    <span className="truncate pe-2">{categoryLabel(a.label || a.slug, lang)}</span>
                    <span className="shrink-0 tabular-nums opacity-60">
                      {num(a.shared_companies ?? 0)} {t(lang, 'shared')}
                      <span className="opacity-45"> / {num(a.companies ?? 0)} {t(lang, 'companies')}</span>
                    </span>
                  </div>
                  <Share n={a.shared_companies || 0} max={maxShared} />
                </div>
              ))}
            </div>
          )}
          <p className="text-[10px] opacity-40 mt-3 leading-snug">{t(lang, 'basisNote')}</p>
        </section>
      )}
    </div>
  );
}
