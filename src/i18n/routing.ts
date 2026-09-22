import { createElement, type ComponentProps } from 'react';
import { defineRouting } from 'next-intl/routing';
import { createNavigation } from 'next-intl/navigation';

// ONE source of truth for locales. Add a language here and every page gets it —
// no duplicated pages. 'en' is the default (served at /), 'ar' served at /ar.
export const routing = defineRouting({
  locales: ['en', 'ar'],
  defaultLocale: 'en',
  localePrefix: 'as-needed',
  // A REQUESTED URL IS THE ANSWER (WEB-15). Measured 22 Sep 2026: with next-intl's default
  // localeDetection, a browser sending Accept-Language: ar was 307'd from /terms to /ar/terms, so the
  // English legal page could not be opened — and a shared /terms link showed a different document to
  // different people. The language is chosen by the URL (and the LangSwitch, which writes the cookie),
  // never guessed from the browser.
  localeDetection: false
});

const nav = createNavigation(routing);
export const { usePathname, useRouter } = nav;

// NO PREFETCH INTO THE APP SHELLS (website audit 14 Sep 2026). The public pages link to /me,
// /portal and /supplier from the header, hero, two-sided block and footer, and Next prefetches every
// in-viewport <Link> once the page is idle. Measured locally (next build + Lighthouse 12 mobile, / ):
// those prefetches pulled the portals' own chunks — three.js, motion and the portal UI, ~260 KB,
// 100% unused by the page being loaded — into the homepage's first-load window. The list mirrors
// APP_SHELLS in next.config.mjs (the same three paths are served noindex). Every other link keeps
// the default prefetch; an explicit `prefetch` prop still wins.
const APP_SHELLS = ['/me', '/portal', '/supplier'];
const isAppShell = (href: unknown) => {
  const p = typeof href === 'string' ? href : (href as { pathname?: string } | null)?.pathname;
  return typeof p === 'string' && APP_SHELLS.some((s) => p === s || p.startsWith(s + '/') || p.startsWith(s + '?'));
};

export function Link(props: ComponentProps<typeof nav.Link>) {
  return createElement(nav.Link, props.prefetch === undefined && isAppShell(props.href) ? { ...props, prefetch: false } : props);
}
