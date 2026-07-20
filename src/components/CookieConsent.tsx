'use client';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { useTranslations, useLocale } from 'next-intl';

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
  const rtl = locale === 'ar';
  return (
    <div dir={rtl ? 'rtl' : 'ltr'} role="dialog" aria-live="polite" aria-label={t('title')}
      style={{ position: 'fixed', left: 12, right: 12, bottom: 12, zIndex: 60, margin: '0 auto', maxWidth: 720,
        background: 'rgba(6,18,27,.965)', border: '1px solid rgba(110,231,212,.19)', borderRadius: 18,
        boxShadow: '0 24px 60px -28px rgba(3,12,18,.9), inset 0 1px 0 rgba(110,231,212,.10)', padding: '18px 20px', color: '#EAF4F2',
        fontFamily: rtl ? 'var(--font-ar), system-ui, sans-serif' : 'var(--font-body), system-ui, sans-serif' }}>
      <div style={{ fontFamily: 'var(--font-head), system-ui, sans-serif', fontWeight: 600, fontSize: 15.5, letterSpacing: '-.015em', marginBottom: 7 }}>{t('title')}</div>
      <div style={{ fontSize: 13, color: '#9DB2B2', lineHeight: 1.6 }}>
        {t('text')} <a href="/cookie-policy" style={{ color: '#6EE7D4', textDecoration: 'underline' }}>{t('policy')}</a>
      </div>
      <div style={{ display: 'flex', gap: 10, marginTop: 14, flexWrap: 'wrap' }}>
        <button onClick={() => choose('all')}
          style={{ background: '#14B8A6', color: '#04231F', border: 0, borderRadius: 999, padding: '10px 20px', fontWeight: 700, fontSize: 14, cursor: 'pointer', boxShadow: '0 10px 26px -14px rgba(20,184,166,.7)' }}>
          {t('accept')}
        </button>
        <button onClick={() => choose('essential')}
          style={{ background: 'rgba(110,231,212,.03)', color: '#EAF4F2', border: '1px solid rgba(110,231,212,.19)', borderRadius: 999, padding: '10px 20px', fontWeight: 600, fontSize: 14, cursor: 'pointer' }}>
          {t('decline')}
        </button>
      </div>
    </div>
  );
}
