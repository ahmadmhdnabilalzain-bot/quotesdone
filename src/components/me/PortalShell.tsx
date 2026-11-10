// @ts-nocheck
'use client';
// THE PORTAL SHELL — an application frame, not a page with a menu.
//
// WHAT THIS REPLACES AND WHY. The founder registered as a customer on 13 Aug 2026, opened /en/me,
// and said: "so many tabs that are irrelevant to customers ... the visuals, extremely basic, felt
// so static and super outdated." Rendered at 1280 and 375 (which the previous session did not do),
// the screen was a stack of identical full-width cards under TEN identical grey pill buttons —
// Projects, Approvals, Messages, Documents, Orders, What you may need next, Project room, Account,
// Company profile, Home — in server-ranked order, with no icons, no grouping, no active state, and
// "Home" last. Every module behind those pills is real and most of them are good. The pills were
// the product's navigation and they read as a debug toolbar.
//
// The two structural lessons from the reference designs he supplied, which matter more than the
// palette: a customer belongs INSIDE an application with a persistent sidebar, and the assistant is
// a PRIMARY SURFACE — the widest element on the page — not a bubble in the corner.
//
// THREE THINGS THIS FILE MUST NOT BREAK, all of them earned:
//   1. RTL. Every inline direction here is LOGICAL (ms/me/ps/pe/start/end/border-e). No ml-, no
//      left-, no fixed left/right. Arabic is half the market.
//   2. Bidi isolation. Assistant replies carry +971 numbers, emails and paths; they render through
//      ChatWidget's `render`, which wraps each in <bdi>. Imported, never re-implemented.
//   3. Keyboard and screen-reader access. Every destination is a real <button>; the open one
//      carries aria-current; the mobile overflow carries aria-expanded. The 5 Aug a11y fix in
//      CustomerPortal exists because this exact class of control was once a bare <div onClick>.
import { useEffect, useRef, useState } from 'react';
import { Sparkles, Bell, Menu, X, Sun, Moon, LogOut, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { BrandMark } from '@/components/BrandMark';
import { NAV_GROUPS, MOBILE_PRIMARY } from './shell/navGroups';
import { AssistantPanel } from './shell/AssistantPanel';
import { afterEscape, afterMoreToggle, afterNavigate } from '@/lib/portalPanels';
export { NAV_GROUPS } from './shell/navGroups';
export { AssistantPanel } from './shell/AssistantPanel';
export { StatTile, RFQ_STATE, rfqState, StatusPill } from './shell/StatusParts';

// ── THE SHELL ──────────────────────────────────────────────────────────────────────────────────
// §21's per-customer panel ranking, kept and moved. customer_portal returns layout.order ranked by
// what this customer actually has outstanding, and it used to reorder a flat bar of ten pills. It
// now reorders items WITHIN their group, so the ranking still surfaces what is waiting on them
// without shuffling "Account" into the middle of their work.
//
// CSS `order`, not array order — the same reason the original bar used it: `order` moves the
// painted position and leaves the DOM alone, so a server-side ranking can never reorder a keyboard
// user's tab sequence. Unranked items sort last because indexOf returns -1.
// THE SPINE IS NOT A PANEL. Overview and My requests are the two destinations the portal is FOR;
// the server's ranking is over the §22 module panels and does not mention them, so they scored 99
// and the first render put "Documents, Orders, Overview, My requests" in the Work group — the
// dashboard third in its own menu. They are pinned ahead of the ranking rather than inside it.
const PINNED = { home: -2, requests: -1 };
const rankOf = (id, order) => {
  if (id in PINNED) return PINNED[id];
  const ids = Array.isArray(order) ? order.map(String) : [];
  const i = ids.indexOf(id);
  return i < 0 ? 99 : i;
};

export function PortalShell({
  lang, t, theme, onSwapTheme, onSetLang, onSignOut,
  view, onView, customerName, unread = 0, alerts = 0, alertList = [], onAlert, token, order, suggestions, children,
}) {
  const rtl = lang === 'ar';
  const [moreOpen, setMoreOpen] = useState(false);
  const [bellOpen, setBellOpen] = useState(false);
  const [asstOpen, setAsstOpen] = useState(false);
  const [seed, setSeed] = useState('');
  const [q, setQ] = useState('');
  const searchRef = useRef(null);
  // The three panels move together through src/lib/portalPanels.ts: on a phone a tab, the More sheet or Escape never
  // leaves the full-width assistant covering what was chosen (measured 10 Nov 2026, e2e run b9d7d1d5).
  const panelsNow = useRef({ asst: false, more: false, bell: false });
  panelsNow.current = { asst: asstOpen, more: moreOpen, bell: bellOpen };
  const setPanels = (p) => {
    setAsstOpen(p.asst); setMoreOpen(p.more); setBellOpen(p.bell);
    if (!p.asst) setSeed('');
  };

  // FOCUS COMES BACK TO THE CONTROL THAT OPENED THE PANEL (a11y review, 18 Sep 2026).
  // Choosing a destination in the More sheet, or an alert in the bell list, or closing the
  // assistant, unmounts the very element that holds focus — `go()` sets moreOpen false and the
  // whole `{moreOpen && …}` block goes with it. A browser then drops focus on <body>, so a
  // keyboard user's next Tab restarts at the top of the document instead of continuing from the
  // control they were on (WCAG 2.4.3). One place, because all three close down several paths:
  // Escape, the backdrop, and the choice itself.
  const moreBtn = useRef(null);
  // THE TAB BAR PUBLISHES ITS REAL HEIGHT (E2E stage 1 D7 follow-up, 30 Sep 2026): it measured 69px on production
  // at 375px, not the 56 the panel assumed, so the panel covered its top 13px. offsetHeight includes the
  // safe-area padding, and is 0 when the bar is hidden (md and up), where panels sit on the bottom edge.
  // A callback ref, not an effect: the bar mounts after the shell's first render (measured: an effect on [] saw null).
  const tabBarObs = useRef<ResizeObserver | null>(null);
  const tabBar = useRef((el: HTMLElement | null) => {
    tabBarObs.current?.disconnect(); tabBarObs.current = null;
    const root = document.documentElement.style;
    if (!el) { root.removeProperty('--qd-tabbar-h'); return; }
    const set = () => root.setProperty('--qd-tabbar-h', el.offsetHeight + 'px');
    // border-box: the safe-area inset is PADDING, which a content-box observer never reports (measured: 57px kept after +34px).
    set(); tabBarObs.current = new ResizeObserver(set); tabBarObs.current.observe(el, { box: 'border-box' });
  }).current;   // one stable callback, so React does not detach and re-attach it on every render
  const bellBtn = useRef(null);
  const wasOpen = useRef({ more: false, bell: false, asst: false });
  useEffect(() => {
    const back = (was, now, el) => {
      if (was && !now && el && (document.activeElement === document.body || !document.activeElement)) el.focus();
      return now;
    };
    wasOpen.current = {
      more: back(wasOpen.current.more, moreOpen, moreBtn.current),
      bell: back(wasOpen.current.bell, bellOpen, bellBtn.current),
      asst: back(wasOpen.current.asst, asstOpen, searchRef.current),
    };
  }, [moreOpen, bellOpen, asstOpen]);

  // A placeholder that says what the field can do is the point of the field — and at 375px
  // "Ask about your requests, quotes or documents…" renders as "Ask about your", which says
  // nothing and looks broken. A placeholder cannot be set per breakpoint in CSS, so it is set here.
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    // The retired collapse preference is cleared so a stale '1' left in a browser means nothing.
    try { localStorage.removeItem('qd-nav-collapsed'); } catch (_e) {}
    const mq = window.matchMedia('(max-width: 639px)');
    const sync = () => setNarrow(mq.matches);
    sync(); mq.addEventListener('change', sync);
    return () => mq.removeEventListener('change', sync);
  }, []);
  // Cmd/Ctrl+K puts the cursor in the assistant field. The shortcut exists because the field is the
  // primary way to use the portal, not a search box bolted onto one.
  useEffect(() => {
    const onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && String(e.key).toLowerCase() === 'k') { e.preventDefault(); if (searchRef.current) searchRef.current.focus(); }
      if (e.key === 'Escape') setPanels(afterEscape(panelsNow.current));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const go = (id) => { setPanels(afterNavigate(panelsNow.current, narrow)); onView(id); };
  const submitAsk = (e) => {
    e.preventDefault();
    const text = q.trim(); if (!text) { setAsstOpen(true); return; }
    setSeed(text); setQ(''); setAsstOpen(true);
  };

  const isActive = (id) => view === id || (id === 'home' && (view === '' || view === 'home'));
  // The name wraps rather than truncates: "What you may need next" cut to "What you may ne…" is
  // the same unreadable navigation this change exists to remove, just shorter.
  const NavButton = ({ item }) => {
    const Icon = item.icon;
    const active = isActive(item.id);
    return (
      <button
        type="button"
        data-nav-id={item.id}
        onClick={() => go(item.id)}
        aria-current={active ? 'page' : undefined}
        style={{ order: rankOf(item.id, order) }}
        className={cn(
          'group relative flex min-h-11 w-full items-center gap-2.5 rounded-xl px-3 py-2 text-[14px] font-medium transition-colors duration-200',
          'focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
          active ? 'bg-primary/14 font-semibold text-primary' : 'text-foreground/80 hover:bg-secondary/50 hover:text-foreground',
        )}
      >
        {/* The active marker is on the INLINE START edge so it lands on the correct side in Arabic. */}
        {active ? <span className="absolute inset-y-1.5 inset-s-0 w-[3px] rounded-full bg-primary" aria-hidden /> : null}
        <Icon className="h-4 w-4 shrink-0 opacity-70" aria-hidden />
        <span className="min-w-0 flex-1 wrap-break-word text-start leading-snug">{t(item.label)}</span>
        {item.badge === 'unread' && unread > 0
          ? <span className="rounded-full bg-primary px-1.5 py-0.5 text-[10px] font-bold text-primary-foreground tabular-nums">{unread}</span>
          : null}
      </button>
    );
  };

  const mobileItems = NAV_GROUPS.flatMap((g) => g.items).filter((i) => MOBILE_PRIMARY.includes(i.id));
  const overflowGroups = NAV_GROUPS
    .map((g) => ({ ...g, items: g.items.filter((i) => !MOBILE_PRIMARY.includes(i.id)) }))
    .filter((g) => g.items.length);

  return (
    <div className="flex min-h-screen w-full">
      {/* ── SIDEBAR (desktop) ─────────────────────────────────────────────────────────────── */}
      {/* One width, always labelled. 240px at tablet leaves the 768px main column 528px; 264px
          from 1024 up. There is no icon-only state to fall into. */}
      <nav
        aria-label={t('nav_main')}
        className="sticky top-0 hidden h-screen w-[240px] shrink-0 flex-col border-e border-border bg-card/80 md:flex lg:w-[264px]"
      >
        <div className="flex items-center gap-2 px-4 py-4">
          <BrandMark className="h-9 w-9 shrink-0" />
          <div className="min-w-0">
            <div className="truncate font-head text-[15px] font-extrabold leading-tight text-foreground">QuotesDone</div>
            <div className="truncate text-[11px] text-muted-foreground">{t('brand_sub')}</div>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-4">
          {NAV_GROUPS.map((g) => (
            <div key={g.caption} role="group" aria-labelledby={'qd-nav-' + g.caption} className="mb-4">
              {/* A heading in plain words and sentence case — not monospace capitals. */}
              <div id={'qd-nav-' + g.caption} className="px-3 pb-1 text-[12.5px] font-semibold text-muted-foreground">{t(g.caption)}</div>
              <div className="flex flex-col gap-0.5">
                {g.items.map((item) => <NavButton key={item.id} item={item} />)}
              </div>
            </div>
          ))}
        </div>
      </nav>

      {/* ── MAIN COLUMN ───────────────────────────────────────────────────────────────────── */}
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 border-b border-border bg-background/95 shadow-e1">
          <div className="flex items-center gap-2 px-3 py-2.5 sm:gap-3 sm:px-5">
            <BrandMark className="h-9 w-9 shrink-0 md:hidden" />

            {/* THE ASSISTANT FIELD — the widest element on the page, by design. In the reference
                the founder supplied, AI search is the primary surface; ours was a bubble in a
                corner, which is half of why he called it a chat bot. */}
            <form onSubmit={submitAsk} className="min-w-0 flex-1" role="search">
              <label className="sr-only" htmlFor="qd-ask">{t('ask_ph')}</label>
              <div className="group relative flex items-center">
                <Sparkles className="pointer-events-none absolute inset-s-3.5 h-4 w-4 text-primary" aria-hidden />
                <input
                  id="qd-ask" ref={searchRef} value={q} onChange={(e) => setQ(e.target.value)}
                  placeholder={narrow ? t('ask_ph_short') : t('ask_ph')} autoComplete="off"
                  className={cn(
                    'h-11 w-full rounded-btn border border-input bg-card ps-11 pe-3 sm:pe-16 text-[13.5px] text-foreground shadow-e1',
                    'placeholder:text-muted-foreground focus-visible:outline-hidden',
                    'focus-visible:border-primary/50 focus-visible:ring-2 focus-visible:ring-primary/25',
                    'transition-[border-color,box-shadow] duration-200',
                  )}
                />
                <kbd className="pointer-events-none absolute inset-e-3 hidden rounded border border-border bg-secondary/60 px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground sm:block">⌘K</kbd>
              </div>
            </form>

            {/* A BELL MUST SHOW WHAT IT COUNTS. customer_portal returns the alerts themselves, not
                only alerts_count, so the dot has a list behind it. A notification control that
                opens something other than the notifications is the same defect this codebase keeps
                finding: an instrument reporting on a different subject to the one it names. */}
            <div className="relative shrink-0">
              <button type="button" ref={bellBtn} onClick={() => setBellOpen((v) => !v)}
                aria-label={t('alerts_label')} aria-expanded={bellOpen}
                className="relative grid h-10 w-10 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-secondary/50 hover:text-foreground focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring">
                <Bell className="h-[18px] w-[18px]" aria-hidden />
                {alerts > 0 ? <span className="absolute inset-e-2 top-2 h-2 w-2 rounded-full bg-primary ring-2 ring-background" aria-hidden /> : null}
              </button>
              {bellOpen && (
                <>
                  <button type="button" aria-label={t('close')} onClick={() => setBellOpen(false)} className="fixed inset-0 z-40 cursor-default" />
                  <div className="absolute inset-e-0 z-50 mt-2 w-[min(360px,calc(100vw-24px))] overflow-hidden rounded-xl border border-border bg-card shadow-lg motion-safe:animate-in motion-safe:fade-in motion-safe:slide-in-from-top-1 motion-safe:duration-200">
                    <div className="border-b border-border px-4 py-2.5 text-[12px] font-bold uppercase tracking-[0.08em] text-muted-foreground/70">{t('alerts_label')}</div>
                    {!alertList.length ? (
                      <p className="px-4 py-4 text-[13px] text-muted-foreground">{t('attention_none')}</p>
                    ) : (
                      <ul className="max-h-[60vh] divide-y divide-border overflow-y-auto">
                        {/* Each notification opens what it is about — the request it names —
                            through the same onAlert the Overview's alert cards use. */}
                        {alertList.map((a, i) => (
                          <li key={i}>
                            <button type="button" onClick={() => { setBellOpen(false); if (onAlert) onAlert(a); }}
                              className="flex w-full items-start gap-3 px-4 py-3 text-start transition-colors hover:bg-secondary/40 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring">
                              <span className={cn('mt-1.5 h-2 w-2 shrink-0 rounded-full',
                                a.severity === 'high' ? 'bg-danger' : a.severity === 'medium' ? 'bg-warn' : 'bg-primary')} aria-hidden />
                              <span className="min-w-0 flex-1">
                                <span className="block text-[13px] font-semibold text-foreground">{a.title}</span>
                                {a.detail ? <span className="mt-0.5 block text-[12px] leading-relaxed text-muted-foreground">{a.detail}</span> : null}
                              </span>
                              <ChevronRight className={cn('mt-1 h-3.5 w-3.5 shrink-0 text-muted-foreground', rtl && 'rotate-180')} aria-hidden />
                            </button>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                </>
              )}
            </div>

            {/* Its name is the customer's INITIAL below lg, where the name span is hidden — one
                letter, for a control that opens Account (a11y review, 18 Sep 2026). */}
            <button type="button" onClick={() => go('account')} aria-label={t('mod_account')}
              className="flex min-h-11 shrink-0 items-center gap-2 rounded-xl py-1 ps-1 pe-2 transition-colors hover:bg-secondary/50 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring">
              <span className="grid h-8 w-8 place-items-center rounded-full bg-primary/15 text-[12px] font-bold text-primary">
                {String(customerName || '?').trim().charAt(0).toUpperCase()}
              </span>
              <span dir="auto" className="hidden max-w-[140px] truncate text-start text-[13px] font-semibold text-foreground lg:block">{customerName || ''}</span>
            </button>

            <div className="hidden shrink-0 items-center gap-1 sm:flex">
              {/* h-11 w-11: 44px, the minimum tap target. size="sm" made these 32px (CP-13). */}
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={() => onSetLang(rtl ? 'en' : 'ar')} aria-label={rtl ? 'English' : 'العربية'} title={t('lang_note')}>{rtl ? 'EN' : 'ع'}</Button>
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={onSwapTheme}
                aria-label={theme === 'dark' ? t('theme_light') : t('theme_dark')}>
                {theme === 'dark' ? <Sun className="h-4 w-4" aria-hidden /> : <Moon className="h-4 w-4" aria-hidden />}
              </Button>
              <Button variant="ghost" size="sm" className="h-11 w-11 px-0" onClick={onSignOut} aria-label={t('signout')}><LogOut className={cn('h-4 w-4', rtl && 'rotate-180')} aria-hidden /></Button>
            </div>
          </div>
        </header>

        {/* id="main" — the layout's skip link targets #main; without it the first focusable element
            on the signed-in customer portal did nothing (measured 18 Sep 2026). */}
        <main id="main" className="min-w-0 flex-1 pb-[calc(6rem+env(safe-area-inset-bottom))] md:pb-8">{children}</main>
      </div>

      {/* ── MOBILE TAB BAR ────────────────────────────────────────────────────────────────── */}
      {/* Its own name, not the sidebar's. Only one of the two is in the accessibility tree at a
          time (the other is display:none), but two landmarks that answer to "Portal navigation"
          is one CSS regression away from being a real defect (a11y review, 18 Sep 2026). */}
      <nav ref={tabBar} aria-label={t('nav_main_bar')}
        className="fixed inset-x-0 bottom-0 z-30 flex items-stretch border-t border-border bg-card pb-[env(safe-area-inset-bottom)] shadow-e2 md:hidden">
        {mobileItems.map((item) => {
          const Icon = item.icon;
          const active = isActive(item.id);
          return (
            <button key={item.id} type="button" onClick={() => go(item.id)} aria-current={active ? 'page' : undefined}
              className={cn('relative flex min-h-[56px] min-w-0 flex-1 flex-col items-center justify-center gap-1 px-0.5 py-2 text-[11.5px] font-semibold leading-tight transition-colors',
                'focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
                active ? 'text-primary' : 'text-foreground/75')}>
              <Icon className="h-[18px] w-[18px]" aria-hidden />
              {/* Wraps to a second line before it would ever be cut. */}
              <span className="max-w-full wrap-break-word text-center">{t(item.label)}</span>
              {/* The dot is decoration; the COUNT is the information, and the sidebar says it out
                  loud (line above). A phone must not tell a screen-reader user less than a desktop
                  does about the same state (a11y review, 18 Sep 2026). */}
              {item.badge === 'unread' && unread > 0 ? <>
                <span className="absolute inset-e-[22%] top-1.5 h-2 w-2 rounded-full bg-primary" aria-hidden />
                <span className="sr-only">{unread}</span>
              </> : null}
              {active ? <span className="absolute inset-x-5 top-0 h-[2px] rounded-full bg-primary" aria-hidden /> : null}
            </button>
          );
        })}
        <button type="button" ref={moreBtn} onClick={() => setPanels(afterMoreToggle(panelsNow.current))} aria-expanded={moreOpen} aria-controls="qd-nav-more"
          className={cn('flex min-h-[56px] min-w-0 flex-1 flex-col items-center justify-center gap-1 px-0.5 py-2 text-[11.5px] font-semibold leading-tight transition-colors',
            'focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring',
            moreOpen ? 'text-primary' : 'text-foreground/75')}>
          {moreOpen ? <X className="h-[19px] w-[19px]" aria-hidden /> : <Menu className="h-[19px] w-[19px]" aria-hidden />}
          <span>{t('nav_more')}</span>
        </button>
      </nav>

      {moreOpen && (
        <>
          <button type="button" aria-label={t('close')} onClick={() => setMoreOpen(false)}
            className="fixed inset-0 z-30 bg-background/80 md:hidden" />
          {/* THE SHEET GIVES FULL NAMES, one per row: a two-column grid cut "What you may need
              next" at 375px. */}
          <nav id="qd-nav-more" aria-label={t('nav_more_title')}
            className="fixed inset-x-0 bottom-(--qd-tabbar-h,0px) z-40 max-h-[70vh] overflow-y-auto rounded-t-2xl border-t border-border bg-card p-4 motion-safe:animate-in motion-safe:slide-in-from-bottom-6 motion-safe:duration-300 md:hidden">
            {overflowGroups.map((g) => (
              <div key={g.caption} role="group" aria-labelledby={'qd-more-' + g.caption} className="mb-3">
                <div id={'qd-more-' + g.caption} className="px-1 pb-1 text-[12.5px] font-semibold text-muted-foreground">{t(g.caption)}</div>
                <div className="flex flex-col gap-1">
                  {g.items.map((item) => {
                    const Icon = item.icon;
                    const active = isActive(item.id);
                    return (
                      <button key={item.id} type="button" onClick={() => go(item.id)} aria-current={active ? 'page' : undefined}
                        className={cn('flex min-h-11 items-center gap-2.5 rounded-xl border px-3 py-2 text-start text-[14px] font-medium',
                          'focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring',
                          active ? 'border-primary/40 bg-primary/12 text-primary' : 'border-border bg-secondary/25 text-foreground')}>
                        <Icon className="h-4 w-4 shrink-0 opacity-70" aria-hidden />
                        <span className="min-w-0 flex-1 wrap-break-word leading-snug">{t(item.label)}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="mt-1 flex items-center gap-2 border-t border-border pt-3">
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={() => onSetLang(rtl ? 'en' : 'ar')}>{rtl ? 'English' : 'العربية'}</Button>
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={onSwapTheme}>{theme === 'dark' ? t('theme_light') : t('theme_dark')}</Button>
              <Button variant="outline" size="sm" className="h-11 flex-1" onClick={onSignOut}>{t('signout')}</Button>
            </div>
            <p className="pt-1 text-[11.5px] leading-snug text-muted-foreground">{t('lang_note')}</p>
          </nav>
        </>
      )}

      <AssistantPanel token={token} lang={lang} open={asstOpen} seed={seed} t={t} suggestions={suggestions}
        onClose={() => { setAsstOpen(false); setSeed(''); }} />
    </div>
  );
}
