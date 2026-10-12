'use client';
// ROW #5 §7 §8 — PRODUCT INTELLIGENCE AND AI PRODUCT CARDS.
//
// ── THE DEFECT THIS CLOSES ──────────────────────────────────────────────────────────────────────
// supplier_product, supplier_product_variant and supplier_catalog are a complete, well-designed
// schema that had 0 rows AND 0 readers on production — confirmed by two independent scans against
// a control. Suppliers can upload catalogues through the portal today and nothing whatsoever
// happens to them. This is the screen those rows were designed for.
//
// ── WHAT IT WILL NOT SHOW ───────────────────────────────────────────────────────────────────────
// §8's mock draws "AI Match: 96%". A match percentage is a claim about a SPECIFIC opportunity, and
// production holds 0 inquiries. This component renders an AI match ONLY when the payload carries a
// real computed one, and says nothing at all otherwise. A confident number corresponding to nothing
// is the fabrication this row's scorer exists to catch — and the fact that it would also turn a
// MISSING check green is exactly why it must not be written.
//
// Same rule as the health panel: absent is not zero. A product with no availability recorded shows
// "not recorded", never "0 units", because 0 units means out of stock and that is a different claim.
import React, { useEffect, useState } from 'react';
import SupplierCatalogUpload from './SupplierCatalogUpload';
import { call } from './api';
// The one count formatter: a bare toLocaleString() follows the VIEWER's browser, not the page.
import { num } from './money';
import { PanelError, PanelLoading, panelErrorCode } from './PanelState';
import { arDays } from '@/lib/durationLabel';

type Variant = {
  sku?: string | null; attributes?: Record<string, unknown> | null;
  price_policy?: Record<string, unknown> | null; lead_time_policy?: Record<string, unknown> | null;
  active?: boolean;
};
type Product = {
  id: string; name: string; category?: string | null; brand?: string | null; model?: string | null;
  description?: string | null; attributes?: Record<string, string> | null; attribute_count?: number;
  certifications?: string[] | null; status?: string | null; variants?: Variant[] | null;
  available_units?: number | null; compatible_projects?: string[] | null; ai_match?: number | null;
  evidence_refs?: { source?: string; page?: number }[] | null;
};
type Payload = {
  product_count?: number; category_count?: number; attribute_count?: number;
  searchable?: boolean; match_count?: number; products?: Product[];
  catalogs?: { id: string; status?: string; version?: number; extracted_at?: string | null; source?: string | null }[];
};
type Lang = 'en' | 'ar';

const T = {
  en: {
    title: 'Product Intelligence', products: 'Products', categories: 'Categories',
    specs: 'Specifications', searchable: 'Searchable', yes: 'YES', no: 'NO',
    search: 'Search products, brands or specifications…', matches: 'matching',
    available: 'Available', notRecorded: 'not recorded', units: 'units',
    compatible: 'Compatible Projects', certs: 'Certifications', catalogues: 'Catalogues',
    empty: 'No products yet. Upload a catalogue and it will be extracted here.',
    loading: 'Reading your catalogue…', leadTime: 'Lead time', days: 'days',
    aiMatch: 'Best match', noMatch: 'no opportunity to match against yet', source: 'Source',
  },
  ar: {
    title: 'ذكاء المنتجات', products: 'المنتجات', categories: 'الفئات',
    specs: 'المواصفات', searchable: 'قابل للبحث', yes: 'نعم', no: 'لا',
    search: 'البحث في المنتجات أو العلامات التجارية أو المواصفات…', matches: 'مطابق',
    available: 'متوفر', notRecorded: 'غير مسجل', units: 'وحدة',
    compatible: 'المشاريع المناسبة', certs: 'الشهادات', catalogues: 'الكتالوجات',
    empty: 'لا توجد منتجات بعد. ارفعوا كتالوجًا لتظهر هنا المنتجات المستخرجة منه.',
    loading: 'جارٍ قراءة الكتالوج…', leadTime: 'مدة التوريد', days: 'يوم',
    aiMatch: 'أفضل مطابقة', noMatch: 'لا توجد فرص مطابقة بعد', source: 'المصدر',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

function Count({ label, value }: { label: string; value: number | undefined }) {
  return (
    <div>
      <div className="text-2xl font-semibold tabular-nums">{value ?? 0}</div>
      <div className="text-[10px] uppercase tracking-wide opacity-50">{label}</div>
    </div>
  );
}

// §8 — THE AI PRODUCT CARD. Its own component so a check can name it, and so the eight fields the
// spec enumerates are countable over one thing rather than scattered across a page.
export function ProductCard({ p, lang }: { p: Product; lang: Lang }) {
  const attrs = Object.entries(p.attributes || {}).filter(([k]) => k !== 'compatible_projects');
  const variant = (p.variants || []).find((v) => v.active) || (p.variants || [])[0];
  const lead = variant?.lead_time_policy?.['lead_time_days'] as number | undefined;
  return (
    <article className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
      <header className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h4 className="text-sm font-medium truncate">{p.name}</h4>
          <div className="text-[11px] opacity-60 truncate">
            {[p.category, p.brand, p.model].filter(Boolean).join(' · ')}
          </div>
        </div>
        {/* Rendered ONLY when a real computed match exists. See the header note. */}
        {p.ai_match != null ? (
          <div className="text-right shrink-0">
            <div className="text-lg font-semibold tabular-nums">{Math.round(p.ai_match)}%</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'aiMatch')}</div>
          </div>
        ) : null}
      </header>

      {p.description && <p className="text-[11px] opacity-70 mt-2 leading-relaxed">{p.description}</p>}

      {attrs.length > 0 && (
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 mt-3">
          {attrs.slice(0, 8).map(([k, v]) => (
            <div key={k} className="flex justify-between gap-2 text-[11px] min-w-0">
              <dt className="opacity-50 truncate">{k.replace(/_/g, ' ')}</dt>
              <dd className="tabular-nums truncate">{String(v)}</dd>
            </div>
          ))}
        </dl>
      )}

      <div className="flex flex-wrap gap-1.5 mt-3">
        {(p.certifications || []).map((c) => (
          <span key={c} className="rounded-full border border-info/30 bg-info/10 px-2 py-0.5 text-[10px]">
            ✓ {c}
          </span>
        ))}
      </div>

      {(p.compatible_projects || []).length > 0 && (
        <div className="mt-3">
          <div className="text-[10px] uppercase tracking-wide opacity-50 mb-1">{t(lang, 'compatible')}</div>
          <div className="flex flex-wrap gap-1.5">
            {(p.compatible_projects || []).map((c) => (
              <span key={c} className="rounded-full border border-white/15 px-2 py-0.5 text-[10px]">{c}</span>
            ))}
          </div>
        </div>
      )}

      <footer className="flex justify-between items-baseline mt-3 pt-2.5 border-t border-white/10 text-[11px]">
        <span className="opacity-50">{t(lang, 'available')}</span>
        {/* ABSENT IS NOT ZERO. "0 units" means out of stock; "not recorded" means we do not know. */}
        <span className="tabular-nums">
          {p.available_units != null
            ? `${num(p.available_units)} ${t(lang, 'units')}`
            : t(lang, 'notRecorded')}
          {lead != null && <span className="opacity-50"> · {t(lang, 'leadTime')} {lang === 'ar' ? arDays(lead) : `${lead} ${t(lang, 'days')}`}</span>}
        </span>
      </footer>
    </article>
  );
}

