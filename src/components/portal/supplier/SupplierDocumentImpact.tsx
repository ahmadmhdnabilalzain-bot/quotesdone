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
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Doc = {
  key: string; label: string; on_file: boolean; expiry: string | null; expired: boolean;
  unlocked: number; would_unlock: number; note: string;
};
type Impact = { open_in_my_trade?: number; basis?: string; documents?: Doc[] };

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
    title: 'What your documents unlock', loading: 'Checking what each document is doing…',
    onFile: 'on file', missing: 'missing', expired: 'expired',
    // The two sentences that carry the whole feature. Both take a real count.
    usedFor: 'used for', rfqsUnlocked: 'RFQs unlocked so far',
    costing: 'Uploading it would qualify you for', moreOpportunities: 'more opportunities',
    allGood: 'Nothing is being held back by a missing document.',
    expires: 'expires', upload: 'Go to Documents',
  },
  ar: {
    title: 'ما الذي تفتحه مستنداتك', loading: 'جارٍ فحص أثر كل مستند…',
    onFile: 'مرفوع', missing: 'مفقود', expired: 'منتهٍ',
    usedFor: 'استُخدم في', rfqsUnlocked: 'طلب تم فتحه حتى الآن',
    costing: 'رفعه سيؤهلك لـ', moreOpportunities: 'فرصة إضافية',
    allGood: 'لا شيء معطّل بسبب مستند مفقود.',
    expires: 'ينتهي في', upload: 'اذهب إلى المستندات',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

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
    <section className="rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-xl p-4">
      <div className="flex justify-between items-baseline mb-3">
        <h3 className="text-xs uppercase tracking-wide opacity-60">{t(lang, 'title')}</h3>
        {goTo && (
          <button type="button" onClick={() => goTo('documents')} className="text-[10px] opacity-50 underline underline-offset-2 hover:opacity-80">
            {t(lang, 'upload')}
          </button>
        )}
      </div>

      {blocking.length === 0 && <p className="text-[11px] opacity-50 mb-2">{t(lang, 'allGood')}</p>}

      <div className="space-y-1.5">
        {docs.map((x) => (
          <div key={x.key} className="rounded-lg border border-white/10 bg-white/[0.02] px-3 py-2">
            <div className="flex justify-between items-start gap-3">
              <span className="text-[13px]">{x.label}</span>
              <span className={'shrink-0 rounded-full border px-2 py-0.5 text-[10px] '
                + (x.expired ? 'text-danger-fg border-danger/25 bg-danger/[0.06]'
                  : x.on_file ? 'text-ok-fg border-ok/25 bg-ok/[0.06]'
                  : 'text-warn-fg border-warn/25 bg-warn/[0.06]')}>
                {x.expired ? t(lang, 'expired') : x.on_file ? t(lang, 'onFile') : t(lang, 'missing')}
              </span>
            </div>

            {/* The credit: how many RFQs this document has already unlocked. */}
            {x.unlocked > 0 && (
              <div className="text-[11px] opacity-60 mt-1">
                {t(lang, 'usedFor')} <span className="tabular-nums font-medium">{x.unlocked}</span> {t(lang, 'rfqsUnlocked')}
              </div>
            )}

            {/* The cost: how many open opportunities its absence is blocking, right now. */}
            {x.would_unlock > 0 && (
              <div className="text-[11px] text-warn-fg/90 mt-1">
                {t(lang, 'costing')} <span className="tabular-nums font-semibold">{x.would_unlock}</span> {t(lang, 'moreOpportunities')}
              </div>
            )}

            <p className="text-[10px] opacity-40 mt-1 leading-snug">
              {x.note}{x.expiry ? ' · ' + t(lang, 'expires') + ' ' + x.expiry : ''}
            </p>
          </div>
        ))}
      </div>

      <p className="text-[10px] opacity-35 mt-2 leading-snug">{d.basis}</p>
    </section>
  );
}
