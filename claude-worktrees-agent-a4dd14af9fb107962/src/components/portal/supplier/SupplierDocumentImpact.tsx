'use client';
// ROW #5 §16 §4 — WHAT EACH DOCUMENT IS EARNING, AND WHAT THE MISSING ONE IS COSTING.
//
// ── THE ONE QUESTION THE DOCUMENTS SCREEN COULD NOT ANSWER ──────────────────────────────────────
// The portal already listed which documents are on file and when they expire. §16's claim is that
// documents are ALIVE, and a list of filenames with dates beside them is exactly the stored-file
// view it says it is replacing. What makes a document alive is knowing what it does: this licence
// has unlocked N enquiries, and that missing one is costing you M open ones right now.
//
// Both numbers come from fn_supplier_document_impact. Neither is computed here, and neither is
// softened here: when the routine attributes zero, this renders zero. A screen that rounded a
// disappointing count up to "several" would be the same defect as an invented market price.
//
// ── WHY THE COST IS SHOWN LOUDER THAN THE CREDIT ────────────────────────────────────────────────
// A supplier who has already uploaded their licence does not need to be congratulated for it. The
// one with an expired licence needs to know, in the strongest terms the screen has, that every open
// enquiry in their trade is currently out of reach. So `would_unlock` gets the accent colour and
// the count; `unlocked` is stated plainly beside it.
import React, { useEffect, useState } from 'react';
import { SUPA_ANON, fnUrl } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Doc = {
  key: string; label: string; on_file: boolean; expiry: string | null; expired: boolean;
  unlocked: number; would_unlock: number; note: string;
};
type Impact = { open_in_my_trade?: number; basis?: string; documents?: Doc[] };

const ANON = SUPA_ANON;

async function call(path: string, body: unknown, token?: string | null) {
  const r = await fetch(fnUrl(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + (token || ANON) },
    body: JSON.stringify(body),
  });
  return r.json();
}