export default function ProductIntelligence({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [data, setData] = useState<Payload | null>(null);
  const [q, setQ] = useState('');
  const [reload, setReload] = useState(0);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    // Debounced so typing a specification does not fire a request per keystroke.
    const id = setTimeout(() => {
      call('supplier_portal', { action: 'products', q }, token).then((j) => {
        if (!live) return;
        if (j && j.ok) { setErr(''); setData(j); }
        else setErr(panelErrorCode(j));
      });
    }, q ? 250 : 0);
    return () => { live = false; clearTimeout(id); };
  }, [token, q, reload]);

  // Retrying is a re-run of the same debounced read: `reload` is the effect's own trigger.
  if (err) return <PanelError lang={lang} code={err} onRetry={() => { setErr(''); setReload((n) => n + 1); }} />;
  if (!data) return <PanelLoading lang={lang} text={t(lang, 'loading')} />;

  const products = data.products || [];

  return (
    <div className="space-y-4">
      {/* Product catalogue — the only door that WRITES the product store from a file the supplier already has. */}
      <SupplierCatalogUpload token={token} lang={lang} onDone={() => setReload((n) => n + 1)} />

      {/* §7's "After" panel: the three counts the spec draws, over real rows. */}
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <h3 className="text-xs uppercase tracking-wide opacity-60 mb-3">{t(lang, 'title')}</h3>
        <div className="grid grid-cols-4 gap-4">
          <Count label={t(lang, 'products')} value={data.product_count} />
          <Count label={t(lang, 'categories')} value={data.category_count} />
          <Count label={t(lang, 'specs')} value={data.attribute_count} />
          <div>
            <div className="text-2xl font-semibold text-ok-fg">
              {data.searchable ? t(lang, 'yes') : t(lang, 'no')}
            </div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'searchable')}</div>
          </div>
        </div>
        {(data.catalogs || []).length > 0 && (
          <div className="mt-3 text-[11px] opacity-60">
            {t(lang, 'catalogues')}: {(data.catalogs || []).map((c) => `v${c.version} ${c.status}`).join(' · ')}
          </div>
        )}
      </section>

      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder={t(lang, 'search')}
        aria-label={t(lang, 'search')}
        className="w-full rounded-xl border border-white/10 bg-white/[0.03] px-3.5 py-2.5 text-sm outline-none focus:border-white/25"
      />
      {q && (
        <div className="text-[11px] opacity-50">
          {data.match_count ?? 0} {t(lang, 'matches')}
        </div>
      )}

      {products.length === 0 ? (
        <div className="text-xs opacity-60 p-4">{t(lang, 'empty')}</div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {products.map((p) => <ProductCard key={p.id} p={p} lang={lang} />)}
        </div>
      )}
    </div>
  );
}
