'use client';
import { useEffect, useRef, useState } from 'react';
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
// NEVER OVER A CONTROL (12 Nov 2026, customer_support; founder ruling 1645). Measured on production, first visit, iPhone 13 (390 wide,
// 664 visible): /portal?join=1 opened on Register with the bar fixed at the bottom, 157 px tall (four lines, then a full-width "Got
// it"), covering the lower half of "Create my account"; locally the same bar also covered "Open the supplier portal" on /supplier
// at 360x640, 375x667 and 390x664, and a 61 px bottom bar still covered it, and "Check my job" on the home page at 390x844. A
// bar fixed over the fold covers whatever button sits there, so:
//   - ON A PHONE (below sm) the notice is ONE ROW in the page flow at the very top, above the sticky header: it pushes the page
//     down by its own height and covers nothing. It is in the first paint: COOKIE_ASK (src/lib/cookieAsk.ts, an inline script in the layout, before any
//     content) sets html[data-qd-cookie="ask"] when no choice is stored, and globals.css shows the notice only then, so the page
//     never moves after it has loaded (CLS 0). The text is "We use cookies." with the Cookie Policy link and "Got it" (44 px).
//   - From sm up it stays the bar fixed at the bottom with the full sentence, and the page keeps its measured height free below
//     (--qd-cookie-h, body padding), so the last control always scrolls clear of it.
//   - On a phone it is in the flow WITHOUT a z-index (review, item 2: z-60 put it over every z-40/z-50 overlay near the top of the
//     page); the bottom bar from sm up keeps z-60. The Cookie Policy link is 44 px tall for a thumb (padding a negative margin takes
//     back, so the row keeps its height).
//   - For TAP_GUARD_MS after "Got it", a tap inside the band the notice covered is swallowed, so a quick second tap never lands on
//     what moves into that band (the same guard ProfileForm uses after the WhatsApp question).
// Prevented by: scripts/checks/the_cookie_notice_never_covers_the_first_button.test.mjs (a browser check, first visit).
const TAP_GUARD_MS = 400;
export function CookieConsent() {
  const t = useTranslations('cookie');
  const locale = useLocale();
  const pathname = usePathname() || '';
  // Rendered on the server and on the client alike (no storage read in render); whether it SHOWS is html[data-qd-cookie="ask"].
  const [show, setShow] = useState(true);
  const bar = useRef<HTMLDivElement>(null);
  // From sm up the bar is fixed at the bottom: the page keeps its measured height free while it shows.
  useEffect(() => {
    const root = document.documentElement;
    if (!show || !bar.current || root.getAttribute('data-qd-cookie') !== 'ask') { root.style.removeProperty('--qd-cookie-h'); return; }
    const set = () => { if (bar.current) root.style.setProperty('--qd-cookie-h', Math.ceil(bar.current.getBoundingClientRect().height) + 'px'); };
    set();
    let ro: ResizeObserver | null = null;
    try { ro = new ResizeObserver(set); ro.observe(bar.current); } catch (_e) { /* old browser: the first measure stands */ }
    return () => { if (ro) ro.disconnect(); root.style.removeProperty('--qd-cookie-h'); };
  }, [show]);
  const choose = (v: string) => {
    try {
      localStorage.setItem('qd-cookie-consent', v);
      localStorage.setItem('qd-cookie-consent-at', new Date().toISOString());
    } catch (_e) {}
    try {
      const r = bar.current?.getBoundingClientRect();
      if (r) {
        const until = Date.now() + TAP_GUARD_MS;
        const swallow = (e: Event) => {
          const p = e as PointerEvent;
          if (Date.now() > until) { off(); return; }
          if (p.clientY >= r.top && p.clientY <= r.bottom) { e.preventDefault(); e.stopPropagation(); }
        };
        const off = () => { for (const k of ['pointerdown', 'click']) document.removeEventListener(k, swallow, true); };
        for (const k of ['pointerdown', 'click']) document.addEventListener(k, swallow, true);
        setTimeout(off, TAP_GUARD_MS + 50);
      }
    } catch (_e) {}
    try { document.documentElement.removeAttribute('data-qd-cookie'); } catch (_e) {}
    setShow(false);
  };
  // Never show the public cookie banner inside the internal OS console.
  if (/(^|\/)os(\/|$)/.test(pathname)) return null;
  if (!show) return null;
  // 44 px to a finger (12 Nov 2026, customer_support; browser walk M20: "Got it" measured 358x40 at 390x844), as ui/button.tsx.
  const btn = 'inline-flex h-10 pointer-coarse:min-h-11 shrink-0 items-center justify-center whitespace-nowrap rounded-btn px-5 text-small font-semibold transition-colors duration-base';
  return (
    <div ref={bar} data-qd-cookie-notice="" dir={locale === 'ar' ? 'rtl' : 'ltr'} role="region" aria-label={t('title')}
      className="relative border-b border-line2 bg-navy-deep sm:fixed sm:inset-x-0 sm:bottom-0 sm:z-60 sm:border-b-0 sm:border-t sm:pb-[env(safe-area-inset-bottom)] sm:shadow-e3">
      <div className="container-x flex flex-row items-center gap-3 py-2 sm:gap-6 sm:py-2.5">
        <p className="min-w-0 flex-1 text-small leading-snug text-muted">
          <span className="font-semibold text-white">{t('title')}.</span>{' '}<span className="hidden sm:inline">{t('text')}{' '}</span>
          <Link href="/cookie-policy" prefetch={false} className="-my-[13px] inline-block whitespace-nowrap py-[13px] text-teal-light underline underline-offset-2 hover:text-white">{t('policy')}</Link>
        </p>
        <button type="button" onClick={() => choose('essential')} className={`${btn} bg-teal text-on-teal hover:bg-[#1ED0BC]`}>
          {t('ok')}
        </button>
      </div>
    </div>
  );
}
