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
    // the Sealed brand book (noindex), 14 Sep 2026
    '/brand', '/(ar|en)/brand',
    '/services/:path*', '/(ar|en)/services/:path*',
    // Superseded Supplier Agreement versions (/supplier-agreement/v10, /v11) are pages a supplier who
    // accepted them must be able to read, and the sitemap lists them. Measured 22 Sep 2026: both 404'd
    // on both hosts without the /ar prefix, because only the bare /supplier-agreement was matched.
    // Prevented by: scripts/checks/every_page_is_routed_and_every_sitemap_url_is_a_page.test.mjs.
    '/supplier-agreement/:path*', '/(ar|en)/supplier-agreement/:path*',
    '/blog/:path*', '/(ar|en)/blog/:path*'
  ]
};
