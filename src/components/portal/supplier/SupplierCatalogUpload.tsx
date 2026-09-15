'use client';
// ROW #5 §7 §24 — CATALOG AI. The supplier's own catalogue becomes their product store.
//
// §7's premise is that a supplier should not type 245 products into a form — they already have the
// list, in a price list, a spreadsheet, a PDF catalogue or a drawing schedule. This is the door for
// that, and it is the only thing in the estate that WRITES supplier_product from a file.
//
// ── THE ACCEPTED FORMATS ARE THE ONES THAT CAN ACTUALLY BE READ ─────────────────────────────────
//   .csv .tsv .txt   parsed as a table, no model involved
//   .xlsx .xls       parsed as a table
//   .pdf and images  read by the vision model
//   .dwg .dxf        converted to a PDF sheet first, then read — schedule and title block
//   .ifc .rvt        same route; a BIM model is geometry, and what is extractable is its schedule
//
// A drawing is not a catalogue and this does not pretend otherwise: what comes back from a sheet is
// what a human would read off it. The result panel prints the route taken, so a supplier can see
// whether their file was parsed, converted, or stored without extraction.
//
// ── AND "0 PRODUCTS" IS NOT "WE COULD NOT READ IT" ──────────────────────────────────────────────
// Those look identical on screen and mean completely different things. The endpoint distinguishes
// them — extracted / no_products_found / unsupported_format / conversion_failed — and each renders
// its own sentence, because a supplier who thinks their catalogue was read will not re-upload it.
import React, { useRef, useState } from 'react';
import { motion } from 'motion/react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Result = {
  ok?: boolean; catalog_id?: string | null; format?: string;
  products_created?: number; products_found?: number; note?: string;
  status?: string; why?: string; error?: string;
};

const FN = SUPA_FN;
const ANON = SUPA_ANON;

