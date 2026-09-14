'use client';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useTranslations, useLocale } from 'next-intl';
import { Link } from '@/i18n/routing';

// A compact bottom bar, not a card over the hero: one line at desktop width (≤72px tall), a slim
// sheet on a phone. "Essential only" is the same size and weight as "Accept all" — declining is
// never the harder click. Storage keys and values are unchanged (qd-cookie-consent: all|essential).
export function CookieConsent() {
  const t = useTranslations('cookie');
  const locale = useLocale();
  const pathname = usePathname() || '';
  const [show, setShow] = useState(false);
  useEffect(() => {
    try { if (!localStorage.getItem('qd-cookie-consent')) setShow(true); } catch (_e) {}
  }, []);
  const choose = (v: string) => {
    try {
      localStorage.setItem('qd-cookie-consent', v);
      localStorage.setItem('qd-cookie-consent-at', new Date().toISOString());
    } catch (_e) {}
    setShow(false);
  };
  // Never show the public cookie banner inside the internal OS console.
  if (/(^|\/)os(\/|$)/.test(pathname)) return null;
  if (!show) return null;
  const btn = 'inline-flex h-10 flex-1 items-center justify-center whitespace-nowrap rounded-btn px-5 text-small font-semibold transition-colors duration-base sm:flex-none';
  return (
    <div dir={locale === 'ar' ? 'rtl' : 'ltr'} role="dialog" aria-live="polite" aria-label={t('title')}
      className="fixed inset-x-0 bottom-0 z-[60] border-t border-line2 bg-navy-deep/[.97] shadow-e3">
      <div className="container-x flex flex-col gap-3 py-3.5 sm:flex-row sm:items-center sm:gap-6 sm:py-3">
        <p className="min-w-0 flex-1 text-small leading-snug text-muted">
          <span className="font-semibold text-white">{t('title')}.</span>{' '}{t('text')}{' '}
          <Link href="/cookie-policy" className="text-teal-light underline underline-offset-2 hover:text-white">{t('policy')}</Link>
        </p>
        <div className="flex shrink-0 gap-2">
          <button type="button" onClick={() => choose('essential')} className={`${btn} border border-line3 bg-surf text-paper hover:border-teal hover:text-white`}>
            {t('decline')}
          </button>
          <button type="button" onClick={() => choose('all')} className={`${btn} bg-teal text-on-teal hover:bg-[#1ED0BC]`}>
            {t('accept')}
          </button>
        </div>
      </div>
    </div>
  );
}
