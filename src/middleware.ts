import createMiddleware from 'next-intl/middleware';
import { NextResponse, type NextRequest } from 'next/server';
import { routing } from './i18n/routing';
import { AE_DOMAIN_SERVES_SITE, aeRedirectTarget } from './lib/domains';

const intl = createMiddleware(routing);

// UAE visitors on quotesdone.com go to quotesdone.ae (TDRA, founder 14 Sep 2026). Gated by
// AE_DOMAIN_SERVES_SITE in src/lib/domains.ts; every page lives under [locale], so the matcher
// below already covers every page the rule is meant for.
// THE SIGNED-IN SHELLS STILL FOLLOW THE REGISTERED LANGUAGE (23 Sep 2026, review of #855).
// routing.ts turned next-intl's localeDetection off so a requested URL is the answer: an Arabic
// browser asking for /terms gets /terms (WEB-15). That switch also stopped next-intl reading the
// NEXT_LOCALE cookie, which src/lib/documentLocale.ts writes at sign-in precisely so /me and /portal
// are SERVED in the account's language and paint the right direction in the first frame. Detection by
// header is a guess about a visitor; the cookie is a fact about an account, so only the app shells,
// and only on their unprefixed paths, follow it. Public pages never do.
const SHELLS = /^\/(me|portal)(\/|$)/;

export default function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  if (SHELLS.test(pathname) && req.cookies.get('NEXT_LOCALE')?.value === 'ar') {
    const url = req.nextUrl.clone();
    url.pathname = '/ar' + pathname;
    return NextResponse.redirect(url, 307);
  }
  const to = aeRedirectTarget({
    enabled: AE_DOMAIN_SERVES_SITE,
    host: req.headers.get('host'),
    country: req.headers.get('x-vercel-ip-country'),
    pathname: req.nextUrl.pathname,
    search: req.nextUrl.search,
    userAgent: req.headers.get('user-agent'),
  });
  return to ? NextResponse.redirect(to, 308) : intl(req);
}

export const config = {
  // Only the surfaces migrated to Next.js run through locale routing.
  // NOTE: individual blog posts (/blog/:slug) are now native pages, so they
  // must be listed here. Without the :path* entry they bypass locale routing
  // and fall through to the legacy catch-all rewrite.
  matcher: [
    '/', '/(ar|en)',
    // /os and /console were the OS admin console. The founder ruled the OS irrelevant on 8 Sep 2026
    // and it is deleted — the routes, the shell, its client and its twelve edge functions. Matching a
    // path that no longer exists costs a middleware run on every request to a 404.
    '/(ar|en)/portal', '/portal', '/(ar|en)/me', '/me', '/(ar|en)/supplier', '/supplier',
    '/terms', '/(ar|en)/terms', '/privacy', '/(ar|en)/privacy', '/cookie-policy', '/(ar|en)/cookie-policy', '/refund-policy', '/(ar|en)/refund-policy', '/supplier-agreement', '/(ar|en)/supplier-agreement', '/acceptable-use', '/(ar|en)/acceptable-use', '/disclaimer', '/(ar|en)/disclaimer', '/complaints', '/(ar|en)/complaints', '/complaints/status', '/(ar|en)/complaints/status', '/how-we-verify', '/(ar|en)/how-we-verify',
    '/about', '/(ar|en)/about', '/contact', '/(ar|en)/contact', '/faq', '/(ar|en)/faq', '/services', '/(ar|en)/services', '/blog', '/(ar|en)/blog',
    '/how-it-works', '/(ar|en)/how-it-works',
    // the two-step admin sign-in (security audit 10 Nov 2026, item 1); /ar/admin is sent to /admin by the page
    '/admin', '/(ar|en)/admin',
    // the Sealed brand book (noindex), 14 Sep 2026
    '/brand', '/(ar|en)/brand',
    '/services/:path*', '/(ar|en)/services/:path*',
    // Superseded Supplier Agreement versions (/supplier-agreement/v10, /v11) are pages a supplier who
    // accepted them must be able to read, and the sitemap lists them. Measured 22 Sep 2026: both 404'd
    // on both hosts without the /ar prefix, because only the bare /supplier-agreement was matched.
    // Prevented by: scripts/checks/every_page_is_routed_and_every_sitemap_url_is_a_page.test.mjs.
    '/supplier-agreement/:path*', '/(ar|en)/supplier-agreement/:path*',
    // Superseded Customer Terms versions (/terms/v9 from 6 Oct 2026), for the same reason.
    '/terms/:path*', '/(ar|en)/terms/:path*',
    // Superseded Privacy, Refund and Disclaimer versions (/privacy/v1.6 etc. from 19 Oct 2026), for the same reason.
    '/privacy/:path*', '/(ar|en)/privacy/:path*', '/refund-policy/:path*', '/(ar|en)/refund-policy/:path*', '/disclaimer/:path*', '/(ar|en)/disclaimer/:path*',
    '/blog/:path*', '/(ar|en)/blog/:path*',
    // EVERY OTHER PATH, SO A WRONG URL GETS THE DESIGNED 404 (website audit 10 Nov 2026, customer_support).
    // Measured on production: /zz-nope and /about/zz served the framework's bare white "404: This page could
    // not be found." with no lang, no header and no way onward. A path no entry above names never reaches
    // next-intl, so it is read as [locale]='zz-nope' and the layout rejects it before [locale]/[...rest] can
    // render [locale]/not-found.tsx. /ar/zz-nope and /services/zz-nope already got the designed page.
    // Left out: api and u (route handlers outside [locale]), m/ (the brand-storage rewrite in
    // next.config.mjs), Next's and Vercel's own paths, any path with a dot (files in public/ and app/,
    // robots.txt, sitemap.xml, favicon.ico), and the social cards: /en/opengraph-image is the og:image URL
    // and next-intl would redirect it to the unprefixed path (next.config.mjs keeps the same exception).
    // Kept by: scripts/checks/a_wrong_url_gets_the_designed_404_in_its_language.test.mjs.
    '/((?!api|u/|m/|_next|_vercel|.*\\..*|.*(?:opengraph|twitter)-image).*)'
  ]
};
