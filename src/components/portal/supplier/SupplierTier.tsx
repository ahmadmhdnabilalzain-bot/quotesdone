'use client';
// ROW #5 §20 — THE QUOTESDONE SUPPLIER RANKING. Bronze · Silver · Gold · Platinum.
//
// ── EVERY SUPPLIER ON PRODUCTION IS UNRANKED TODAY, AND THIS SAYS SO IN WORDS ───────────────────
// 0 quotes submitted, 0 won, 0 ratings across 20,465 suppliers. A tier computed from that would
// sort the entire estate into one bucket and print a badge on it, which reads as a judgement when
// it is actually an absence. So an inactive supplier sees "Unranked" with the reason — never a low
// tier — and the ladder above it with the exact requirement for each rung.
//
// A supplier should be able to predict their own tier. Thresholds nobody can see are a mood, not a
// target, so the requirements are rendered from the routine's own ladder rather than restated here.
//
// ── AND THE BENEFITS ARE LABELLED AS NOT YET ACTIVE ─────────────────────────────────────────────
// §20 wants the tier to change RFQ distribution, preferred status and visibility. Those decide
// which real companies get work, so they are the founder's call rather than an implementation
// detail. Showing a benefit that does not operate would be the most damaging kind of invention on
// this page, so `benefits_active:false` renders as an explicit "not yet".
import React, { useEffect, useState } from 'react';
import { motion } from 'motion/react';

type Lang = 'en' | 'ar';
type Rung = { tier: string; needs: string };
type Payload = {
  tier?: string; available?: boolean; basis?: string;
  ladder?: Rung[];
  progress?: { quotes_submitted?: number; quotes_won?: number; quality_rating?: number | null; response_rate?: number | null };
  benefits_active?: boolean; benefits_note?: string;
};

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
    title: 'QuotesDone Supplier Ranking', loading: 'Reading your ranking…',
    yourTier: 'Your tier', unranked: 'Unranked', ladder: 'The ladder',
    progress: 'Your progress', submitted: 'Quotes submitted', won: 'Jobs won',
    quality: 'Quality rating', response: 'Response rate', notRated: 'not rated yet',
    benefits: 'What a tier confers', notYet: 'Not active yet',
  },
  ar: {
    title: 'تصنيف موردي QuotesDone', loading: 'جارٍ قراءة تصنيفك…',
    yourTier: 'تصنيفك', unranked: 'غير مصنّف', ladder: 'السلّم',
    progress: 'تقدّمك', submitted: 'عروض مقدَّمة', won: 'أعمال فائزة',
    quality: 'تقييم الجودة', response: 'معدل الاستجابة', notRated: 'لم يُقيَّم بعد',
    benefits: 'ما يمنحه التصنيف', notYet: 'غير مفعّل بعد',
  },
};
const t = (lang: Lang, k: keyof typeof T.en): string => (T[lang] || T.en)[k] || T.en[k] || String(k);

// The metals, in order, so the ladder always renders as a ladder even if the payload reorders.
const ORDER = ['bronze', 'silver', 'gold', 'platinum'];
const STYLE: Record<string, string> = {
  bronze: 'text-amber-600', silver: 'text-slate-300', gold: 'text-yellow-400', platinum: 'text-cyan-200',
};

export default function SupplierTier({ token, lang = 'en' }: { token?: string | null; lang?: Lang }) {
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'tier' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setD(j); else setErr((j && (j.error || j.hint)) || 'load_err');
    }).catch(() => { if (live) setErr('load_err'); });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="p-4 text-xs opacity-60">{err}</div>;
  if (!d) return <div className="p-4 text-xs opacity-60">{t(lang, 'loading')}</div>;

  const ranked = d.available === true;
  const tier = String(d.tier || 'unranked');
  const ladder = [...(d.ladder || [])].sort((a, b) => ORDER.indexOf(a.tier) - ORDER.indexOf(b.tier));
  const p = d.progress || {};

  return (
    <div className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <h2 className="text-[15px] font-semibold text-white">{t(lang, 'title')}</h2>

      <section className="qd-panel p-4">
        <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'yourTier')}</div>
        <motion.div
          initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25 }}
          className={'mt-0.5 text-2xl font-semibold capitalize ' + (ranked ? (STYLE[tier] || 'text-white') : 'text-muted-foreground')}
        >
          {ranked ? tier : t(lang, 'unranked')}
        </motion.div>
        {/* The reason, always. "Unranked" without it reads as a bad score. */}
        <p className="mt-1.5 text-xs leading-[1.7] text-muted-foreground">{d.basis}</p>
      </section>

      <section className="qd-panel p-4">
        <h3 className="mb-2 text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'ladder')}</h3>
        <ol className="flex flex-col gap-1.5">
          {ladder.map((r) => (
            <li key={r.tier} className="flex items-baseline gap-2 text-[12.5px]">
              <span className={'w-[4.5rem] shrink-0 font-medium capitalize ' + (STYLE[r.tier] || 'text-white')}>{r.tier}</span>
              <span className={r.tier === tier ? 'text-white' : 'text-muted-foreground'}>{r.needs}</span>
              {r.tier === tier && <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-emerald-400" />}
            </li>
          ))}
        </ol>
      </section>

      <section className="qd-panel p-4">
        <h3 className="mb-2 text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'progress')}</h3>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-[12.5px] sm:grid-cols-4">
          {([
            [t(lang, 'submitted'), p.quotes_submitted ?? 0, false],
            [t(lang, 'won'), p.quotes_won ?? 0, false],
            // NULL is not zero: a rating nobody has earned renders as words, and draws no number.
            [t(lang, 'quality'), p.quality_rating, true],
            [t(lang, 'response'), p.response_rate, true],
          ] as [string, number | null | undefined, boolean][]).map(([label, v, nullable]) => (
            <div key={label} className="flex flex-col gap-0.5">
              <dt className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</dt>
              <dd className={v == null && nullable ? 'text-[12px] italic text-muted-foreground/60' : 'tabular-nums text-white'}>
                {v == null && nullable ? t(lang, 'notRated') : String(v ?? 0)}
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="qd-panel p-4">
        <h3 className="mb-1 text-[10px] uppercase tracking-wide text-muted-foreground">{t(lang, 'benefits')}</h3>
        <p className="text-xs leading-[1.7] text-muted-foreground">
          {!d.benefits_active && <b className="text-white/80">{t(lang, 'notYet')} · </b>}
          {d.benefits_note}
        </p>
      </section>
    </div>
  );
}
