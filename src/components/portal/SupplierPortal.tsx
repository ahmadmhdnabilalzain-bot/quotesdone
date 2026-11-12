// @ts-nocheck
'use client';
// THE SUPPLIER PORTAL (/portal). Split by subject on 9 Nov 2026 from one 2,084-line file, as a pure move:
// every statement kept as it was, only the imports between the new files added. This file keeps the
// session and phase (SupplierPortal) and re-exports what the old file exported. The rest is in
// ./supplier/core/: session.ts (SB, the dashboard warm-up), copy.ts (the T dictionary and t()), styles.ts
// (the class map S), helpers.tsx (labels, dates, expiry, FilePick), upload.ts, Login, ClaimRefusal,
// Agreement (re-acceptance), tabs.ts, HeaderMenus (bell and account menu), Dashboard, QuoteForm, Documents,
// Projects, Billing, Onboarding and ProfileForm. The checks that read the portal as text read all of
// these, through scripts/lib/portal_sources.mjs.
import { useEffect, useRef, useState } from 'react';
import { localisedPath, applyDocumentLocale, applyShellChrome } from '@/lib/documentLocale';
import { takeAuthFragment } from '@/lib/authFragment';
import { readFirstTouch } from '@/lib/firstTouch';
import SupplierEntryHero from './supplier/SupplierEntryHero';
import SupportRatingPrompt from './SupportRatingPrompt';
import { call } from './supplier/api';
import { drop } from '@/components/me/prefetch';
import { Button } from '@/components/ui/button';
import { BrandMark } from '@/components/BrandMark';
import { warmSupplier, SB } from './supplier/core/session';
import { warmsMe } from '@/lib/supplierRegistrationReads';
import { t } from './supplier/core/copy';
import { S } from './supplier/core/styles';
import { claimRefusalKey, ClaimRefusal } from './supplier/core/ClaimRefusal';
import { InviteBanner, Login } from './supplier/core/Login';
import { Dashboard } from './supplier/core/Dashboard';

// THE LIGHT THEME IS NOT OFFERED UNTIL IT IS FINISHED (12 Nov 2026, customer_support; founder ruling 1645, browser walk finding
// H6). Measured on production in light: tab labels 1.25:1 contrast, "Create account" 1.33:1, links 1.5:1, the sign-in e-mail box
// a dark block on white; one tap away and remembered on the device (qd-theme=light, a key the customer portal shares). Every
// supplier gets the finished dark theme: no toggle, and a stored 'light' is ignored here (the customer portal still reads it).
// The theme code stays; set THEME_CHOICE true once the light palette passes the contrast checks.
const THEME_CHOICE = false;

