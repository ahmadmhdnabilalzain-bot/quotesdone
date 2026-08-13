'use client';
// ROW #5 §24 — INVENTORY. What the supplier can actually deliver, and how soon.
//
// ── THIS READS THE CATALOGUE, IT DOES NOT INTRODUCE A SECOND ONE ────────────────────────────────
// Availability lives in supplier_product.attributes beside capacity and refrigerant, because it is
// a per-product fact of the same kind. There is no inventory table and there should not be one: a
// second store of "which products exist" would drift from the catalogue the moment either changed.
//
// ── A PRODUCT WITH NO STATED AVAILABILITY IS SHOWN, NOT HIDDEN ──────────────────────────────────
// That is the honest default on a platform where no real supplier has filled this in yet. Hiding
// them would make an empty inventory look like a small one; listing them as "not stated" makes the
// gap visible and gives the supplier the one thing worth doing about it. The counter at the top
// counts the gap on purpose.
import React, { useEffect, useMemo, useState } from 'react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Attrs = Record<string, unknown>;
type Product = {
  id?: string; name?: string; brand?: string; model?: string; external_key?: string;
  category_slug?: string; subcategory_slug?: string; status?: string; attributes?: Attrs;
};

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
    title: 'Inventory', loading: 'Reading your catalogue…',
    empty: 'No products yet. Upload a catalogue and they will appear here.',
    inStock: 'In stock', madeToOrder: 'Made to order', notStated: 'Not stated',
    units: 'units', restock: 'lead time', weeks: 'weeks',
    stated: 'with a stated stock position', gap: 'still to state',
    gapHelp: 'Customers see delivery confidence on your quotes. Products with no stated position are quoted blind.',
    goProducts: 'Open Product Intelligence',
    all: 'All', search: 'Filter by name, brand or model',
  },
  ar: {
    title: 'المخزون', loading: 'جارٍ قراءة الكتالوج…',
    empty: 'لا توجد منتجات بعد. ارفع كتالوجًا لتظهر هنا.',
    inStock: 'متوفر', madeToOrder: 'حسب الطلب', notStated: 'غير محدد',
    units: 'وحدة', restock: 'مدة التوريد', weeks: 'أسبوع',
    stated: 'بحالة مخزون محددة', gap: 'بحاجة إلى تحديد',
    gapHelp: 'يرى العملاء مدى التزامك بالتسليم في عروضك. المنتجات غير المحددة تُسعَّر دون معرفة.',
    goProducts: 'افتح ذكاء المنتجات',
    all: 'الكل', search: 'ابحث بالاسم أو العلامة أو الطراز',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

const attr = (p: Product, k: string): string | null => {
  const v = (p.attributes || {})[k];
  return v === undefined || v === null || v === '' ? null : String(v);
};

export default function SupplierInventory({ token, lang = 'en', goTo }:
  { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const [rows, setRows] = useState<Product[]>([]);
  const [q, setQ] = useState('');
  const [loaded, setLoaded] = useState(false);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'products', q: '' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setRows(Array.isArray(j.products) ? j.products : (j.items || []));
      else setErr((j && (j.error || j.hint)) || 'load_err');
      setLoaded(true);
    });
    return () => { live = false; };
  }, [token]);

  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    if (!s) return rows;
    return rows.filter((p) =>
      [p.name, p.brand, p.model, p.external_key, p.subcategory_slug]
        .filter(Boolean).join(' ').toLowerCase().includes(s));
  }, [q, rows]);

  const withPosition = rows.filter((p) => attr(p, 'availability')).length;
  const missing = rows.length - withPosition;

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!loaded) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;
  if (!rows.length) return <div className="text-xs opacity-60 p-4">{t(lang, 'empty')}</div>;

  return (
    <div className="space-y-4">
      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <div className="flex justify-between items-baseline mb-3">
          <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
          <span className="text-[10px] opacity-40">{rows.length} products</span>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <div className="text-2xl font-semibold tabular-nums">{withPosition}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'stated')}</div>
          </div>
          <div>
            <div className={'text-2xl font-semibold tabular-nums ' + (missing ? 'text-amber-300' : '')}>{missing}</div>
            <div className="text-[10px] uppercase tracking-wide opacity-50">{t(lang, 'gap')}</div>
          </div>
        </div>
        {missing > 0 && (
          <p className="text-[10px] opacity-45 mt-2 leading-snug">
            {t(lang, 'gapHelp')}
            {goTo && (
              <button type="button" onClick={() => goTo('products')} className="ms-1 underline underline-offset-2 hover:opacity-100">
                {t(lang, 'goProducts')}
              </button>
            )}
          </p>
        )}
      </section>

      <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
        <input
          className="w-full rounded-lg border border-white/10 bg-white/[0.04] px-3 py-2 text-sm outline-none focus:border-white/25 mb-3"
          placeholder={t(lang, 'search')}
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <div className="space-y-1.5">
          {shown.map((p) => {
            const av = attr(p, 'availability');
            const qty = attr(p, 'stock_qty');
            const wk = attr(p, 'restock_weeks');
            const label = av === 'in_stock' ? t(lang, 'inStock')
              : av === 'made_to_order' ? t(lang, 'madeToOrder') : t(lang, 'notStated');
            const tone = av === 'in_stock' ? 'text-emerald-300 border-emerald-300/25 bg-emerald-300/[0.06]'
              : av === 'made_to_order' ? 'text-sky-300 border-sky-300/25 bg-sky-300/[0.06]'
              : 'text-white/45 border-white/10 bg-white/[0.02]';
            return (
              <div key={p.id || p.external_key} className="rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2">
                <div className="flex justify-between items-start gap-3">
                  <div className="min-w-0">
                    <div className="text-[13px] truncate">{p.name}</div>
                    <div className="text-[11px] opacity-45 truncate">
                      {[p.brand, p.model, p.subcategory_slug].filter(Boolean).join(' · ')}
                    </div>
                  </div>
                  <span className={'shrink-0 rounded-full border px-2 py-0.5 text-[10px] ' + tone}>{label}</span>
                </div>
                {(qty || wk) && (
                  <div className="text-[11px] opacity-55 mt-1 tabular-nums">
                    {qty !== null && av === 'in_stock' ? qty + ' ' + t(lang, 'units') : ''}
                    {qty !== null && av === 'in_stock' && wk ? ' · ' : ''}
                    {wk ? t(lang, 'restock') + ' ' + wk + ' ' + t(lang, 'weeks') : ''}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
}