const T = {
  en: {
    title: 'What your documents unlock', loading: 'Checking what each document is doing…',
    onFile: 'on file', missing: 'missing', expired: 'expired',
    // The two sentences that carry the whole feature. Both take a real count.
    usedFor: 'used for', rfqsUnlocked: 'RFQs unlocked so far',
    costing: 'Uploading it would qualify you for', moreOpportunities: 'more opportunities',
    allGood: 'Nothing is being held back by a missing document.',
    expires: 'expires', upload: 'Go to Documents',
  },
  ar: {
    title: 'ما تتيحه لكم مستنداتكم', loading: 'جارٍ فحص أثر كل مستند…',
    onFile: 'مرفوع', missing: 'مفقود', expired: 'منتهٍ',
    usedFor: 'أتاح لكم', rfqsUnlocked: 'من الطلبات حتى الآن',
    costing: 'برفعه تُتاح لكم', moreOpportunities: 'من الفرص الإضافية',
    allGood: 'لا شيء معطّل بسبب مستند مفقود.',
    expires: 'ينتهي في', upload: 'الانتقال إلى المستندات',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// ARABIC, 15 Sep 2026. fn_supplier_document_impact returns each document's label, note and the footer
// `basis` as English sentences, and this panel printed them as they came, so /ar showed "Trade licence",
// "On file and in force.", "Missing. ..." and the stray footer "open enquiries in your trade, and the
// enquiries you have already priced". The words are now chosen here from the facts the routine returns
// (key, on_file, expired; only the trade licence gates matching — the routine's own gates_matching rule),
// in both languages. The routine's English stays the fallback for a key this map does not know.
const DOC_LABEL: Record<string, [string, string]> = {
  trade_licence: ['Trade licence', 'الرخصة التجارية'], company_profile: ['Company profile', 'الملف التعريفي للشركة'],
  iso: ['ISO certification', 'شهادة ISO'], insurance: ['Insurance', 'التأمين'], manufacturer_auth: ['Manufacturer authorisation', 'تفويض الشركة المصنّعة'],
};
const NOTE: Record<string, [string, string]> = {
  in_force: ['On file and in force.', 'مرفوع وساري المفعول.'],
  expired_gate: ['Expired. Renewing it reopens every open enquiry in your trade.', 'منتهي الصلاحية، وبتجديده تُتاح لكم مجددًا جميع الاستفسارات المفتوحة في مجالكم.'],
  expired: ['Expired. Customers see this as a gap when comparing you.', 'منتهي الصلاحية، ويعدّه العملاء نقصًا عند مقارنتكم بغيركم.'],
  missing_gate: ['Missing. It is the document that decides whether you can be matched at all.', 'مفقود، وهو المستند الذي يحدّد إمكانية مطابقتكم من الأساس.'],
  missing: ['Missing. It is optional, but it is what a customer looks for when comparing two similar quotes.', 'مفقود. هذا المستند اختياري، لكنه ما يبحث عنه العميل عند المفاضلة بين عرضين متقاربين.'],
};
const BASIS: [string, string] = ['Counted from open enquiries in your trade, and the enquiries you have already priced.', 'محسوب من الاستفسارات المفتوحة في مجالكم، ومن الاستفسارات التي سبق أن قدّمتم عليها عروض أسعار.'];
const pick = (lang: Lang, p: [string, string]) => p[lang === 'ar' ? 1 : 0];
export const docLabel = (lang: Lang, x: Doc) => (DOC_LABEL[x.key] ? pick(lang, DOC_LABEL[x.key]) : x.label);
export const docNote = (lang: Lang, x: Doc) => {
  const gate = x.key === 'trade_licence';
  const k = x.on_file && !x.expired ? 'in_force' : x.expired ? (gate ? 'expired_gate' : 'expired') : (gate ? 'missing_gate' : 'missing');
  return pick(lang, NOTE[k]);
};
const fmt = (lang: Lang, d: string) => new Date(d).toLocaleDateString(lang === 'ar' ? 'ar-AE' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

// `initial` is the document_impact payload the dashboard call already carries (15 Sep 2026).
export default function SupplierDocumentImpact({ token, lang = 'en', goTo, initial = null }:
  { token?: string | null; lang?: Lang; goTo?: (tab: string) => void; initial?: Impact | null }) {
  const [d, setD] = useState<Impact | null>(initial);
  const [err, setErr] = useState('');

  useEffect(() => { if (initial) setD(initial); }, [initial]);
  useEffect(() => {
    if (initial) return;
    let live = true;
    call('supplier_portal', { action: 'document_impact' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setD(j); else setErr((j && (j.error || j.hint)) || 'load_err');
    });
    return () => { live = false; };
  }, [token, initial]);

  if (err) return <div className="text-xs opacity-60 p-4">{err}</div>;
  if (!d) return <div className="text-xs opacity-60 p-4">{t(lang, 'loading')}</div>;

  const docs = d.documents || [];
  const blocking = docs.filter((x) => x.would_unlock > 0);

  return (
    <section aria-labelledby="qd-doc-impact-h" className="qd-panel p-4">
      <div className="flex justify-between items-center mb-3">
        <h3 id="qd-doc-impact-h" className="text-[13px] font-bold text-foreground">{t(lang, 'title')}</h3>
      </div>

      {blocking.length === 0 && <p className="text-[12px] text-muted-foreground mb-2">{t(lang, 'allGood')}</p>}

      <div className="space-y-1.5">
        {docs.map((x) => (
          <div key={x.key} className="rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2">
            <div className="flex justify-between items-start gap-3">
              <span className="text-[13px]">{docLabel(lang, x)}</span>
              <span className={'shrink-0 rounded-full border px-2 py-0.5 text-[10px] '
                + (x.expired ? 'text-danger-fg border-danger/25 bg-danger/[0.06]'
                  : x.on_file ? 'text-ok-fg border-ok/25 bg-ok/[0.06]'
                  : 'text-warn-fg border-warn/25 bg-warn/[0.06]')}>
                {x.expired ? t(lang, 'expired') : x.on_file ? t(lang, 'onFile') : t(lang, 'missing')}
              </span>
            </div>

            {/* The credit: how many RFQs this document has already unlocked. */}
            {x.unlocked > 0 && (
              <div className="text-[12px] text-muted-foreground mt-1">
                {t(lang, 'usedFor')} <bdi dir="ltr" className="tabular-nums font-medium">{x.unlocked}</bdi> {t(lang, 'rfqsUnlocked')}
              </div>
            )}

            {/* The cost: how many open opportunities its absence is blocking, right now. */}
            {x.would_unlock > 0 && (
              <div className="text-[12px] text-warn-fg mt-1">
                {t(lang, 'costing')} <bdi dir="ltr" className="tabular-nums font-semibold">{x.would_unlock}</bdi> {t(lang, 'moreOpportunities')}
              </div>
            )}

            <p className="text-[12px] text-muted-foreground mt-1 leading-snug">
              {docNote(lang, x)}{x.expiry ? <> · {t(lang, 'expires')} <bdi>{fmt(lang, x.expiry)}</bdi></> : null}
            </p>
          </div>
        ))}
      </div>

      <p className="text-[11.5px] text-muted-foreground mt-2 leading-snug">{pick(lang, BASIS)}</p>
    </section>
  );
}
