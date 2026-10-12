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
import { call } from './api';
import { panelErrorCode, panelErrorText } from './PanelState';

type Lang = 'en' | 'ar';
type DocRead = { status?: string; source?: string; supply_only?: boolean; trades?: { code: string }[] };
type Result = {
  ok?: boolean; catalog_id?: string | null; format?: string;
  products_created?: number; products_found?: number; note?: string;
  // `code` is what is SHOWN (translated by PanelState); `error` stays the server's own English and
  // is never printed — a supplier on /ar was reading "upload failed" and a raw Postgres message.
  status?: string; why?: string; error?: string; code?: string;
  documents_read?: { ok?: boolean; docs?: DocRead[] };
  vision?: { state?: string; message_en?: string; message_ar?: string };
};

// TEXT IN A PHOTO, READ HERE (instruction 576, 21 Sep 2026). A photographed page, label, nameplate or
// price list — and a scanned PDF's rendered pages — are read by tesseract.js in the supplier's own
// browser (src/components/me/ocrClient.ts: self-hosted, eng+ara, the same OCR the customer side uses),
// and the words go to supplier_catalog_ingest as ocr_text, into the same catalogue reader as a text
// layer. Nothing leaves the browser but the text. OCR failing is not an upload failing: the file is
// still sent, and the server says honestly that it could not read it.
async function photoText(images: { mime: string; data: string }[]): Promise<string> {
  try {
    if (!images.length) return '';
    const { ocrImages } = await import('@/components/me/ocrClient');
    return (await ocrImages(images)).text || '';
  } catch (_e) { return ''; }
}
async function imagesOf(file: File): Promise<{ mime: string; data: string }[]> {
  try {
    if (file.type === 'application/pdf') {
      const { rasterisePdf } = await import('@/components/me/pdfRaster');
      return await rasterisePdf(new Uint8Array(await file.arrayBuffer()));
    }
    if (file.type.startsWith('image/')) {
      const { toJpegPages } = await import('@/components/me/ocrClient');
      return await toJpegPages(file);
    }
  } catch (_e) { /* a page the browser cannot draw is sent without text; the server says so */ }
  return [];
}

// THE SHARED call() (./api.ts), NOT A PRIVATE COPY. This file carried one of twelve byte-identical
// copies whose whole body was `return r.json()`: no timeout, and a rejection rather than a result on
// a non-JSON answer. The endpoint name still appears as a literal beside `call(`, which is how
// supplier_catalog_ingest stays discoverable from the code that reaches it.

// Every format the ingester can route. Kept here as one list so the accept attribute and the help
// text can never disagree about what the supplier may upload.
const ACCEPT = '.csv,.tsv,.txt,.xlsx,.xls,.pdf,.png,.jpg,.jpeg,.webp,.dwg,.dxf';

const T = {
  en: {
    title: 'Product catalogue', lead: 'Upload your product catalog, price list, spreadsheet or drawing. We read it and build your product records.',
    formats: 'Price lists and spreadsheets (CSV, Excel), catalogs (PDF, images), and drawings as PDF or CAD (DWG/DXF).',
    choose: 'Choose a catalog file', working: 'Reading your catalog…',
    created: 'products added to your catalog', found: 'found in the document',
    none: 'We read the document and it lists no products. Nothing was added.',
    unsupported: 'We stored the file but could not read products from it.',
    failed: 'The extraction did not complete.', route: 'How it was read',
    held: 'We stored your file, but reading its products needs our reading engine, which is paused. It has not been read yet — this is not "no products". It will be read when the engine is back, or upload a CSV or Excel price list to be read now.',
    photo_text: 'Read from the text in your photo or scan.',
    supply_only: 'Your catalogue reads as supply only (importer, wholesaler or stockist). Confirm or correct this on the Services tab.',
  },
  ar: {
    title: 'كتالوج المنتجات', lead: 'ارفعوا كتالوج منتجاتكم أو قائمة الأسعار أو الجدول أو المخطط، ونتولى قراءته وإنشاء سجلات منتجاتكم.',
    formats: 'قوائم الأسعار والجداول (CSV وExcel)، والكتالوجات (PDF والصور)، والمخططات بصيغة PDF أو CAD ‏(DWG/DXF).',
    choose: 'اختيار ملف الكتالوج', working: 'جارٍ قراءة الكتالوج…',
    created: 'منتج أُضيف إلى كتالوجكم', found: 'وُجد في المستند',
    none: 'قرأنا المستند ولم نجد فيه منتجات، فلم يُضف أي شيء.',
    unsupported: 'حفظنا الملف لكن تعذّرت قراءة المنتجات منه.',
    failed: 'لم يكتمل الاستخراج.', route: 'طريقة القراءة',
    held: 'حفظنا ملفكم، لكن قراءة منتجاته تحتاج إلى محرك القراءة لدينا، وهو متوقف مؤقتًا. لم يُقرأ الملف بعد، وهذا لا يعني عدم وجود منتجات. سيُقرأ فور عودة المحرك، ويمكنكم بدلًا من ذلك رفع قائمة أسعار بصيغة CSV أو Excel لتُقرأ الآن.',
    photo_text: 'قُرئ من النص الموجود في صورتكم أو ملفكم الممسوح ضوئيًا.',
    supply_only: 'يُقرأ كتالوجكم على أنه توريد فقط (مستورد أو تاجر جملة أو مخزّن). يُرجى تأكيد ذلك أو تصحيحه من تبويب الخدمات.',
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
    if (!data) { setBusy(false); setRes({ code: 'bad_response' }); return; }
    // A photo's words are read before the upload; a PDF's only if the server finds no text layer in it.
    const ocr_text = file.type.startsWith('image/') ? await photoText(await imagesOf(file)) : '';
    const first = await call('supplier_catalog_ingest', { file_name: file.name, data, ...(ocr_text ? { ocr_text } : {}) }, token);
    let r: Result = first && first.ok ? first : { code: panelErrorCode(first) };
    const scanned = file.type === 'application/pdf' && r?.catalog_id != null
      && (r.documents_read?.docs || []).some((d) => d.status === 'needs_ocr');
    if (scanned) {
      const text = await photoText(await imagesOf(file));
      if (text.trim()) {
        const again: Result = await call('supplier_catalog_ingest', { catalog_id: r.catalog_id, ocr_text: text }, token).catch(() => ({}));
        if (again?.documents_read) r = { ...r, documents_read: again.documents_read };
      }
    }
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
      <button type="button" className="qd-btn mt-3 min-h-11 min-w-11" disabled={busy} onClick={() => fileRef.current?.click()}>
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
          {res.code && <p role="alert" className="text-warn-fg/90">{panelErrorText(lang, res.code)}</p>}
          {(res.documents_read?.docs || []).some((d) => d.source === 'photo_text') && (
            <p className="mt-1 text-[12px] text-muted-foreground">{t(lang, 'photo_text')}</p>
          )}
          {(res.documents_read?.docs || []).some((d) => d.supply_only) && (
            <p className="mt-1 text-[12px] text-muted-foreground">{t(lang, 'supply_only')}</p>
          )}
          {res.vision?.state === 'off' && (
            <p className="mt-1 text-[12px] text-muted-foreground" dir="auto">{lang === 'ar' ? res.vision.message_ar : res.vision.message_en}</p>
          )}
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
