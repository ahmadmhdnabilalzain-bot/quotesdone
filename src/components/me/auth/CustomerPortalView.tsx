// @ts-nocheck
'use client';
/* oxlint-disable nextjs/no-html-link-for-pages -- the header's Home links are a full page load on purpose, as they were in CustomerPortal.tsx before the 9 Nov 2026 split: leaving /me drops the portal's client state and its Supabase auth listener. */
import { useEffect, useState } from 'react';
import { urlLocale, applyDocumentLocale, applyShellChrome, adoptLocale } from '@/lib/documentLocale';
import { takeAuthFragment } from '@/lib/authFragment';
import { forgetWidgetConv } from '@/lib/widgetConv';
import { Button } from '@/components/ui/button';
// The one loading system (src/components/ui/busy.tsx): 150ms before a spinner shows, 300ms minimum
// once it does, and `pending` guards the double press from ms 0. Nothing here rolls its own timing.
import { useBusy, BusyButton } from '@/components/ui/busy';
import SupportRatingPrompt from '@/components/portal/SupportRatingPrompt';
import { t } from '../portalText';
import { BrandMark } from '@/components/BrandMark';
import { SB, call } from '../api';
import { S } from '../styles';
import { Login } from './Login';
import { Authed } from './Authed';

// Before sign-in the URL decides - it is what the [locale] layout already rendered, so the page never
// flips. This read localStorage and the NEXT_LOCALE cookie only; in a fresh browser both are empty,
// so /ar/me opened English and dir=ltr (e2e journey a, 14 Sep 2026). After sign-in the registered
// language decides (onServedLocale). src/lib/documentLocale.ts.
function initLang(){ try{ if(typeof window==='undefined') return 'en'; return urlLocale(window.location.pathname); }catch(_e){} return 'en'; }

