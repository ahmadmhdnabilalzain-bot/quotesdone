'use client';
// ROW #5 §16 §24 — CERTIFICATIONS. Every certificate, its validity status, and what it costs you.
//
// The documents tab lists files. This answers the question a supplier actually has: which missing
// piece of paper is stopping me winning work, and which is merely untidy?
//
// ── document_status IS A FIELD, AND `missing` IS ONE OF ITS VALUES ──────────────────────────────
// valid · expiring · expired · missing. A certificate the supplier does not hold is shown in the
// list rather than omitted from it — an absence you cannot see is an absence you cannot fix, and a
// list of only the documents someone already uploaded is a congratulations letter.
//
// ── IMPACT IS LABELLED AS A POLICY, NOT A MEASUREMENT ───────────────────────────────────────────
// "Critical" for the trade licence is a fact about the licence gate in save_profile: approval
// literally cannot happen without it. It is not a score derived from this supplier's history, and
// the panel says so, because a stated rule dressed as an observation is the failure this row keeps
// guarding against.
import React, { useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { SUPA_FN, SUPA_ANON } from '@/lib/supaEnv';

type Lang = 'en' | 'ar';
type Cert = {
  key: string; label: string; held: boolean; expiry?: string | null; days_left?: number | null;
  document_status: 'valid' | 'expiring' | 'expired' | 'missing';
  impact_level: 'critical' | 'high' | 'medium' | 'low'; impact_why?: string;
};
type Payload = {
  certifications?: Cert[]; impact_basis?: string;
  summary?: { held?: number; total?: number; expired?: number; expiring?: number; blocking_missing?: number };
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
    title: 'Certifications', loading: 'Checking your certificates…',
    held: 'held', blocking: 'blocking your approval', expiresIn: 'expires in', daysAgo: 'days ago',
    impact: 'Impact', upload: 'Upload in Documents',
    status: { valid: 'Valid', expiring: 'Expiring', expired: 'Expired', missing: 'Not uploaded' },
  },
  ar: {
    title: 'الشهادات', loading: 'جارٍ فحص شهاداتك…',
    held: 'محفوظة', blocking: 'يمنع اعتمادك', expiresIn: 'تنتهي خلال', daysAgo: 'يومًا مضت',
    impact: 'الأثر', upload: 'ارفعها من المستندات',
    status: { valid: 'سارية', expiring: 'قاربت الانتهاء', expired: 'منتهية', missing: 'غير مرفوعة' },
  },
};
const t = (lang: Lang) => T[lang] || T.en;

const DOT: Record<Cert['document_status'], string> = {
  valid: 'bg-emerald-400', expiring: 'bg-amber-300', expired: 'bg-red-400', missing: 'bg-white/25',
};
const IMPACT_STYLE: Record<Cert['impact_level'], string> = {
  critical: 'text-red-300', high: 'text-amber-300', medium: 'text-white/70', low: 'text-muted-foreground',
};

export default function SupplierCertifications({ token, lang = 'en', goTo }:
  { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const L = t(lang);
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    let live = true;
    call('supplier_portal', { action: 'certifications' }, token).then((j) => {
      if (!live) return;
      if (j && j.ok) setD(j); else setErr((j && (j.error || j.hint)) || 'load_err');
    }).catch(() => { if (live) setErr('load_err'); });
    return () => { live = false; };
  }, [token]);

  if (err) return <div className="p-4 text-xs opacity-60">{err}</div>;
  if (!d) return <div className="p-4 text-xs opacity-60">{L.loading}</div>;

  const certs = d.certifications || [];
  const s = d.summary || {};

  return (
    <div className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-[15px] font-semibold text-white">{L.title}</h2>
        <p className="text-[11px] text-muted-foreground">
          <span className="tabular-nums">{s.held ?? 0}/{s.total ?? 0}</span> {L.held}
          {!!s.blocking_missing && <span className="text-red-300"> · {s.blocking_missing} {L.blocking}</span>}
        </p>
      </header>

      <ul className="flex flex-col gap-2">
        {certs.map((c, i) => (
          <motion.li
            key={c.key}
            initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.2, delay: Math.min(i * 0.03, 0.15) }}
            className="qd-panel flex flex-wrap items-start justify-between gap-3 p-3.5"
          >
            <div className="flex min-w-0 items-start gap-2.5">
              <span aria-hidden className={'mt-[7px] h-2 w-2 shrink-0 rounded-full ' + DOT[c.document_status]} />
              <div className="min-w-0">
                <p className="text-[13px] font-medium text-white">{c.label}</p>
                <p className="mt-0.5 text-[11.5px] text-muted-foreground">
                  {L.status[c.document_status]}
                  {c.expiry && c.days_left != null && (
                    <> · {c.days_left >= 0
                      ? `${L.expiresIn} ${c.days_left}d`
                      : `${Math.abs(c.days_left)} ${L.daysAgo}`}</>
                  )}
                </p>
                <p className="mt-1 text-[11px] leading-[1.6] text-muted-foreground/75">{c.impact_why}</p>
              </div>
            </div>
            <div className="shrink-0 text-end">
              <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{L.impact}</div>
              <div className={'text-[12px] font-medium capitalize ' + IMPACT_STYLE[c.impact_level]}>{c.impact_level}</div>
              {!c.held && goTo && (
                <button type="button" className="qd-link mt-1 text-[11px]" onClick={() => goTo('documents')}>
                  {L.upload}
                </button>
              )}
            </div>
          </motion.li>
        ))}
      </ul>

      {/* The provenance of the impact column, stated rather than implied. */}
      <p className="text-[11px] leading-[1.6] text-muted-foreground/60">{d.impact_basis}</p>
    </div>
  );
}