// The same call() every sibling component uses. The first version hand-rolled its fetch, which
// worked and was still wrong: the endpoint name never appeared as a literal next to `call(` or
// `functions/v1/`, so nothing scanning this surface could tell that the portal reaches
// supplier_catalog_ingest at all. Consistency here is not tidiness — it is how the endpoint stays
// discoverable from the code that uses it.
async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(FN + '/' + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

// Every format the ingester can route. Kept here as one list so the accept attribute and the help
// text can never disagree about what the supplier may upload.
const ACCEPT = '.csv,.tsv,.txt,.xlsx,.xls,.pdf,.png,.jpg,.jpeg,.webp,.dwg,.dxf,.ifc,.rvt';

const T = {
  en: {
    title: 'Catalog AI', lead: 'Upload your product catalog, price list, spreadsheet or drawing. We read it and build your product records.',
    formats: 'Price lists and spreadsheets (CSV, Excel), catalogs (PDF, images), and CAD or BIM drawings (DWG, DXF, IFC, RVT).',
    choose: 'Choose a catalog file', working: 'Reading your catalog…',
    created: 'products added to your catalog', found: 'found in the document',
    none: 'We read the document and it lists no products. Nothing was added.',
    unsupported: 'We stored the file but could not read products from it.',
    failed: 'The extraction did not complete.', route: 'How it was read',
    held: 'We stored your file, but reading its products needs our reading engine, which is paused. It has not been read yet — this is not "no products". It will be read when the engine is back, or upload a CSV or Excel price list to be read now.',
  },
  ar: {
    title: 'كتالوج بالذكاء الاصطناعي', lead: 'ارفع كتالوج منتجاتك أو قائمة الأسعار أو الجدول أو المخطط. نقرأه وننشئ سجلات منتجاتك.',
    formats: 'قوائم الأسعار والجداول (CSV، Excel)، الكتالوجات (PDF، صور)، ومخططات CAD أو BIM (DWG، DXF، IFC، RVT).',
    choose: 'اختر ملف الكتالوج', working: 'جارٍ قراءة الكتالوج…',
    created: 'منتج أُضيف إلى كتالوجك', found: 'وُجد في المستند',
    none: 'قرأنا المستند ولا يحتوي على منتجات. لم يُضف شيء.',
    unsupported: 'حفظنا الملف لكن تعذّرت قراءة المنتجات منه.',
    failed: 'لم يكتمل الاستخراج.', route: 'كيف تمت القراءة',
    held: 'حفظنا ملفك، لكن قراءة منتجاته تحتاج إلى محرك القراءة لدينا، وهو متوقف مؤقتًا. لم يُقرأ الملف بعد — وهذا لا يعني «لا توجد منتجات». سيُقرأ عند عودة المحرك، أو ارفع قائمة أسعار بصيغة CSV أو Excel لتُقرأ الآن.',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

export default function SupplierCatalogUpload({ token, lang = 'en', onDone }:
  { token?: string | null; lang?: Lang; onDone?: () => void }) {
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState<Result | null>(null);
  const fileRef = useRef<HTMLInputElement | null>(null);

  async function upload(file: File) {
    setBusy(true); setRes(null);
    const data = await new Promise<string>((resolve, reject) => {
      const fr = new FileReader();
      fr.onload = () => resolve(String(fr.result || ''));
      fr.onerror = () => reject(new Error('read failed'));
      fr.readAsDataURL(file);
    }).catch(() => '');
    if (!data) { setBusy(false); setRes({ error: 'could not read that file' }); return; }
    const r: Result = await call('supplier_catalog_ingest', { file_name: file.name, data }, token)
      .catch(() => ({ error: 'upload failed' }));
    setBusy(false); setRes(r);
    if ((r?.products_created ?? 0) > 0 && onDone) onDone();
  }

  const status = res?.status;

  return (
    <section className="qd-panel p-4" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <h3 className="text-[13.5px] font-semibold text-white">{t(lang, 'title')}</h3>
      <p className="mt-1 text-[12px] leading-[1.7] text-muted-foreground">{t(lang, 'lead')}</p>
      <p className="mt-1 text-[11px] leading-[1.7] text-muted-foreground/70">{t(lang, 'formats')}</p>

      <input
        ref={fileRef} type="file" accept={ACCEPT} className="hidden"
        onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ''; }}
      />
      <button type="button" className="qd-btn mt-3" disabled={busy} onClick={() => fileRef.current?.click()}>
        {busy ? t(lang, 'working') : t(lang, 'choose')}
      </button>

      {res && (
        <motion.div initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} className="mt-3 text-[12.5px] leading-[1.7]">
          {status === 'extracted' && (
            <p className="text-white">
              <b className="tabular-nums">{res.products_created}</b> {t(lang, 'created')}
              {typeof res.products_found === 'number' && res.products_found !== res.products_created && (
                <span className="text-muted-foreground"> · {res.products_found} {t(lang, 'found')}</span>
              )}
            </p>
          )}
          {status === 'no_products_found' && <p className="text-muted-foreground">{t(lang, 'none')}</p>}
          {status === 'unread_llm_hold' && <p className="text-warn-fg/90">{t(lang, 'held')}</p>}
          {(status === 'unsupported_format' || status === 'conversion_unavailable' || status === 'conversion_failed') && (
            <p className="text-warn-fg/90">{t(lang, 'unsupported')} <span className="text-muted-foreground">{res.why}</span></p>
          )}
          {status === 'extraction_failed' && <p className="text-warn-fg/90">{t(lang, 'failed')} <span className="text-muted-foreground">{res.why}</span></p>}
          {res.error && <p className="text-warn-fg/90">{res.error}</p>}
          {res.note && (
            <p className="mt-1 text-[11px] text-muted-foreground/70">
              <span className="uppercase tracking-wide">{t(lang, 'route')}:</span> {res.note}
            </p>
          )}
        </motion.div>
      )}
    </section>
  );
}