function CustomerPortalView() {
  const [lang, setLangState] = useState('en');
  const [token, setToken] = useState('');
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  // SPEC §21 asks for dark mode as an OPTION. The portal was served under html{color-scheme:dark}
  // with no light branch anywhere in globals.css, so "dark" was a decision made FOR the customer and
  // there was nothing to switch to. The light palette is a data-theme branch on .osx (globals.css);
  // this is the control that sets it, and the choice is remembered per device.
  // Read the stored choice in the initialiser (audit 21 Sep 2026, item 15: the first press of the
  // toggle did nothing visible). Nothing renders until `mounted`, so there is no server markup for
  // this value to disagree with, and the state never starts out contradicting the page.
  const [theme, setTheme] = useState(() => { try { const th = localStorage.getItem('qd-theme'); if (th === 'light' || th === 'dark') return th; } catch (_e) {} return 'dark'; });
  useEffect(() => {
    setMounted(true);
    try { const l = initLang(); if (l !== 'en') setLangState(l); } catch (_e) {}
    takeAuthFragment();   // a session in the URL is stripped and NEVER adopted (CWE-384): sign-in is by code only
    try { const tk = localStorage.getItem('qd-cust-token'); if (tk) { setToken(tk); setPhase('app'); } } catch (_e) {}
    try { SB().auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-cust-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {} setPhase('app'); } }).catch(() => {}); } catch (_e) {}
    // THE PORTAL SIGNED PEOPLE OUT EVERY HOUR WHILE HOLDING A VALID REFRESH TOKEN (13 Aug 2026).
    //
    // A Supabase access token lives 60 minutes. This client is created with autoRefreshToken:true
    // and the refresh token is stored, so supabase-js WAS quietly minting a fresh one on schedule —
    // and nothing here listened. `call()` sends the `token` state captured at mount, so at the
    // 60-minute mark every request began returning 401 and Authed showed "Your session has expired.
    // Please sign in again." to a customer whose session had not expired at all. Found by leaving
    // the portal open for an hour while clicking through it.
    //
    // One listener. TOKEN_REFRESHED carries the new access token; SIGNED_OUT carries null and must
    // NOT be mistaken for a refresh failure, so the phase is only ever moved forward here.
    let sub;
    try {
      sub = SB().auth.onAuthStateChange((_evt, ss) => {
        const at = ss && ss.access_token;
        if (!at) return;
        setToken(at);
        try { localStorage.setItem('qd-cust-token', at); if (ss.refresh_token) localStorage.setItem('qd-cust-refresh', ss.refresh_token); } catch (_e) {}
      });
    } catch (_e) {}
    return () => { try { if (sub && sub.data && sub.data.subscription) sub.data.subscription.unsubscribe(); } catch (_e) {} };
  }, []);
  // Switching language while signed in IS a change of the registered language (founder, 14 Sep 2026:
  // the registered language follows every message), so it is saved to customers.locale exactly as
  // Account settings saves it. Signed out, it only changes this page.
  const setLang = (l) => { try { localStorage.setItem('qd-lang', l); } catch (_e) {} adoptLocale(l, setLangState); if (token) call('customer_api', { action: 'set_locale', locale: l }, token).then((j) => { if (!j || !j.ok) console.error('set_locale refused - customers.locale unchanged', j); }).catch((e) => console.error('set_locale failed - customers.locale unchanged', e)); };

  // THE DOCUMENT ITSELF NEVER LEARNED IT HAD SWITCHED LANGUAGE (13 Aug 2026). Measured in the
  // browser with the portal fully in Arabic: document.documentElement.dir was "ltr" and .lang was
  // "en". Every panel sets dir="rtl" on its own <section>, which is why the SCREENSHOT looks
  // correct and hid this - but the root element is what a screen reader reads to choose a voice
  // and pronunciation rules, so an Arabic portal was being announced as English. It is also what
  // the browser uses for hyphenation, quotation marks, and the direction of anything that does not
  // carry a dir of its own. The panels keep their local dir; this sets the thing above them.
  useEffect(() => { applyDocumentLocale(lang); applyShellChrome(lang, 'me'); }, [lang]);
  // A functional update: the next theme is computed from the state React holds, never from a
  // closure a child may still be holding from an earlier render.
  const swapTheme = () => setTheme((cur) => { const next = cur === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} return next; });
  // THE STORED PROFILE LOCALE. customers.locale has existed all along and the portal could not
  // honour it: my_inquiries did not serve it (fixed 5 Aug 2026) and this component decided language
  // from localStorage['qd-lang'] and the NEXT_LOCALE cookie alone. An Arabic customer who set their
  // language once got English on every new device, and the Arabic journey exercised a code path the
  // portal could never reach.
  //
  // 14 SEP 2026 - THE REGISTERED LANGUAGE WINS once signed in. This used to let this device's
  // localStorage (or the NEXT_LOCALE cookie) override customers.locale, so an Arabic-registered
  // customer on a browser that once saw English got an English portal while every message went out
  // in Arabic. A choice made while signed in is saved to customers.locale by setLang above, so the
  // stored value is always the latest choice, and it is written back here so this device agrees.
  const onServedLocale = (l) => {
    if (l !== 'ar' && l !== 'en') return;
    try { localStorage.setItem('qd-lang', l); } catch (_e) {}
    adoptLocale(l, setLangState);
  };
  // login_otp returns the account's registered language with the session, so the first dashboard
  // paint is already in it; the dashboard's own fetch then confirms it (onServedLocale).
  const onAuth = (access, refresh, locale) => { onServedLocale(locale); try { localStorage.setItem('qd-cust-token', access || ''); if (refresh) localStorage.setItem('qd-cust-refresh', refresh); } catch (_e) {} setToken(access || ''); setPhase('app'); if (access) { try { SB().auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} } };
  // Signing out is a network call (Supabase revokes the session) and used to happen with no
  // indicator at all. The tokens are dropped FIRST so a slow or failed revoke can never leave the
  // customer signed in; the button then stays busy until the revoke settles.
  const signOutBusy = useBusy();
  const doSignOut = () => signOutBusy.run('out', async () => {
    try { localStorage.removeItem('qd-cust-token'); localStorage.removeItem('qd-cust-refresh'); } catch (_e) {}
    forgetWidgetConv();   // a pending widget chat must never be retried into the next account on this browser
    try { await SB().auth.signOut(); } catch (_e) {}
    setToken(''); setPhase('login');
  });
  const rtl = lang === 'ar';
  if (!mounted) return null;
  // THE STRIP IS FOR THE DOORWAY, NOT THE HOUSE. Signing in and completing a profile are two
  // single-card screens with no navigation to render; the marketing-style bar is right there and
  // wrong the moment the customer is actually inside, which is where PortalShell takes over.
  const strip = (<header className="sticky top-0 z-10 flex items-center justify-between gap-3 px-4 py-3 sm:px-5 bg-background/95 border-b border-border shadow-e1">
    <a className="flex min-w-0 items-center gap-2 font-head text-base font-semibold tracking-snug text-foreground no-underline" href="/"><BrandMark className="h-8 w-8 shrink-0" /><span className="truncate">QuotesDone <span className="hidden font-mono text-label uppercase tracking-caps text-primary sm:inline">{t(lang, 'brand_sub')}</span></span></a>
    <div className="flex gap-2 items-center">
      {/* h-11 — 44px, the minimum tap target; size="sm" is 32 (CP-13). */}
      <Button asChild variant="outline" size="sm" className="h-11"><a href="/">{t(lang, 'home')}</a></Button>
      <Button variant="outline" size="sm" className="h-11" onClick={() => setLang(rtl ? 'en' : 'ar')}>{rtl ? 'EN' : 'عربي'}</Button>
      <Button variant="outline" size="sm" className="h-11" onClick={swapTheme} aria-label={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')} title={theme === 'dark' ? t(lang, 'theme_light') : t(lang, 'theme_dark')}>{theme === 'dark' ? '☀' : '☾'}</Button>
      {phase === 'app' && <BusyButton busy={signOutBusy} act="out" variant="outline" size="sm" className="h-11" busyLabel={t(lang, 'signing_out')} onClick={doSignOut}>{t(lang, 'signout')}</BusyButton>}
    </div>
  </header>);
  return (<div dir={rtl ? 'rtl' : 'ltr'} data-theme={theme} className="osx min-h-screen bg-background text-foreground">
    {!mounted ? <>{strip}<div className={S.center}>{t(lang, 'loading')}</div></> : (<>
      {/* The signed-in shell carries its own <main>; the doorway screens need one too (audit 14 Sep). */}
      {/* id="main" on each of the three: the layout's skip link targets #main, and exactly one of
          them is on screen at a time (login / profile gate / the shell), so the id is never doubled. */}
      {phase === 'login' && <>{strip}<main id="main"><Login onAuth={onAuth} lang={lang} /></main></>}
      {phase === 'app' && <Authed token={token} lang={lang} strip={strip} theme={theme} onSwapTheme={swapTheme} onSetLang={setLang} onSignOut={doSignOut} onServedLocale={onServedLocale} />}
      {phase === 'app' && token ? <SupportRatingPrompt token={token} lang={lang} api="sales_engineer" /> : null}
    </>)}
  </div>);
}
export { CustomerPortalView };
