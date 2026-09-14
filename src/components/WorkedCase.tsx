'use client';

// The worked case on /how-it-works. public_site worked_case → fn_public_worked_case returns null
// until a real, paid, completed, unrefunded deal exists (0 on 14 Sep 2026), and then this renders
// nothing at all — no placeholder, no sample dressed as a case.
import { useEffect, useState } from 'react';
import { useLocale, useTranslations } from 'next-intl';
import { publicSite, fmtNum } from '@/lib/publicSite';
import { QuoteBadges, type BadgeFacts } from '@/components/QuoteBadges';

type Case = {
  category: string; emirate: string | null; posted_month: string; days_to_reveal: number | null;
  quotes: (BadgeFacts & { amount: number; chosen: boolean })[] | null;
};

export function WorkedCase() {
  const t = useTranslations('howPage');
  const locale = useLocale();
  const [c, setC] = useState<Case | null>(null);
  useEffect(() => { publicSite<{ case: Case | null }>('worked_case').then((j) => setC(j && j.ok ? j.case : null)).catch(() => {}); }, []);
  if (!c || !c.quotes?.length) return null;
  return (
    <section className="container-x py-beat-s">
      {/* the quotes are the sealed documents; the case around them is ruled, not boxed */}
      <div className="relative border-t border-[var(--line2)] pt-9">
        <h2 className="font-head text-[26px] font-semibold tracking-[-0.03em] text-white">{t('caseTitle')}</h2>
        <p className="mt-2 text-[14px] text-muted">{t('caseSub')}</p>
        <p className="mt-4 text-[14px] text-paper">
          {c.category}{c.emirate ? ` · ${c.emirate}` : ''} · {t('posted', { month: c.posted_month })}
          {c.days_to_reveal != null && <> · {t('days', { d: c.days_to_reveal })}</>}
        </p>
        <ul className="mt-6 grid gap-3 md:grid-cols-3 md:items-start">
          {c.quotes.map((q, i) => (
            <li key={i} className={`qd-env p-5 pt-8 md:[&:nth-child(2)]:mt-5 md:[&:nth-child(3)]:mt-10 ${q.chosen ? 'qd-env-gold' : ''}`}>
              <div className="flex items-center gap-2">
                <span className="redact redact-sq !h-5 !w-5" aria-hidden />
                <span className="text-[13px] text-muted">{t('quote', { n: i + 1 })}</span>
                {q.chosen && <span className="ms-auto rounded-full bg-gold/90 px-2 py-px text-[12px] font-semibold text-[#2A2000]">{t('chosen')}</span>}
              </div>
              <div dir="ltr" className="mt-3 text-start font-mono text-[18px] font-semibold text-white rtl:text-end">
                {locale === 'ar' ? `${fmtNum(q.amount, locale)} درهم` : `AED ${fmtNum(q.amount, locale)}`}
              </div>
              <div className="mt-3"><QuoteBadges f={q} /></div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
