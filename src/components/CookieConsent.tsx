'use client';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useTranslations, useLocale } from 'next-intl';
import { Link } from '@/i18n/routing';

// A compact bottom bar, not a card over the hero: one line at desktop width (≤72px tall), a slim
// sheet on a phone.
//
// ONE BUTTON, BECAUSE THERE IS NOTHING TO CHOOSE (WEB-14, 22 Sep 2026). The bar offered "Accept all"
// and "Essential only" over a sentence promising "optional analytics cookies" — and the platform sets
// no analytics cookie at all: measured on production, the only keys written are the session, the
// consent record itself and the portal tokens. Asking for consent to something that does not exist is
// a false statement to the visitor and, under the PDPL, consent obtained for nothing. The notice now
// says essential cookies only and is acknowledged; the cookie policy §2–§5 says the same. The stored
// value stays 'essential' (qd-cookie-consent), so an older 'all' from before today is still read.
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
      <div className="container-x flex flex-col gap-3 py-3.5 sm:flex-row sm:items-center sm:gap-6 sm:py-2.5">
        <p className="min-w-0 flex-1 text-small leading-snug text-muted">
          <span className="font-semibold text-white">{t('title')}.</span>{' '}{t('text')}{' '}
          <Link href="/cookie-policy" prefetch={false} className="text-teal-light underline underline-offset-2 hover:text-white">{t('policy')}</Link>
        </p>
        <div className="flex shrink-0 gap-2">
          <button type="button" onClick={() => choose('essential')} className={`${btn} bg-teal text-on-teal hover:bg-[#1ED0BC]`}>
            {t('ok')}
          </button>
        </div>
      </div>
    </div>
  );
}