export function SupplierPortal() {
  // SUPPLIERS ARE ALWAYS ENGLISH (founder ruling 1008, 28 Sep 2026). The supplier portal had an EN/عربي
  // toggle and followed /ar URLs and leads.locale into Arabic. It renders English for every supplier now:
  // no toggle, no Arabic from the URL, none from the account. The customer portal keeps its own toggle.
  // Prevented by scripts/checks/the_supplier_portal_is_always_english.test.mjs.
  const lang: string = 'en';
  const [token, setToken] = useState('');
  const [phase, setPhase] = useState('login');
  const [mounted, setMounted] = useState(false);
  const [invite, setInvite] = useState(null);
  // THE INVITATION'S TOKEN HAD NOWHERE TO LAND (12 Aug 2026).
  //
  // supplier_api's `claim` action is complete and hardened - it takes body.t, looks the lead up by
  // the unguessable claim_token, refuses a company already claimed by someone else, refuses an
  // account that already manages another company, and sets claimed/claimed_by/portal_updated_at.
  // claim_lookup exists beside it for the "is this your company?" check. NEITHER HAS A SINGLE
  // CALLER: grep for 'claim' across src/components returns nothing, and this portal never read
  // location.search at all.
  //
  // So an invited supplier arriving from their invitation signed up as a stranger. Their directory
  // row - company name, emirate, categories, trades, and now a derived supplier_capabilities record
  // - stayed unclaimed while they retyped it into an empty form. On a cold B2B invite that is the
  // difference between "confirm what we already know about you" and "fill in this form", and
  // leads.claimed is also what stops us inviting the same company again.
  //
  // sessionStorage, not state: the sign-up flow is email -> OTP -> back, and the URL that carried
  // the token is not necessarily the one we return to. Cleared as soon as it is used or refused, so
  // a stale token cannot attach a later, unrelated sign-in to someone else's company.
  const CLAIM_KEY = 'qd-claim-token';
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  // THE DASHBOARD RACED THE CLAIM AND SHOWED AN INVITED SUPPLIER A BLANK FORM (21 Sep 2026, walk of
  // the campaign registration). The dashboard was warmed and mounted in the same tick the claim was
  // sent, and the claim takes ~5.8 s (measured on production, lead 126711). The dashboard answered
  // no_company, Onboarding read `me` before the claim landed, and the supplier who had just been told
  // "this listing is reserved for your company" was shown an empty "Register your company" form —
  // nothing re-read once the claim completed. Both mount paths (stored token AND getSession) also
  // sent the claim, so it went twice. Now: one claim per page, the dashboard waits for it, and the
  // warm-up it discarded is started again with the claimed company in place.
  // Prevented by scripts/checks/an_invited_supplier_can_finish_registering.test.mjs.
  const [claiming, setClaiming] = useState(false);
  // THE CLAIM COULD BE REFUSED AND NOBODY WAS TOLD (audit 22 Sep 2026, SP-C-10). The answer was
  // thrown away: a supplier whose invitation link had already been used by a colleague, or whose
  // account already manages another company, saw the "Attaching your company listing…" message,
  // then a blank registration form, and never learned that the listing had not been attached. The
  // refusal is now shown — and registration still continues underneath it, because the claim has
  // always been an improvement on the flow rather than a gate into it.
  const [claimRefusal, setClaimRefusal] = useState('');
  const claimRun = useRef(null);
  const claimIfInvited = (access) => {
    let t = '';
    try { t = sessionStorage.getItem(CLAIM_KEY) || ''; } catch (_e) {}
    if (!UUID_RE.test(t) || !access) return null;
    if (claimRun.current) return claimRun.current;
    setClaiming(true);
    claimRun.current = (async () => {
      try {
        // A failure here must never block the portal: the supplier can still register manually, which
        // is exactly what everyone has had to do until now. It is said out loud all the same.
        const j = await call('supplier_api', { action: 'claim', t, first_touch: (() => { try { return readFirstTouch(window.localStorage); } catch (_e) { return null; } })() }, access);
        if (!(j && j.ok)) setClaimRefusal(claimRefusalKey(j));
      } catch (_e) { setClaimRefusal('load_failed'); }
      try { sessionStorage.removeItem(CLAIM_KEY); } catch (_e) {}
      drop(); warmSupplier(access);   // what was warmed was asked before the company was claimed
      setClaiming(false);
    })();
    return claimRun.current;
  };
  useEffect(() => {
    setMounted(true);
    // the server-rendered "Opening the supplier portal…" line (PortalBootFallback) hides once this has mounted
    try { document.documentElement.setAttribute('data-qd-portal', 'mounted'); } catch (_e) {}
    // An /ar/portal link opens the English portal at /portal (suppliers are always English).
    try { const w = window.location, want = localisedPath(w.pathname, 'en'); if (want !== w.pathname) window.history.replaceState(window.history.state, '', want + w.search + w.hash); } catch (_e) {}
    // Capture ?t= before anything else can navigate away from it.
    //
    // AND RESOLVE IT TO A COMPANY NAME (13 Aug 2026). The invitation is addressed "Dear Al Ain Glass
    // & Mirrors Factory L.L.C." and the page it links to opened on a generic marketing hero with a
    // sign-in box headed "Welcome back" — to someone who by definition has no account. claim_lookup
    // exists for exactly this check, is public by design, takes only the unguessable token, and had
    // no caller anywhere in src/. 81 invitations sent, 0 registrations. The token is already in the
    // URL; naming the company costs one request and turns "who are you and why should I sign up"
    // into "this is your listing, claim it".
    try {
      const t = new URLSearchParams(window.location.search).get('t') || '';
      // A LINK THAT DOES NOT RESOLVE SAYS SO (24 Sep 2026, sales_engineer, ledger 993). Measured: a
      // mistyped or out-of-date ?t= opened the generic page on "Welcome back", with nothing telling the
      // supplier the invitation link was the problem. claim_lookup answers invalid_link / not_found for
      // exactly that; a network failure or a 503 stays silent, because the link may well be fine.
      if (UUID_RE.test(t)) {
        sessionStorage.setItem(CLAIM_KEY, t);
        call('claim_lookup', { t }).then((j) => {
          if (j && j.ok) setInvite(j);
          else if (j && (j.error === 'invalid_link' || j.error === 'not_found')) setInvite({ invalid: true });
        }).catch(() => {});
      } else if (t) setInvite({ invalid: true });
    } catch (_e) {}
    // A stored 'light' is not honoured while the light theme is unfinished (THEME_CHOICE below); 'dark' is the default anyway.
    try { const th = localStorage.getItem('qd-theme'); if (THEME_CHOICE && (th === 'light' || th === 'dark')) setTheme(th); } catch (_e) {}
    takeAuthFragment();   // a session in the URL is stripped and NEVER adopted (CWE-384): sign-in is by code only
    try { const tk = localStorage.getItem('qd-sup-token'); if (tk) { warmSupplier(tk); setToken(tk); setPhase('app'); claimIfInvited(tk); } } catch (_e) {}
    try { SB().auth.getSession().then(({ data }) => { const ss = data.session; if (ss && ss.access_token) { setToken(ss.access_token); try { localStorage.setItem('qd-sup-token', ss.access_token); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} warmSupplier(ss.access_token); setPhase('app'); claimIfInvited(ss.access_token); } }).catch(() => {}); } catch (_e) {}
    // THE HOUR MARK (14 Sep 2026). supabase-js refreshes the access token on schedule, and nothing here
    // listened — the customer portal learned this on 13 Aug; the supplier portal still sent the token
    // captured at mount, so after 60 minutes every tab answered "Something went wrong". One listener,
    // moving forward only: SIGNED_OUT carries no token and is not a refresh failure.
    let sub;
    try { sub = SB().auth.onAuthStateChange((_evt, ss) => { const at = ss && ss.access_token; if (!at) return; setToken(at); try { localStorage.setItem('qd-sup-token', at); if (ss.refresh_token) localStorage.setItem('qd-sup-refresh', ss.refresh_token); } catch (_e) {} }); } catch (_e) {}
    return () => { try { if (sub && sub.data && sub.data.subscription) sub.data.subscription.unsubscribe(); } catch (_e) {} };
  }, []);
  // The root element, not only this div, carries the language: it is what a screen reader reads.
  // Audit 21 Sep 2026, finding 41: the <title> and skip link are written once by the server layout,
  // so a client-side switch left an English tab title over an Arabic portal until a reload.
  useEffect(() => { applyDocumentLocale(lang); applyShellChrome(lang, 'portal'); }, [lang]);
  // Light/dark is a per-device choice, the same key and the same .osx[data-theme] palette as the
  // customer portal (globals.css). The supplier portal had no control for it at all.
  const [theme, setTheme] = useState('dark');
  // WHERE THE SIGN-IN CARD OPENS (H8): "Become a Verified Supplier" is a press by someone who has no account, so it selects
  // "Create account"; it led to "Welcome back" (Login's startMode flips to sign-up when it changes, unless he chose a tab himself).
  const [joinPressed, setJoinPressed] = useState(false);
  const toSignin = (join = false) => {
    if (join) setJoinPressed(true);
    try { document.getElementById('qd-supplier-signin')?.scrollIntoView({ behavior: 'smooth', block: 'start' }); } catch (_e) {}
    // after the tab has re-rendered for sign-up, so the address box he lands in is the sign-up one
    setTimeout(() => { try { (document.querySelector('#qd-supplier-signin input') as HTMLInputElement | null)?.focus({ preventScroll: true }); } catch (_e) {} }, 60);
  };
  const swapTheme = () => { const next = theme === 'dark' ? 'light' : 'dark'; try { localStorage.setItem('qd-theme', next); } catch (_e) {} setTheme(next); };
  // HOW MANY TIMES A 401 HAS COME BACK WITHOUT A USABLE REFRESH, AND THE ONE REFRESH IN FLIGHT.
  // Both are read by onExpired below, and declared here because onAuth resets the counter.
  const expiredRuns = useRef(0);
  const refreshing = useRef<Promise<void> | null>(null);
  // WHAT THE CODE ANSWER ALREADY SAID (11 Nov 2026, customer_support; registration certification finding 9): login_otp tells a
  // supplier signing in by e-mail whether he has a company yet (has_company). With none, and no invitation being claimed, the
  // dashboard opens "Register your company" at once instead of waiting for me / dashboard to say so. Only ever a hint: the
  // dashboard's own reads still land and correct it.
  const [noCompanyYet, setNoCompanyYet] = useState(false);
  const onAuth = (access, refresh, _locale, hasCompany = undefined) => { expiredRuns.current = 0;
    let claimPending = false; try { claimPending = UUID_RE.test(sessionStorage.getItem(CLAIM_KEY) || ''); } catch (_e) {}
    setNoCompanyYet(hasCompany === false && !claimPending); try { localStorage.setItem('qd-sup-token', access || ''); if (refresh) localStorage.setItem('qd-sup-refresh', refresh); } catch (_e) {} setToken(access || ''); if (access) warmSupplier(access, warmsMe({ hasCompany, claimPending })); setPhase('app'); if (access) { try { SB().auth.setSession({ access_token: access, refresh_token: refresh || '' }).catch(() => {}); } catch (_e) {} claimIfInvited(access); } };
  const doSignOut = () => { try { localStorage.removeItem('qd-sup-token'); localStorage.removeItem('qd-sup-refresh'); localStorage.removeItem('qd-chat-conv'); } catch (_e) {} setToken(''); setPhase('login'); try { SB().auth.signOut().catch(() => {}); } catch (_e) {} };
  // A 401: try the stored refresh token once, and only then decide whether to sign the supplier out.
  //
  // SIGNING SOMEONE OUT IS NOT A SAFE DEFAULT (review of #858, 22 Sep 2026). Until this PR only the
  // dashboard reached here. `_expired` is now set on ANY 401, so Projects, Documents, Profile,
  // Onboarding, Receipts, Billing and `me` all route into it — and supplier_api, supplier_pay and
  // kyc still call `admin.auth.getUser` raw, which returned bare 401s throughout the ~35 s GoTrue
  // outages of 18 and 21 Sep 2026. During an outage the refresh fails too, because it is the same
  // service, so the old code would have thrown a working supplier out mid-form on every one of
  // those 401s at once. The exposure grew; the remedy had to grow with it.
  //
  // So the two cases are separated, because they are genuinely different:
  //   - the refresh token is EXPLICITLY rejected (invalid_grant / "Invalid Refresh Token" / 400 or
  //     403 from the refresh itself) — that is certain. Sign out now.
  //   - anything else (network, 5xx, 429, no detail) — that is an outage, not an expiry. Leave the
  //     session alone and let the panel show its retry. Only a SECOND consecutive such 401 signs
  //     out, so a single blip costs a retry press and not the supplier's half-filled registration.
  // A successful refresh resets the counter, through `onAuth` — see the three notes below it.
  //
  // The proper fix is upstream: #854 moves supplier_pay to `signedInUser`, which answers a genuine
  // expiry and a GoTrue outage differently. supplier_api and kyc still need the same move, and when
  // all three are done the counter below can go.
  // THE COUNTER ONLY MEANS "CONSECUTIVE" IF ONE OUTAGE INSTANT INCREMENTS IT ONCE (re-review of
  // #858, 23 Sep 2026 — three defects in the mitigation above, all of which SIGNED A WORKING
  // SUPPLIER OUT, the very thing it was written to stop):
  //
  //   1. The comment above claimed onAuth resets the counter. It did not touch it, so the count was
  //      monotonic for the whole session: a blip at 09:00 left it at 1, an unrelated blip at 15:00
  //      made it 2, and the supplier was signed out mid-form. onAuth resets it now, so "consecutive"
  //      is true of the code and not only of the comment.
  //   2. ONE dead leg produces SEVERAL 401s, not one. The dashboard alone fires two reads on mount
  //      (`me` through wentExpired, and fetchDashboard's own _http === 401) and every open tab adds
  //      more; each called refreshSession separately and each added 1, so a SINGLE blip reached 2 and
  //      signed out. `refreshing` makes the refresh one shared promise, so concurrent 401s from the
  //      same instant are one attempt and one increment.
  //   3. "already used" was read as an explicit rejection. Under refresh-token rotation it is what
  //      the SECOND concurrent refresh is told while the first one SUCCEEDS — the signature of a race,
  //      not of a dead token. It signed the supplier out while a live token was being handed back.
  //      Removed; invalid_grant / Invalid Refresh Token / refresh_token_not_found still sign out at
  //      once, and with the dedupe above the race cannot happen from this component anyway.
  const onExpired = async (): Promise<void> => {
    if (refreshing.current) return refreshing.current;
    const attempt = (async () => {
      let refusedOutright = false;
      try {
        const { data, error } = await SB().auth.refreshSession();
        const ss = data && data.session;
        if (ss && ss.access_token) { onAuth(ss.access_token, ss.refresh_token); return; }
        const msg = String((error && (error.message || error.code)) || '');
        const st = Number((error && error.status) || 0);
        refusedOutright = /invalid[_ ]?(grant|refresh)|refresh[_ ]?token[_ ]?not[_ ]?found/i.test(msg) || st === 400 || st === 403;
      } catch (_e) { refusedOutright = false; }
      expiredRuns.current += 1;
      if (refusedOutright || expiredRuns.current >= 2) { expiredRuns.current = 0; doSignOut(); }
    })().finally(() => { refreshing.current = null; });
    refreshing.current = attempt;
    return attempt;
  };
  const rtl = lang === 'ar';
  if (!mounted) return null;
  return (
    // No inline font (14 Sep 2026). The root set fontFamily 'Inter, system-ui, sans-serif'; Inter is
    // not loaded anywhere (public/fonts holds 11 woff2, none Inter; document.fonts showed 0 faces on
    // /supplier), so the portal rendered in the OS fallback and the Arabic portal lost Tajawal. It now
    // inherits the layout's var(--font-body) / var(--font-head), the same faces as the homepage.
    <div dir={rtl ? 'rtl' : 'ltr'} lang={lang} data-theme={theme} className="osx min-h-screen bg-background text-foreground">
      <header className="qd-topbar sticky top-0 z-10 flex items-center justify-between gap-2 px-4 sm:px-5 py-3 bg-card/70 backdrop-blur-xl border-b border-border">
        {/* whitespace-nowrap + the sub-label hidden below sm: at 375px "QuotesDone / SUPPLIER / PORTAL"
            wrapped to three lines beside the buttons (audit mobile screenshot). */}
        {/* L6 (12 Nov 2026, browser walk): at 200 % zoom the wordmark ran under the buttons; it is the part that gives way (min-w-0
            + truncate), the buttons never shrink, and the link is 44 px tall for a thumb. */}
        <a className="group flex min-h-11 min-w-0 items-center gap-2.5 overflow-hidden whitespace-nowrap text-[15px] font-extrabold text-foreground no-underline font-head" href={rtl ? '/ar' : '/'}>
          <BrandMark className="h-7 w-7 shrink-0 transition-transform duration-500 group-hover:rotate-[8deg]" />
          <span className="truncate">QuotesDone <span className="hidden sm:inline font-mono text-[10.5px] font-semibold uppercase tracking-[0.18em] text-primary align-middle">{t(lang, 'brand_sub')}</span></span>
        </a>
        <div className="flex gap-2 items-center shrink-0">
          {THEME_CHOICE && <Button variant="outline" size="sm" onClick={swapTheme} aria-pressed={theme === 'light'} aria-label={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')} title={theme === 'dark' ? (rtl ? 'الوضع الفاتح' : 'Light mode') : (rtl ? 'الوضع الداكن' : 'Dark mode')}><span aria-hidden>{theme === 'dark' ? '☀' : '☾'}</span></Button>}
          <Button asChild variant="outline" size="sm" className="hidden sm:inline-flex"><a href={rtl ? '/ar' : '/'}>{t(lang, 'home')}</a></Button>
          {phase === 'app' && <Button variant="outline" size="sm" onClick={doSignOut}>{t(lang, 'signout')}</Button>}
        </div>
      </header>
      {/* id="main", not "qd-portal-main": the skip link the layout renders before the header points
          at #main (app/[locale]/layout.tsx), and on 18 Sep 2026 it pointed at nothing here — the id
          it had was referenced by no CSS, no script and no test, so the first focusable element on
          the supplier portal did nothing at all. */}
      <main id="main">
      {!mounted ? <div className={S.center}>{t(lang, 'loading')}</div> : (<>
        {/* An invited supplier is told whose listing this is, before anything else on the page. */}
        {phase === 'login' && invite && <InviteBanner invite={invite} lang={lang} onStart={() => toSignin(false)} />}
        {/* §1 — on a wide screen the supplier meets the product before the sign-in box. ON A PHONE THE CARD COMES FIRST (12 Nov
            2026, browser walk finding H8): the e-mail box stood at y = 1,026 of an 844 px screen, under a headline he had just read on
            /supplier. Order only, below sm: the same two blocks, the hero's call-to-action still leads to the card. */}
        {phase === 'login' && <div className="flex flex-col">
          <div className="order-2 sm:order-1"><SupplierEntryHero lang={lang} onStart={() => toSignin(true)} /></div>
          <div id="qd-supplier-signin" className="order-1 scroll-mt-20 sm:order-2"><Login onAuth={onAuth} lang={lang} startMode={joinPressed || (invite && (invite.claimable || invite.invalid)) ? 'signup' : 'signin'} /></div>
        </div>}
        {phase === 'app' && (claiming
          ? <div className={S.center} aria-busy="true" role="status">{t(lang, 'claiming_listing')}</div>
          : <>
              {claimRefusal ? <ClaimRefusal code={claimRefusal} lang={lang} onClose={() => setClaimRefusal('')} /> : null}
              <Dashboard token={token} lang={lang} onExpired={onExpired} noCompanyYet={noCompanyYet} />
              {token ? <SupportRatingPrompt token={token} lang={lang} api="supplier_api" /> : null}
            </>)}
      </>)}
      </main>
    </div>
  );
}
export { claimRefusalKey } from './supplier/core/ClaimRefusal';
export { loginErr } from './supplier/core/Login';
export { ARCHIVED_AGREEMENTS, agreementChanges, needsReaccept } from './supplier/core/Agreement';
