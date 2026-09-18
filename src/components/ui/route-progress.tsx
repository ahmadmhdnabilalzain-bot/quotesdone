'use client';
// THE TOP BAR FOR ROUTE CHANGES. Part of the one loading system — see ui/busy.tsx for the rules,
// docs/CONVENTIONS_LOADING.md for the convention.
//
// Before this, a route change was blank-to-blank: `find src/app -name loading.tsx` returned zero
// files, so every header link, hero CTA and `router.push` into /me or /portal (the two heaviest
// client bundles on the site) gave the visitor nothing at all for the whole download.
//
// It listens at the document, capture phase, for a click on a same-origin anchor. That covers every
// <Link> on the site without touching one of them. Call sites that navigate imperatively
// (router.push / router.replace) call `startRouteProgress()` themselves.
//
// IT DELIBERATELY USES NO ROUTER HOOK. The first version read `usePathname()` from @/i18n/routing to
// learn when the route landed, and that BROKE `next build`: this component is mounted in the root
// locale layout, so the hook ran during static generation of all 501 pages and threw on the blog
// leaves ("Export encountered an error on /[locale]/blog/[slug]/page"). Watching
// `window.location.href` instead is client-only by construction, needs no Suspense boundary, and
// fixes a second defect for free — `usePathname` strips the query string, so a navigation that
// changed only `?filter=…` would have left the bar creeping until the stuck ceiling.
//
// It resolves on the URL changing, and on a hard ceiling (STUCK_MS). A bar that creeps to 90% and
// stays there forever would be exactly the "cannot tell broken from idle" indicator this
// instruction exists to remove.
import * as React from 'react';
import { SHOW_AFTER_MS, MIN_SHOW_MS } from '@/components/ui/busy-timing';

const START_EVENT = 'qd:route-start';
/** Tell the bar a navigation began. For imperative router.push / router.replace call sites. */
export function startRouteProgress() {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(START_EVENT));
}

// A route change that has not landed in 20s is not "still loading", it is broken. Resolve the bar
// so the page looks idle (and reachable) rather than permanently mid-flight.
const STUCK_MS = 20000;
// How often we ask whether the URL changed. Cheap (a string compare), and only while a navigation
// is actually in flight — the interval is cleared the moment the bar resolves.
const POLL_MS = 120;

/** `label` is the announced status text; the root layout passes it in the page's own language. */
export function RouteProgress({ label = 'Loading' }: { label?: string }) {
  const [pct, setPct] = React.useState(0);       // 0 = hidden
  const timers = React.useRef<ReturnType<typeof setTimeout>[]>([]);
  const poll = React.useRef<ReturnType<typeof setInterval> | undefined>(undefined);
  const startedAt = React.useRef(0);             // 0 = no navigation in flight (synchronous guard)
  const shownAt = React.useRef(0);
  const from = React.useRef('');

  const clearAll = React.useCallback(() => {
    timers.current.forEach(clearTimeout); timers.current = [];
    clearInterval(poll.current); poll.current = undefined;
  }, []);

  const finish = React.useCallback(() => {
    if (!startedAt.current) return;
    clearAll();
    startedAt.current = 0;
    if (!shownAt.current) { setPct(0); return; }           // never shown — nothing to resolve
    const held = Math.max(0, MIN_SHOW_MS - (Date.now() - shownAt.current));
    timers.current.push(setTimeout(() => {
      setPct(100);
      timers.current.push(setTimeout(() => { setPct(0); shownAt.current = 0; }, 220));
    }, held));
  }, [clearAll]);

  // The guard is a ref set SYNCHRONOUSLY, for the same reason useBusy.run uses one: two clicks (or a
  // click plus a startRouteProgress()) inside one batch must not restart the timer chain and push
  // both the 150ms delay and the 20s ceiling out from the second event instead of the first.
  const begin = React.useCallback(() => {
    if (startedAt.current) return;
    clearAll();
    startedAt.current = Date.now();
    from.current = window.location.href;
    poll.current = setInterval(() => {
      if (window.location.href !== from.current) finish();
    }, POLL_MS);
    timers.current.push(setTimeout(() => {                  // rule 1 — nothing under 150ms
      shownAt.current = Date.now();
      setPct(12);
      // Creep, never arrive: real progress is unknowable for a route change, so the bar states
      // "working", not "42% done". It only reaches 100 when the route actually lands.
      ([[180, 42], [520, 66], [1100, 80], [2400, 90]] as const).forEach(([ms, p]) => {
        timers.current.push(setTimeout(() => setPct(p), ms));
      });
    }, SHOW_AFTER_MS));
    timers.current.push(setTimeout(finish, STUCK_MS));
  }, [clearAll, finish]);

  React.useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const a = (e.target as Element | null)?.closest?.('a');
      if (!a) return;
      const href = a.getAttribute('href');
      if (!href || a.hasAttribute('download') || (a.getAttribute('target') || '') === '_blank') return;
      if (href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('tel:')) return;
      let url: URL;
      try { url = new URL(href, window.location.href); } catch { return; }
      if (url.origin !== window.location.origin) return;
      if (url.pathname === window.location.pathname && url.search === window.location.search) return;
      begin();
    };
    document.addEventListener('click', onClick, true);
    window.addEventListener(START_EVENT, begin);
    return () => { document.removeEventListener('click', onClick, true); window.removeEventListener(START_EVENT, begin); };
  }, [begin]);

  React.useEffect(() => () => { timers.current.forEach(clearTimeout); clearInterval(poll.current); }, []);

  // TWO indicators, because a bar is not an announcement. The bar is decorative and aria-hidden —
  // a `role="progressbar"` here would spend its whole (sub-second) life unfocused and outside any
  // live region, so no screen reader would ever meet it. The status node is the accessible half: it
  // is always in the DOM so the live region exists BEFORE its text changes, which is what makes a
  // polite announcement fire at all.
  return (
    <>
      {pct ? <div className="qd-routebar" aria-hidden style={{ ['--qd-progress' as string]: String(pct / 100) }} /> : null}
      <span role="status" aria-live="polite" className="sr-only">{pct && pct < 100 ? label : ''}</span>
    </>
  );
}
