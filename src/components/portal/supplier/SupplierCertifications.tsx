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
import React, { useCallback, useEffect, useState } from 'react';
import { motion } from 'motion/react';
import { call } from './api';
import { PanelError, PanelLoading, panelErrorCode } from './PanelState';
import { arDays } from '@/lib/durationLabel';

type Lang = 'en' | 'ar';
type Cert = {
  key: string; label: string; label_ar?: string | null; held: boolean; expiry?: string | null; days_left?: number | null;
  document_status: 'valid' | 'expiring' | 'expired' | 'missing';
  impact_level: 'critical' | 'high' | 'medium' | 'low'; impact_why?: string; impact_why_ar?: string | null;
};
type Payload = {
  certifications?: Cert[]; impact_basis?: string; impact_basis_ar?: string | null;
  summary?: { held?: number; total?: number; expired?: number; expiring?: number; blocking_missing?: number };
};

const T = {
  en: {
    title: 'Certifications', loading: 'Checking your certificates…',
    held: 'held', blocking: 'blocking your approval', expiresIn: 'expires in', days: 'days', daysAgo: 'days ago',
    impact: 'Impact', upload: 'Upload in Documents',
    status: { valid: 'Valid', expiring: 'Expiring', expired: 'Expired', missing: 'Not uploaded' },
  },
  ar: {
    title: 'الشهادات', loading: 'جارٍ فحص شهاداتكم…',
    held: 'محفوظة', blocking: 'يمنع اعتمادكم', expiresIn: 'تنتهي خلال', days: 'يومًا', daysAgo: 'يومًا مضت',
    impact: 'الأثر', upload: 'رفعها من تبويب المستندات',
    status: { valid: 'سارية', expiring: 'قاربت الانتهاء', expired: 'منتهية', missing: 'غير مرفوعة' },
  },
};
const t = (lang: Lang) => T[lang] || T.en;

// The Documents tab has no slot for a tax certificate or bank details (the TRN is read off the
// licence; money moves through Stripe), and bank details were removed estate-wide. A server that
// has not yet been redeployed can still send those two rows, and "Upload in Documents" beside a
// row the Documents tab cannot take is a dead end — so those two keys are dropped here too.
const RETIRED_SUBJECTS = new Set(['vat', 'bank_iban']);

const IMPACT_LABEL: Record<Lang, Record<Cert['impact_level'], string>> = {
  en: { critical: 'Critical', high: 'High', medium: 'Medium', low: 'Low' },
  ar: { critical: 'حرج', high: 'مرتفع', medium: 'متوسط', low: 'منخفض' },
};

const DOT: Record<Cert['document_status'], string> = {
  valid: 'bg-ok', expiring: 'bg-warn', expired: 'bg-danger', missing: 'bg-white/25',
};
const IMPACT_STYLE: Record<Cert['impact_level'], string> = {
  critical: 'text-danger-fg', high: 'text-warn-fg', medium: 'text-white/70', low: 'text-muted-foreground',
};

export default function SupplierCertifications({ token, lang = 'en', goTo }:
  { token?: string | null; lang?: Lang; goTo?: (tab: string) => void }) {
  const L = t(lang);
  const [d, setD] = useState<Payload | null>(null);
  const [err, setErr] = useState('');

  const load = useCallback(async () => {
    setErr('');
    const j = await call('supplier_portal', { action: 'certifications' }, token);
    if (j && j.ok) setD(j); else setErr(panelErrorCode(j));
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  if (err) return <PanelError lang={lang} code={err} onRetry={() => { void load(); }} />;
  if (!d) return <PanelLoading lang={lang} text={L.loading} />;

  const certs = (d.certifications || []).filter((c) => !RETIRED_SUBJECTS.has(c.key));
  const ar = lang === 'ar';
  const s = d.summary || {};

  return (
    <div className="flex flex-col gap-3" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-[15px] font-semibold text-white">{L.title}</h2>
        <p className="text-[11px] text-muted-foreground">
          {/* Counted from the rows on screen, so the fraction always matches the list beneath it. */}
          <span className="tabular-nums">{certs.filter((c) => c.held).length}/{certs.length}</span> {L.held}
          {!!s.blocking_missing && <span className="text-danger-fg"> · {s.blocking_missing} {L.blocking}</span>}
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
                <p className="text-[13px] font-medium text-white">{(ar && c.label_ar) || c.label}</p>
                <p className="mt-0.5 text-[11.5px] text-muted-foreground">
                  {L.status[c.document_status]}
                  {c.expiry && c.days_left != null && (
                    <> · {c.days_left >= 0
                      ? (ar ? (c.days_left === 0 ? 'تنتهي اليوم' : `${L.expiresIn} ${arDays(c.days_left)}`) : `${L.expiresIn} ${c.days_left} ${L.days}`)
                      : (ar ? `منذ ${arDays(Math.abs(c.days_left))}` : `${Math.abs(c.days_left)} ${L.daysAgo}`)}</>
                  )}
                </p>
                <p className="mt-1 text-[11px] leading-[1.6] text-muted-foreground/75">{(ar && c.impact_why_ar) || c.impact_why}</p>
              </div>
            </div>
            <div className="shrink-0 text-end">
              <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{L.impact}</div>
              <div className={'text-[12px] font-medium ' + IMPACT_STYLE[c.impact_level]}>{IMPACT_LABEL[ar ? 'ar' : 'en'][c.impact_level] || c.impact_level}</div>
              {!c.held && goTo && (
                <button type="button" className="qd-link mt-1 inline-flex min-h-11 min-w-11 items-center justify-end text-[11px]" onClick={() => goTo('documents')}>
                  {L.upload}
                </button>
              )}
            </div>
          </motion.li>
        ))}
      </ul>

      {/* The provenance of the impact column, stated rather than implied. */}
      <p className="text-[11px] leading-[1.6] text-muted-foreground/60">{(ar && d.impact_basis_ar) || d.impact_basis}</p>
    </div>
  );
}
