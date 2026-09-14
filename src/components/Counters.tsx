'use client';

// HONEST COUNTERS. Fed by public_site → fn_public_site_counters, which returns NULL for any value
// below its floor. If nothing has cleared a floor (true on 14 Sep 2026: 0 suppliers, 0 jobs,
// 0 quotes), this renders its children — the server-rendered descriptors — and never a zero.
// MeasuredMedian and TradeCount read the same single request.
import { useEffect, useState, type ReactNode } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { getCounters, fmtNum, type Counters as C } from '@/lib/publicSite';

function useCounters() {
  const [c, setC] = useState<C | null>(null);
  useEffect(() => { let on = true; getCounters().then((v) => { if (on) setC(v); }); return () => { on = false; }; }, []);
  return c;
}

export function Counters({ children }: { children: ReactNode }) {
  const t = useTranslations('counters');
  const locale = useLocale();
  const c = useCounters();
  const items = !c ? [] : [
    c.licence_verified_suppliers != null && { v: fmtNum(c.licence_verified_suppliers, locale), k: t('suppliers') },
    c.jobs_this_month != null && { v: fmtNum(c.jobs_this_month, locale), k: t('jobs') },
    c.median_hours_to_first_quote != null && { v: t('hours', { h: fmtNum(c.median_hours_to_first_quote, locale) }), k: t('median') },
    c.categories_covered != null && { v: fmtNum(c.categories_covered, locale), k: t('categories') },
  ].filter(Boolean) as { v: string; k: string }[];

  if (!items.length) return <>{children}</>;
  return (
    <div className="relative z-10 border-y border-[var(--line)] bg-navy-deep/50 backdrop-blur-sm">
      <div className="container-x grid grid-cols-2 gap-px py-5 md:grid-cols-4">
        {items.map((it) => (
          <div key={it.k} className="px-4 py-2 text-start">
            <div className="font-head text-[clamp(24px,3vw,34px)] font-semibold tracking-[-0.03em] text-white tabular">{it.v}</div>
            <div className="mt-1 text-[13px] text-muted">{it.k}</div>
          </div>
        ))}
      </div>
      <p className="container-x pb-3 font-mono text-[12px] uppercase tracking-[0.16em] text-faint rtl:tracking-normal">{t('measured')}</p>
    </div>
  );
}

/** The CTA band's measured median — rendered only when the counter endpoint has one. */
export function MeasuredMedian({ template }: { template: string }) {
  const locale = useLocale();
  const c = useCounters();
  if (!c || c.median_hours_to_first_quote == null || c.median_basis_jobs == null) return null;
  return (
    <p className="relative mt-4 text-[13.5px] text-teal-light">
      {template.replace('{h}', fmtNum(c.median_hours_to_first_quote, locale)).replace('{n}', fmtNum(c.median_basis_jobs, locale))}
    </p>
  );
}

/** A category tile's supplier count — only when the trade has at least one verified supplier. */
export function TradeCount({ trade, template }: { trade: string; template: string }) {
  const locale = useLocale();
  const c = useCounters();
  const n = c?.per_trade?.[trade];
  if (!n || n <= 0) return null;
  return <span className="mt-3 block text-[12px] text-teal-light">{template.replace('{count}', fmtNum(n, locale))}</span>;
}
